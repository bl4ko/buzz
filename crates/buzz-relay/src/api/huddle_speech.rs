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
    agent_name: Option<String>,
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
    if bytes.len() < 44
        || bytes.len() > MAX_AUDIO
        || &bytes[..4] != b"RIFF"
        || &bytes[8..12] != b"WAVE"
        || read_u32(bytes, 4) as usize != bytes.len() - 8
    {
        return false;
    }
    let mut offset = 12;
    let mut rate = None;
    let mut data = None;
    while offset + 8 <= bytes.len() {
        let size = read_u32(bytes, offset + 4) as usize;
        let start = offset + 8;
        let Some(end) = start.checked_add(size).filter(|end| *end <= bytes.len()) else {
            return false;
        };
        if &bytes[offset..offset + 4] == b"fmt " {
            if size < 16 || rate.is_some() {
                return false;
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
                return false;
            }
            rate = Some(sample_rate as usize);
        }
        if &bytes[offset..offset + 4] == b"data" {
            if data.is_some() {
                return false;
            }
            data = Some(size);
        }
        offset = end + size % 2;
    }
    offset == bytes.len()
        && matches!((rate, data), (Some(rate), Some(size)) if size > 0 && size % 2 == 0 && size <= rate * 2 * 15)
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

fn transcription_body(model: &str, audio: &[u8], boundary: &str) -> Vec<u8> {
    let mut multipart = Vec::new();
    for (name, value) in [
        ("model", model),
        ("language", "en"),
        ("response_format", "json"),
        ("vad_filter", "true"),
    ] {
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
    if request
        .agent_name
        .as_deref()
        .is_some_and(|name| !["Hermes", "Athene", "Argus"].contains(&name))
    {
        return Err(api_error(StatusCode::BAD_REQUEST, "invalid agent name").into_response());
    }
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
    let _slot = SPEECH_SLOTS.try_acquire().map_err(|_| {
        api_error(StatusCode::TOO_MANY_REQUESTS, "speech service busy").into_response()
    })?;
    let boundary = format!("buzz-{}", Uuid::new_v4());
    let multipart = transcription_body(&state.config.speech_transcription_model, &audio, &boundary);
    let client = CLIENT.as_ref().map_err(|_| {
        api_error(StatusCode::SERVICE_UNAVAILABLE, "speech client unavailable").into_response()
    })?;
    let response = client
        .post(format!(
            "{}/audio/transcriptions",
            base.trim_end_matches('/')
        ))
        .header(
            "Content-Type",
            format!("multipart/form-data; boundary={boundary}"),
        )
        .body(multipart)
        .send()
        .await
        .map_err(|_| {
            api_error(StatusCode::BAD_GATEWAY, "speech service unavailable").into_response()
        })?;
    let bytes = upstream_bytes(response).await?;
    let value: serde_json::Value = serde_json::from_slice(&bytes).map_err(|_| {
        api_error(StatusCode::BAD_GATEWAY, "invalid speech response").into_response()
    })?;
    let text = value
        .get("text")
        .and_then(|v| v.as_str())
        .ok_or_else(|| api_error(StatusCode::BAD_GATEWAY, "missing transcript").into_response())?;
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
    let voice = request.voice.as_deref().unwrap_or("am_michael");
    if request.text.trim().is_empty()
        || request.text.chars().count() > 2000
        || !VOICES.contains(&voice)
    {
        return Err(
            api_error(StatusCode::BAD_REQUEST, "invalid speech text or voice").into_response(),
        );
    }
    let _slot = SPEECH_SLOTS.try_acquire().map_err(|_| {
        api_error(StatusCode::TOO_MANY_REQUESTS, "speech service busy").into_response()
    })?;
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
        let body = transcription_body("whisper", b"WAV", "boundary");
        let body = String::from_utf8(body).unwrap();
        assert!(body.contains("name=\"vad_filter\"\r\n\r\ntrue\r\n"));
        assert!(!body.contains("name=\"prompt\""));
        assert!(body.contains("audio/wav\r\n\r\nWAV\r\n--boundary--\r\n"));
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
