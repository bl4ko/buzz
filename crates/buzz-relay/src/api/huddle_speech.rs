#![allow(clippy::result_large_err)]
use std::{
    sync::{Arc, LazyLock},
    time::Duration,
};

use axum::{
    body::Bytes,
    extract::{Path, State},
    http::{HeaderMap, StatusCode},
    response::{IntoResponse, Response},
    Json,
};
use base64::Engine;
use serde::Deserialize;
use serde_json::json;
use tokio::sync::Semaphore;
use uuid::Uuid;

use super::{api_error, bridge};
use crate::{nip_fi_http::admit_nip_fi_http_on_state, state::AppState};

static SPEECH_SLOTS: LazyLock<Semaphore> = LazyLock::new(|| Semaphore::new(2));

async fn speech_slot() -> Result<tokio::sync::SemaphorePermit<'static>, Response> {
    tokio::time::timeout(Duration::from_secs(10), SPEECH_SLOTS.acquire())
        .await
        .ok()
        .and_then(Result::ok)
        .ok_or_else(|| {
            api_error(StatusCode::TOO_MANY_REQUESTS, "speech service busy").into_response()
        })
}
static CLIENT: LazyLock<Result<reqwest::Client, reqwest::Error>> = LazyLock::new(|| {
    reqwest::Client::builder()
        .timeout(Duration::from_secs(60))
        .redirect(reqwest::redirect::Policy::none())
        .build()
});
const MAX_AUDIO: usize = 1_440_128;
const MAX_OUTPUT: usize = 8 * 1024 * 1024;
const VOICES: &[&str] = &["am_michael", "af_heart", "bm_george"];

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Transcription {
    audio: String,
    #[serde(rename = "agent_name")]
    _agent_name: Option<String>,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Speech {
    text: String,
    voice: Option<String>,
}

async fn authorize(
    state: &Arc<AppState>,
    channel: Uuid,
    headers: &HeaderMap,
    body: &[u8],
    operation: &str,
) -> Result<(), Response> {
    let host = headers
        .get("host")
        .and_then(|h| h.to_str().ok())
        .unwrap_or("");
    let tenant = crate::tenant::bind_community(&state.db, host)
        .await
        .map_err(|_| api_error(StatusCode::NOT_FOUND, "community not found").into_response())?;
    let url = bridge::nip98_expected_url(
        &state.config.relay_url,
        &tenant,
        &format!("/huddle/{channel}/{operation}"),
    );
    let admission = admit_nip_fi_http_on_state(
        state,
        headers,
        bridge::make_nip98_closure_for_admission(
            headers.clone(),
            "POST",
            url,
            Some(body.to_vec()),
            true,
            true,
        ),
    )?;
    let pubkey = *admission.proven_pubkey();
    let (event_id, created_at) = admission.into_extra();
    bridge::enforce_http_admission(state, &tenant, &pubkey)
        .await
        .map_err(IntoResponse::into_response)?;
    bridge::check_nip98_replay(state, &tenant, event_id)
        .await
        .map_err(IntoResponse::into_response)?;
    super::relay_members::enforce_relay_membership(
        state,
        tenant.community(),
        &pubkey.to_bytes(),
        super::relay_members::extract_auth_tag_header(headers),
        created_at,
    )
    .await
    .map_err(IntoResponse::into_response)?;
    let child = state
        .db
        .get_channel(tenant.community(), channel)
        .await
        .map_err(|_| api_error(StatusCode::NOT_FOUND, "huddle not found").into_response())?;
    let member = state
        .is_member_cached(tenant.community(), channel, &pubkey.to_bytes())
        .await
        .map_err(|_| {
            api_error(StatusCode::SERVICE_UNAVAILABLE, "membership unavailable").into_response()
        })?;
    let active = state
        .audio_rooms
        .get(tenant.community(), channel)
        .is_some_and(|room| {
            room.roster_snapshot()
                .peers
                .iter()
                .any(|peer| peer.pubkey == pubkey.to_hex())
        });
    if child.ttl_seconds.is_none() || child.archived_at.is_some() || !member || !active {
        return Err(
            api_error(StatusCode::FORBIDDEN, "active huddle membership required").into_response(),
        );
    }
    Ok(())
}

fn read_u32(bytes: &[u8], offset: usize) -> u32 {
    u32::from_le_bytes([
        bytes[offset],
        bytes[offset + 1],
        bytes[offset + 2],
        bytes[offset + 3],
    ])
}
fn read_u16(bytes: &[u8], offset: usize) -> u16 {
    u16::from_le_bytes([bytes[offset], bytes[offset + 1]])
}
fn valid_wav(bytes: &[u8]) -> bool {
    wav_pcm(bytes).is_some()
}

/// Returns the sample rate and PCM data range of a bounded mono PCM16 WAV.
fn wav_pcm(bytes: &[u8]) -> Option<(usize, std::ops::Range<usize>)> {
    if bytes.len() < 44
        || bytes.len() > MAX_AUDIO
        || &bytes[..4] != b"RIFF"
        || &bytes[8..12] != b"WAVE"
        || read_u32(bytes, 4) as usize != bytes.len() - 8
    {
        return None;
    }
    let mut offset = 12;
    let mut rate = None;
    let mut data = None;
    while offset + 8 <= bytes.len() {
        let size = read_u32(bytes, offset + 4) as usize;
        let start = offset + 8;
        let end = start.checked_add(size).filter(|end| *end <= bytes.len())?;
        if &bytes[offset..offset + 4] == b"fmt " {
            if size < 16 || rate.is_some() {
                return None;
            }
            let format = read_u16(bytes, start);
            let channels = read_u16(bytes, start + 2);
            let sample_rate = read_u32(bytes, start + 4);
            let bits = read_u16(bytes, start + 14);
            let byte_rate = read_u32(bytes, start + 8);
            let alignment = read_u16(bytes, start + 12);
            if format != 1
                || channels != 1
                || bits != 16
                || !(8_000..=48_000).contains(&sample_rate)
                || byte_rate != sample_rate * 2
                || alignment != 2
            {
                return None;
            }
            rate = Some(sample_rate as usize);
        }
        if &bytes[offset..offset + 4] == b"data" {
            if data.is_some() {
                return None;
            }
            data = Some(start..end);
        }
        offset = end + size % 2;
    }
    match (rate, data) {
        (Some(rate), Some(data))
            if offset == bytes.len()
                && !data.is_empty()
                && data.len() % 2 == 0
                && data.len() <= rate * 2 * 15 =>
        {
            Some((rate, data))
        }
        _ => None,
    }
}

const SPEECH_PAD_MS: usize = 200;

/// Keeps only detected speech, padded on both sides, so the recognizer never decodes long noise.
fn speech_only(audio: &[u8], intervals: &[SpeechTimestamp]) -> Option<Vec<u8>> {
    let (rate, data) = wav_pcm(audio)?;
    let pcm = &audio[data];
    let byte = |ms: usize| (ms * rate / 1000 * 2).min(pcm.len());
    let mut kept = Vec::new();
    let mut copied = 0;
    for interval in intervals {
        let start = byte((interval.start as usize).saturating_sub(SPEECH_PAD_MS)).max(copied);
        let end = byte(interval.end as usize + SPEECH_PAD_MS);
        if start < end {
            kept.extend_from_slice(&pcm[start..end]);
            copied = end;
        }
    }
    let mut wav = Vec::with_capacity(44 + kept.len());
    wav.extend_from_slice(b"RIFF");
    wav.extend_from_slice(&(36 + kept.len() as u32).to_le_bytes());
    wav.extend_from_slice(b"WAVEfmt \x10\0\0\0\x01\0\x01\0");
    wav.extend_from_slice(&(rate as u32).to_le_bytes());
    wav.extend_from_slice(&(rate as u32 * 2).to_le_bytes());
    wav.extend_from_slice(b"\x02\0\x10\0data");
    wav.extend_from_slice(&(kept.len() as u32).to_le_bytes());
    wav.extend_from_slice(&kept);
    Some(wav)
}

async fn upstream_bytes(mut response: reqwest::Response) -> Result<Vec<u8>, Response> {
    if !response.status().is_success() {
        return Err(api_error(StatusCode::BAD_GATEWAY, "speech service failed").into_response());
    }
    let mut bytes = Vec::new();
    while let Some(chunk) = response
        .chunk()
        .await
        .map_err(|_| api_error(StatusCode::BAD_GATEWAY, "speech response failed").into_response())?
    {
        if bytes.len() + chunk.len() > MAX_OUTPUT {
            return Err(
                api_error(StatusCode::BAD_GATEWAY, "speech response too large").into_response(),
            );
        }
        bytes.extend_from_slice(&chunk);
    }
    Ok(bytes)
}

fn audio_body(fields: &[(&str, &str)], audio: &[u8], boundary: &str) -> Vec<u8> {
    let mut multipart = Vec::new();
    for (name, value) in fields {
        multipart.extend_from_slice(
            format!(
                "--{boundary}\r\nContent-Disposition: form-data; name=\"{name}\"\r\n\r\n{value}\r\n"
            )
            .as_bytes(),
        );
    }
    multipart.extend_from_slice(format!("--{boundary}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"speech.wav\"\r\nContent-Type: audio/wav\r\n\r\n").as_bytes());
    multipart.extend_from_slice(audio);
    multipart.extend_from_slice(format!("\r\n--{boundary}--\r\n").as_bytes());
    multipart
}

#[derive(Deserialize)]
struct SpeechTimestamp {
    start: u32,
    end: u32,
}

async fn transcribe_audio(
    client: &reqwest::Client,
    vad_base: &str,
    transcription_base: &str,
    model: &str,
    audio: &[u8],
) -> Result<String, Response> {
    let bytes = request_audio(
        client,
        vad_base,
        "audio/speech/timestamps",
        &[
            ("model", "silero_vad_v5"),
            ("min_speech_duration_ms", "250"),
        ],
        audio,
    )
    .await?;
    let timestamps: Vec<SpeechTimestamp> = serde_json::from_slice(&bytes).map_err(|_| {
        api_error(StatusCode::BAD_GATEWAY, "invalid speech detection response").into_response()
    })?;
    if timestamps
        .iter()
        .any(|interval| interval.start >= interval.end || interval.end > 15_000)
    {
        return Err(
            api_error(StatusCode::BAD_GATEWAY, "invalid speech detection interval").into_response(),
        );
    }
    if timestamps.is_empty() {
        return Ok(String::new());
    }
    let speech = speech_only(audio, &timestamps).ok_or_else(|| {
        api_error(StatusCode::BAD_REQUEST, "invalid speech audio").into_response()
    })?;
    let bytes = request_audio(
        client,
        transcription_base,
        "audio/transcriptions",
        &[
            ("model", model),
            ("response_format", "json"),
            ("language", "en"),
            ("to_language", "en"),
        ],
        &speech,
    )
    .await?;
    let value: serde_json::Value = serde_json::from_slice(&bytes).map_err(|_| {
        api_error(StatusCode::BAD_GATEWAY, "invalid speech response").into_response()
    })?;
    value
        .get("text")
        .and_then(|v| v.as_str())
        .map(str::to_owned)
        .ok_or_else(|| api_error(StatusCode::BAD_GATEWAY, "missing transcript").into_response())
}

async fn request_audio(
    client: &reqwest::Client,
    base: &str,
    endpoint: &str,
    fields: &[(&str, &str)],
    audio: &[u8],
) -> Result<Vec<u8>, Response> {
    let boundary = format!("buzz-{}", Uuid::new_v4());
    let response = client
        .post(format!("{}/{endpoint}", base.trim_end_matches('/')))
        .header(
            "Content-Type",
            format!("multipart/form-data; boundary={boundary}"),
        )
        .body(audio_body(fields, audio, &boundary))
        .send()
        .await
        .map_err(|_| {
            api_error(StatusCode::BAD_GATEWAY, "speech service unavailable").into_response()
        })?;
    upstream_bytes(response).await
}

pub async fn transcribe(
    State(state): State<Arc<AppState>>,
    Path(channel): Path<Uuid>,
    headers: HeaderMap,
    body: Bytes,
) -> Response {
    match transcribe_inner(state, channel, headers, body).await {
        Ok(response) => response,
        Err(response) => response,
    }
}

async fn transcribe_inner(
    state: Arc<AppState>,
    channel: Uuid,
    headers: HeaderMap,
    body: Bytes,
) -> Result<Response, Response> {
    let base = state
        .config
        .speech_transcription_base_url
        .as_deref()
        .or(state.config.speech_base_url.as_deref())
        .ok_or_else(|| {
            api_error(StatusCode::SERVICE_UNAVAILABLE, "speech service disabled").into_response()
        })?;
    authorize(&state, channel, &headers, &body, "transcribe").await?;
    let request: Transcription = serde_json::from_slice(&body).map_err(|_| {
        api_error(StatusCode::BAD_REQUEST, "invalid transcription request").into_response()
    })?;
    let audio = base64::engine::general_purpose::STANDARD
        .decode(request.audio)
        .map_err(|_| {
            api_error(StatusCode::BAD_REQUEST, "invalid audio encoding").into_response()
        })?;
    if !valid_wav(&audio) {
        return Err(api_error(
            StatusCode::BAD_REQUEST,
            "audio must be mono PCM16 WAV, at most 15 seconds",
        )
        .into_response());
    }
    let _slot = speech_slot().await?;
    let vad_base = state.config.speech_base_url.as_deref().ok_or_else(|| {
        api_error(
            StatusCode::SERVICE_UNAVAILABLE,
            "speech detection unavailable",
        )
        .into_response()
    })?;
    let client = CLIENT.as_ref().map_err(|_| {
        api_error(StatusCode::SERVICE_UNAVAILABLE, "speech client unavailable").into_response()
    })?;
    let text = transcribe_audio(
        client,
        vad_base,
        base,
        &state.config.speech_transcription_model,
        &audio,
    )
    .await?;
    Ok(Json(json!({"text": text})).into_response())
}

pub async fn speech(
    State(state): State<Arc<AppState>>,
    Path(channel): Path<Uuid>,
    headers: HeaderMap,
    body: Bytes,
) -> Response {
    match speech_inner(state, channel, headers, body).await {
        Ok(response) => response,
        Err(response) => response,
    }
}

async fn speech_inner(
    state: Arc<AppState>,
    channel: Uuid,
    headers: HeaderMap,
    body: Bytes,
) -> Result<Response, Response> {
    let base = state.config.speech_base_url.as_deref().ok_or_else(|| {
        api_error(StatusCode::SERVICE_UNAVAILABLE, "speech service disabled").into_response()
    })?;
    authorize(&state, channel, &headers, &body, "speech").await?;
    let request: Speech = serde_json::from_slice(&body).map_err(|_| {
        api_error(StatusCode::BAD_REQUEST, "invalid speech request").into_response()
    })?;
    let voice = request.voice.as_deref().unwrap_or("af_heart");
    if request.text.trim().is_empty()
        || request.text.chars().count() > 2000
        || !VOICES.contains(&voice)
    {
        return Err(
            api_error(StatusCode::BAD_REQUEST, "invalid speech text or voice").into_response(),
        );
    }
    let _slot = speech_slot().await?;
    let client = CLIENT.as_ref().map_err(|_| {
        api_error(StatusCode::SERVICE_UNAVAILABLE, "speech client unavailable").into_response()
    })?;
    let response = client.post(format!("{}/audio/speech", base.trim_end_matches('/'))).json(&json!({"input":request.text,"voice":voice,"model":"speaches-ai/Kokoro-82M-v1.0-ONNX","response_format":"wav"})).send().await.map_err(|_| api_error(StatusCode::BAD_GATEWAY, "speech service unavailable").into_response())?;
    let bytes = upstream_bytes(response).await?;
    if bytes.len() < 12 || &bytes[..4] != b"RIFF" || &bytes[8..12] != b"WAVE" {
        return Err(api_error(StatusCode::BAD_GATEWAY, "invalid speech audio").into_response());
    }
    Ok((
        [("Content-Type", "audio/wav"), ("Cache-Control", "no-store")],
        bytes,
    )
        .into_response())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn transcription_requires_speech_without_suggesting_words() {
        let body = audio_body(
            &[("model", "whisper"), ("response_format", "json")],
            b"WAV",
            "boundary",
        );
        let body = String::from_utf8(body).unwrap();
        assert!(!body.contains("name=\"vad_filter\""));
        assert!(!body.contains("name=\"prompt\""));
        assert!(!body.contains("name=\"language\""));
        assert!(body.contains("audio/wav\r\n\r\nWAV\r\n--boundary--\r\n"));
    }

    #[tokio::test]
    async fn vad_gates_transcription() {
        use std::sync::atomic::{AtomicUsize, Ordering};
        for (vad_status, vad_body, expected_calls, expected_text) in [
            (StatusCode::OK, "[]", 0, Some("")),
            (
                StatusCode::OK,
                "[{\"start\":160,\"end\":2389}]",
                1,
                Some("hello"),
            ),
            (StatusCode::OK, "[{\"start\":10,\"end\":5}]", 0, None),
            (StatusCode::OK, "[{\"start\":-1,\"end\":5}]", 0, None),
            (StatusCode::OK, "{}", 0, None),
            (StatusCode::SERVICE_UNAVAILABLE, "[]", 0, None),
        ] {
            let calls = Arc::new(AtomicUsize::new(0));
            let observed = calls.clone();
            let app =
                axum::Router::new().fallback(axum::routing::post(
                    move |uri: axum::http::Uri, body: Bytes| {
                        let observed = observed.clone();
                        async move {
                            if uri.path() == "/audio/speech/timestamps" {
                                let body = String::from_utf8_lossy(&body);
                                assert!(
                                    body.contains("name=\"min_speech_duration_ms\"\r\n\r\n250\r\n")
                                );
                                (vad_status, vad_body)
                            } else {
                                let cropped = [
                                    b"audio/wav\r\n\r\nRIFF".as_slice(),
                                    &(36u32 + 2_589 * 32).to_le_bytes(),
                                ]
                                .concat();
                                assert!(body.windows(cropped.len()).any(|part| part == cropped));
                                let body = String::from_utf8_lossy(&body);
                                assert!(body.contains("name=\"language\"\r\n\r\nen\r\n"));
                                assert!(body.contains("name=\"to_language\"\r\n\r\nen\r\n"));
                                assert!(!body.contains("name=\"prompt\""));
                                observed.fetch_add(1, Ordering::SeqCst);
                                (StatusCode::OK, "{\"text\":\"hello\"}")
                            }
                        }
                    },
                ));
            let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
            let base = format!("http://{}", listener.local_addr().unwrap());
            let server = tokio::spawn(async move { axum::serve(listener, app).await.unwrap() });
            let result = transcribe_audio(
                &reqwest::Client::new(),
                &base,
                &base,
                "qwen",
                &silent_wav(3_000),
            )
            .await;
            server.abort();
            assert_eq!(calls.load(Ordering::SeqCst), expected_calls, "{vad_body}");
            match expected_text {
                Some(text) => assert_eq!(result.unwrap(), text),
                None => assert_eq!(result.unwrap_err().status(), StatusCode::BAD_GATEWAY),
            }
        }
    }

    fn silent_wav(milliseconds: usize) -> Vec<u8> {
        speech_only(
            &[
                b"RIFF\x26\x00\x00\x00WAVEfmt \x10\x00\x00\x00\x01\x00\x01\x00\x80\x3e\x00\x00\x00\x7d\x00\x00\x02\x00\x10\x00data\x02\x00\x00\x00".as_slice(),
                &[0, 0],
            ]
            .concat(),
            &[],
        )
        .map(|mut wav| {
            let pcm = vec![0u8; milliseconds * 32];
            wav.truncate(40);
            wav.extend_from_slice(&(pcm.len() as u32).to_le_bytes());
            wav.extend_from_slice(&pcm);
            let length = (wav.len() - 8) as u32;
            wav[4..8].copy_from_slice(&length.to_le_bytes());
            wav
        })
        .unwrap()
    }

    #[test]
    fn speech_only_keeps_padded_speech() {
        let mut wav = silent_wav(3_000);
        for (index, sample) in wav[44..].chunks_mut(2).enumerate() {
            sample.copy_from_slice(&(index as u16).to_le_bytes());
        }
        let cropped = speech_only(
            &wav,
            &[
                SpeechTimestamp {
                    start: 100,
                    end: 400,
                },
                SpeechTimestamp {
                    start: 500,
                    end: 900,
                },
                SpeechTimestamp {
                    start: 2_800,
                    end: 2_950,
                },
            ],
        )
        .unwrap();
        assert!(valid_wav(&cropped));
        let samples: Vec<u16> = cropped[44..]
            .chunks(2)
            .map(|pair| u16::from_le_bytes([pair[0], pair[1]]))
            .collect();
        assert_eq!(samples.len(), 16 * 1_100 + 16 * 400);
        assert_eq!(samples[0], 0);
        assert_eq!(samples[16 * 1_100 - 1], 16 * 1_100 - 1);
        assert_eq!(samples[16 * 1_100], 16 * 2_600);
        assert_eq!(*samples.last().unwrap(), 16 * 3_000 - 1);
        assert!(speech_only(b"WAV", &[]).is_none());
    }

    #[test]
    fn wav_bounds() {
        let mut wav = b"RIFF\x26\x00\x00\x00WAVEfmt \x10\x00\x00\x00\x01\x00\x01\x00\x80\x3e\x00\x00\x00\x7d\x00\x00\x02\x00\x10\x00data\x02\x00\x00\x00\x00\x00".to_vec();
        assert!(valid_wav(&wav));
        wav[22] = 2;
        assert!(!valid_wav(&wav));
        wav[22] = 1;
        wav[40] = 100;
        assert!(!valid_wav(&wav));
        wav[40] = 2;
        wav.extend_from_slice(b"data\x02\x00\x00\x00\x00\x00");
        let length = (wav.len() - 8) as u32;
        wav[4..8].copy_from_slice(&length.to_le_bytes());
        assert!(!valid_wav(&wav));
        wav.truncate(46);
        wav.push(0);
        let length = (wav.len() - 8) as u32;
        wav[4..8].copy_from_slice(&length.to_le_bytes());
        assert!(!valid_wav(&wav));
    }
}
