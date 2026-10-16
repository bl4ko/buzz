use std::{sync::Mutex, time::Duration};

use async_trait::async_trait;
use jsonwebtoken::{Algorithm, EncodingKey, Header};
use reqwest::header::{AUTHORIZATION, CONTENT_TYPE};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use thiserror::Error;
use uuid::Uuid;

use crate::{
    apns::{read_outcome, ApnsError, DeliveryOutcome},
    config::ApnsEnvironment,
};

pub const ATTRIBUTES_TYPE: &str = "BuzzApprovalsActivityAttributes";
pub const MAX_PAYLOAD_BYTES: usize = 4096;
pub const STALE_AFTER_SECONDS: i64 = 7200;
pub const MAX_ASK_CHARS: usize = 120;
pub const MAX_NAME_CHARS: usize = 64;
pub const MAX_CASE_ID_CHARS: usize = 96;
pub const MAX_OPEN_COUNT: u16 = 999;
const RELEVANCE_SCORE: u8 = 100;
const JWT_RENEW_AFTER_SECONDS: i64 = 40 * 60;
const JWT_MIN_AGE_SECONDS: i64 = 20 * 60;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ApprovalsState {
    #[serde(rename = "askEventID")]
    pub ask_event_id: String,
    #[serde(rename = "caseID", default, skip_serializing_if = "Option::is_none")]
    pub case_id: Option<String>,
    pub ask: String,
    pub agent: String,
    pub channel: String,
    #[serde(rename = "openCount")]
    pub open_count: u16,
    #[serde(rename = "askedAt")]
    pub asked_at: i64,
}

fn lower_hex_64(value: &str) -> bool {
    value.len() == 64
        && value
            .bytes()
            .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
}

fn valid_case_id(value: &str) -> bool {
    let mut bytes = value.bytes();
    bytes.next().is_some_and(|b| b.is_ascii_alphanumeric())
        && value.len() <= MAX_CASE_ID_CHARS
        && bytes.all(|b| b.is_ascii_alphanumeric() || matches!(b, b'.' | b'_' | b'-'))
}

pub fn validate_state(state: &ApprovalsState) -> Result<(), &'static str> {
    if !lower_hex_64(&state.ask_event_id) {
        return Err("askEventID");
    }
    if state
        .case_id
        .as_deref()
        .is_some_and(|id| !valid_case_id(id))
    {
        return Err("caseID");
    }
    let ask = state.ask.chars().count();
    if ask == 0 || ask > MAX_ASK_CHARS {
        return Err("ask");
    }
    if state.agent.chars().count() > MAX_NAME_CHARS {
        return Err("agent");
    }
    if state.channel.chars().count() > MAX_NAME_CHARS {
        return Err("channel");
    }
    if !(1..=MAX_OPEN_COUNT).contains(&state.open_count) {
        return Err("openCount");
    }
    if state.asked_at < 0 {
        return Err("askedAt");
    }
    Ok(())
}

fn valid_host(host: &str) -> bool {
    !host.is_empty()
        && host.len() <= 253
        && host.split('.').all(|label| {
            !label.is_empty()
                && label.len() <= 63
                && !label.starts_with('-')
                && !label.ends_with('-')
                && label
                    .bytes()
                    .all(|b| b.is_ascii_lowercase() || b.is_ascii_digit() || b == b'-')
        })
}

fn valid_port(port: &str) -> bool {
    !port.is_empty()
        && port.len() <= 5
        && !port.starts_with('0')
        && port.bytes().all(|b| b.is_ascii_digit())
        && port.parse::<u16>().is_ok_and(|p| p != 443)
}

pub fn origin_hash(origin: &str) -> Option<[u8; 32]> {
    let authority = origin.strip_prefix("https://")?;
    let valid = match authority.split_once(':') {
        Some((host, port)) => valid_host(host) && valid_port(port),
        None => valid_host(authority),
    };
    valid.then(|| Sha256::digest(origin.as_bytes()).into())
}

pub enum LiveEvent<'a> {
    Start {
        origin: &'a str,
        state: &'a ApprovalsState,
    },
    Update {
        state: &'a ApprovalsState,
    },
    End,
}

#[derive(Debug, Error, PartialEq, Eq)]
pub enum PayloadError {
    #[error("invalid Live Activity state field {0}")]
    InvalidState(&'static str),
    #[error("Live Activity payload exceeds the APNs size limit")]
    TooLarge,
}

#[derive(Serialize)]
struct Envelope<T> {
    aps: T,
}

#[derive(Serialize)]
struct Attributes<'a> {
    origin: &'a str,
}

#[derive(Serialize)]
struct Alert<'a> {
    title: &'static str,
    body: &'a str,
}

#[derive(Serialize)]
struct StartAps<'a> {
    timestamp: i64,
    event: &'static str,
    #[serde(rename = "attributes-type")]
    attributes_type: &'static str,
    attributes: Attributes<'a>,
    #[serde(rename = "content-state")]
    content_state: &'a ApprovalsState,
    #[serde(rename = "stale-date")]
    stale_date: i64,
    #[serde(rename = "relevance-score")]
    relevance_score: u8,
    #[serde(rename = "input-push-token")]
    input_push_token: u8,
    alert: Alert<'a>,
}

#[derive(Serialize)]
struct UpdateAps<'a> {
    timestamp: i64,
    event: &'static str,
    #[serde(rename = "content-state")]
    content_state: &'a ApprovalsState,
    #[serde(rename = "stale-date")]
    stale_date: i64,
    #[serde(rename = "relevance-score")]
    relevance_score: u8,
}

#[derive(Serialize)]
struct EndAps<'a> {
    timestamp: i64,
    event: &'static str,
    #[serde(rename = "content-state")]
    content_state: &'a ApprovalsState,
    #[serde(rename = "dismissal-date")]
    dismissal_date: i64,
}

pub fn payload(event: &LiveEvent<'_>, now: i64) -> Result<Vec<u8>, PayloadError> {
    let stale_date = now.saturating_add(STALE_AFTER_SECONDS);
    let body = match event {
        LiveEvent::Start { origin, state } => {
            validate_state(state).map_err(PayloadError::InvalidState)?;
            serde_json::to_vec(&Envelope {
                aps: StartAps {
                    timestamp: now,
                    event: "start",
                    attributes_type: ATTRIBUTES_TYPE,
                    attributes: Attributes { origin },
                    content_state: state,
                    stale_date,
                    relevance_score: RELEVANCE_SCORE,
                    input_push_token: 1,
                    alert: Alert {
                        title: "Needs you",
                        body: &state.ask,
                    },
                },
            })
        }
        LiveEvent::Update { state } => {
            validate_state(state).map_err(PayloadError::InvalidState)?;
            serde_json::to_vec(&Envelope {
                aps: UpdateAps {
                    timestamp: now,
                    event: "update",
                    content_state: state,
                    stale_date,
                    relevance_score: RELEVANCE_SCORE,
                },
            })
        }
        LiveEvent::End => serde_json::to_vec(&Envelope {
            aps: EndAps {
                timestamp: now,
                event: "end",
                content_state: &ApprovalsState {
                    ask_event_id: String::new(),
                    case_id: None,
                    ask: String::new(),
                    agent: String::new(),
                    channel: String::new(),
                    open_count: 0,
                    asked_at: now,
                },
                dismissal_date: now,
            },
        }),
    }
    .map_err(|_| PayloadError::InvalidState("serialization"))?;
    if body.len() > MAX_PAYLOAD_BYTES {
        return Err(PayloadError::TooLarge);
    }
    Ok(body)
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct LiveActivityAttempt {
    pub request_id: Uuid,
    pub expires_at: i64,
    pub priority: u8,
}

#[async_trait]
pub trait LiveActivityTransport: Send + Sync {
    async fn send(
        &self,
        attempt: LiveActivityAttempt,
        token_hex: &str,
        payload: &[u8],
    ) -> DeliveryOutcome;
}

#[derive(Serialize)]
struct Claims<'a> {
    iss: &'a str,
    iat: i64,
}

struct CachedJwt {
    token: String,
    issued_at: i64,
    rejected: bool,
}

pub struct ApnsTokenTransport {
    client: reqwest::Client,
    base_url: String,
    topic: String,
    key: EncodingKey,
    key_id: String,
    team_id: String,
    now: fn() -> i64,
    cache: Mutex<Option<CachedJwt>>,
}

fn apple_identifier(value: &str) -> bool {
    value.len() == 10 && value.bytes().all(|b| b.is_ascii_alphanumeric())
}

pub fn transport_from_config(
    profile: &crate::config::AppProfileConfig,
) -> Result<Option<std::sync::Arc<dyn LiveActivityTransport>>, LiveActivitySetupError> {
    let Some(credentials) = profile.live_activity.as_ref() else {
        return Ok(None);
    };
    let key = std::fs::read(&credentials.auth_key_path).map_err(|_| LiveActivitySetupError)?;
    let transport = ApnsTokenTransport::new(
        &key,
        credentials.key_id.clone(),
        credentials.team_id.clone(),
        profile.apns_topic.clone(),
        profile.apns_environment,
    )
    .map_err(|_| LiveActivitySetupError)?;
    Ok(Some(std::sync::Arc::new(transport)))
}

#[derive(Debug, Error)]
#[error("invalid Live Activity APNs auth key")]
pub struct LiveActivitySetupError;

fn system_now() -> i64 {
    chrono::Utc::now().timestamp()
}

impl ApnsTokenTransport {
    pub fn new(
        key_pem: &[u8],
        key_id: String,
        team_id: String,
        topic: String,
        environment: ApnsEnvironment,
    ) -> Result<Self, ApnsError> {
        let base_url = match environment {
            ApnsEnvironment::Production => "https://api.push.apple.com",
            ApnsEnvironment::Sandbox => "https://api.sandbox.push.apple.com",
        };
        Self::with_parts(
            key_pem,
            key_id,
            team_id,
            topic,
            base_url.to_owned(),
            system_now,
        )
    }

    fn with_parts(
        key_pem: &[u8],
        key_id: String,
        team_id: String,
        topic: String,
        base_url: String,
        now: fn() -> i64,
    ) -> Result<Self, ApnsError> {
        if !apple_identifier(&key_id) || !apple_identifier(&team_id) || topic.is_empty() {
            return Err(ApnsError::Credential);
        }
        let key = EncodingKey::from_ec_pem(key_pem).map_err(|_| ApnsError::Credential)?;
        let client = reqwest::Client::builder()
            .http2_keep_alive_while_idle(false)
            .timeout(Duration::from_secs(15))
            .build()
            .map_err(|_| ApnsError::Credential)?;
        let transport = Self {
            client,
            base_url,
            topic: format!("{topic}.push-type.liveactivity"),
            key,
            key_id,
            team_id,
            now,
            cache: Mutex::new(None),
        };
        transport.bearer(now())?;
        Ok(transport)
    }

    fn sign(&self, issued_at: i64) -> Result<String, ApnsError> {
        let mut header = Header::new(Algorithm::ES256);
        header.typ = None;
        header.kid = Some(self.key_id.clone());
        jsonwebtoken::encode(
            &header,
            &Claims {
                iss: &self.team_id,
                iat: issued_at,
            },
            &self.key,
        )
        .map_err(|_| ApnsError::Credential)
    }

    fn bearer(&self, now: i64) -> Result<String, ApnsError> {
        let mut cache = self.cache.lock().map_err(|_| ApnsError::Credential)?;
        if let Some(cached) = cache.as_ref() {
            let age = now.saturating_sub(cached.issued_at);
            let renew =
                age >= JWT_RENEW_AFTER_SECONDS || (cached.rejected && age >= JWT_MIN_AGE_SECONDS);
            if !renew {
                return Ok(cached.token.clone());
            }
        }
        let token = self.sign(now)?;
        *cache = Some(CachedJwt {
            token: token.clone(),
            issued_at: now,
            rejected: false,
        });
        Ok(token)
    }

    fn mark_rejected(&self, token: &str) {
        if let Ok(mut cache) = self.cache.lock() {
            if let Some(cached) = cache.as_mut().filter(|cached| cached.token == token) {
                cached.rejected = true;
            }
        }
    }
}

#[async_trait]
impl LiveActivityTransport for ApnsTokenTransport {
    async fn send(
        &self,
        attempt: LiveActivityAttempt,
        token_hex: &str,
        payload: &[u8],
    ) -> DeliveryOutcome {
        let bearer = match self.bearer((self.now)()) {
            Ok(bearer) => bearer,
            Err(_) => return DeliveryOutcome::ConfigurationFault,
        };
        let response = self
            .client
            .post(format!("{}/3/device/{token_hex}", self.base_url))
            .header(CONTENT_TYPE, "application/json")
            .header(AUTHORIZATION, format!("bearer {bearer}"))
            .header("apns-id", attempt.request_id.to_string())
            .header("apns-topic", &self.topic)
            .header("apns-push-type", "liveactivity")
            .header("apns-priority", attempt.priority.to_string())
            .header("apns-expiration", attempt.expires_at.to_string())
            .body(payload.to_vec())
            .send()
            .await;
        let (outcome, reason) = read_outcome(response).await;
        if matches!(
            reason.as_deref(),
            Some("ExpiredProviderToken" | "InvalidProviderToken")
        ) {
            self.mark_rejected(&bearer);
        }
        outcome
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::{
        body::Bytes,
        extract::{Path, State},
        http::{HeaderMap, StatusCode},
        routing::post,
        Router,
    };
    use std::sync::Arc;

    const VECTORS_JSON: &str = include_str!("../tests/vectors/live_activity_payloads.json");
    const TEST_KEY: &[u8] = include_bytes!("../tests/fixtures/apns-test-auth-key.p8");
    const TEST_PUBLIC_KEY: &[u8] = include_bytes!("../tests/fixtures/apns-test-auth-key.pub.pem");

    fn vectors() -> serde_json::Value {
        serde_json::from_str(VECTORS_JSON).unwrap()
    }

    fn state(ask: &str) -> ApprovalsState {
        ApprovalsState {
            ask_event_id: "ab".repeat(32),
            case_id: Some("BUZZ-1".into()),
            ask: ask.into(),
            agent: "Zeus".into(),
            channel: "tasks".into(),
            open_count: 1,
            asked_at: 1,
        }
    }

    #[test]
    fn payload_matches_vectors() {
        let file = vectors();
        let cases = file["cases"].as_array().unwrap();
        let names: Vec<_> = cases.iter().map(|c| c["name"].as_str().unwrap()).collect();
        assert_eq!(
            names,
            [
                "start_basic",
                "start_multibyte_120_chars",
                "update_count_only",
                "update_no_case_id",
                "end"
            ]
        );
        for case in cases {
            let name = case["name"].as_str().unwrap();
            let now = case["now"].as_i64().unwrap();
            let state: Option<ApprovalsState> = (!case["state"].is_null())
                .then(|| serde_json::from_value(case["state"].clone()).unwrap());
            let event = match case["event"].as_str().unwrap() {
                "start" => LiveEvent::Start {
                    origin: case["origin"].as_str().unwrap(),
                    state: state.as_ref().unwrap(),
                },
                "update" => LiveEvent::Update {
                    state: state.as_ref().unwrap(),
                },
                "end" => LiveEvent::End,
                other => panic!("unknown event {other}"),
            };
            let body = payload(&event, now).unwrap();
            assert_eq!(
                std::str::from_utf8(&body).unwrap(),
                case["expected"].as_str().unwrap(),
                "{name}"
            );
            assert_eq!(
                body.len() as u64,
                case["expected_bytes"].as_u64().unwrap(),
                "{name}"
            );
        }
        for entry in file["origin_hashes"].as_array().unwrap() {
            assert_eq!(
                hex::encode(origin_hash(entry["origin"].as_str().unwrap()).unwrap()),
                entry["sha256"].as_str().unwrap()
            );
        }
        for origin in file["invalid_origins"].as_array().unwrap() {
            assert!(origin_hash(origin.as_str().unwrap()).is_none(), "{origin}");
        }
    }

    #[test]
    fn ask_of_120_multibyte_chars_passes_and_121_fails() {
        let ask: String = "🐝".repeat(120);
        assert_eq!(validate_state(&state(&ask)), Ok(()));
        assert_eq!(validate_state(&state(&format!("{ask}ž"))), Err("ask"));
        let mut long_agent = state("ok");
        long_agent.agent = "ž".repeat(64);
        long_agent.channel = "🐝".repeat(64);
        assert_eq!(validate_state(&long_agent), Ok(()));
        long_agent.agent.push('a');
        assert_eq!(validate_state(&long_agent), Err("agent"));
        for (field, mutate) in [
            (
                "askEventID",
                (|s: &mut ApprovalsState| s.ask_event_id = "AB".repeat(32))
                    as fn(&mut ApprovalsState),
            ),
            ("askEventID", |s| s.ask_event_id.clear()),
            ("caseID", |s| s.case_id = Some("-bad".into())),
            ("caseID", |s| s.case_id = Some("a".repeat(97))),
            ("ask", |s| s.ask.clear()),
            ("channel", |s| s.channel = "c".repeat(65)),
            ("openCount", |s| s.open_count = 0),
            ("openCount", |s| s.open_count = 1000),
            ("askedAt", |s| s.asked_at = -1),
        ] {
            let mut value = state("ok");
            mutate(&mut value);
            assert_eq!(validate_state(&value), Err(field));
            assert_eq!(
                payload(&LiveEvent::Update { state: &value }, 1),
                Err(PayloadError::InvalidState(field))
            );
        }
        let mut case = state("ok");
        case.case_id = Some(format!("A{}", "b._-".repeat(23)));
        assert_eq!(case.case_id.as_ref().unwrap().len(), 93);
        assert_eq!(validate_state(&case), Ok(()));
    }

    #[test]
    fn state_rejects_unknown_fields_and_decision() {
        let mut value = serde_json::to_value(state("ok")).unwrap();
        value["decision"] = "approve".into();
        assert!(serde_json::from_value::<ApprovalsState>(value).is_err());
        let mut value = serde_json::to_value(state("ok")).unwrap();
        value["caseID"] = serde_json::Value::Null;
        assert_eq!(
            serde_json::from_value::<ApprovalsState>(value)
                .unwrap()
                .case_id,
            None
        );
    }

    #[test]
    fn payload_over_4096_bytes_is_rejected() {
        let value = state(&"\u{1}".repeat(120));
        let fits = format!("https://{}", "a".repeat(63));
        assert!(payload(
            &LiveEvent::Start {
                origin: &fits,
                state: &value
            },
            1
        )
        .is_ok());
        let origin = format!("https://{}", "a".repeat(MAX_PAYLOAD_BYTES));
        assert_eq!(
            payload(
                &LiveEvent::Start {
                    origin: &origin,
                    state: &value
                },
                1
            ),
            Err(PayloadError::TooLarge)
        );
    }

    #[test]
    fn origin_hash_rejects_path_and_uppercase_host() {
        assert!(origin_hash("https://buzz.bl4ko.com").is_some());
        assert!(origin_hash("https://buzz.bl4ko.com:8443").is_some());
        for origin in [
            "https://buzz.bl4ko.com/",
            "https://buzz.bl4ko.com/v1",
            "https://Buzz.bl4ko.com",
            "HTTPS://buzz.bl4ko.com",
            "https://buzz.bl4ko.com:443",
            "https://buzz.bl4ko.com:08443",
            "https://buzz.bl4ko.com:65536",
            "https://buzz.bl4ko.com:",
            "https://buzz..com",
            "https://-buzz.com",
            "https://[::1]",
            "https://buzz.bl4ko.com#x",
        ] {
            assert!(origin_hash(origin).is_none(), "{origin}");
        }
    }

    fn fixed_now() -> i64 {
        1_760_620_000
    }

    fn test_transport(base_url: String, now: fn() -> i64) -> ApnsTokenTransport {
        ApnsTokenTransport::with_parts(
            TEST_KEY,
            "ABC123DEFG".into(),
            "55S37D9HA7".into(),
            "com.bl4ko.buzz".into(),
            base_url,
            now,
        )
        .unwrap()
    }

    #[test]
    fn jwt_header_and_claims() {
        let transport = test_transport("http://127.0.0.1:1".into(), fixed_now);
        let token = transport.bearer(fixed_now()).unwrap();
        let header = jsonwebtoken::decode_header(&token).unwrap();
        assert_eq!(header.alg, Algorithm::ES256);
        assert_eq!(header.kid.as_deref(), Some("ABC123DEFG"));
        assert_eq!(header.typ, None);
        let mut validation = jsonwebtoken::Validation::new(Algorithm::ES256);
        validation.required_spec_claims.clear();
        validation.validate_exp = false;
        let claims = jsonwebtoken::decode::<serde_json::Value>(
            &token,
            &jsonwebtoken::DecodingKey::from_ec_pem(TEST_PUBLIC_KEY).unwrap(),
            &validation,
        )
        .unwrap()
        .claims;
        assert_eq!(
            claims,
            serde_json::json!({"iss": "55S37D9HA7", "iat": fixed_now()})
        );
        for (key, key_id, team_id) in [
            (b"not a key".as_slice(), "ABC123DEFG", "55S37D9HA7"),
            (TEST_KEY, "short", "55S37D9HA7"),
            (TEST_KEY, "ABC123DEFG", "55S37D9HA7X"),
        ] {
            assert!(matches!(
                ApnsTokenTransport::with_parts(
                    key,
                    key_id.into(),
                    team_id.into(),
                    "com.bl4ko.buzz".into(),
                    "http://127.0.0.1:1".into(),
                    fixed_now,
                ),
                Err(ApnsError::Credential)
            ));
        }
    }

    #[test]
    fn transport_from_config_reads_the_auth_key() {
        let profile = |path: &str| crate::config::AppProfileConfig {
            app_attest_app_id: "TEAM.app".into(),
            app_attest_environment: crate::config::AppAttestEnvironment::Production,
            apns_cert_path: "/unused".into(),
            apns_topic: "com.bl4ko.buzz".into(),
            apns_environment: ApnsEnvironment::Production,
            live_activity: Some(crate::config::LiveActivityCredentials {
                auth_key_path: path.into(),
                key_id: "ABC123DEFG".into(),
                team_id: "55S37D9HA7".into(),
            }),
        };
        let key = concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/tests/fixtures/apns-test-auth-key.p8"
        );
        assert!(transport_from_config(&profile(key)).unwrap().is_some());
        let cert_only = concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/tests/fixtures/apns-test-cert-only.pem"
        );
        for path in ["/missing/auth-key.p8", cert_only] {
            assert!(transport_from_config(&profile(path)).is_err(), "{path}");
        }
    }

    #[test]
    fn jwt_is_reused_inside_20_minutes() {
        let transport = test_transport("http://127.0.0.1:1".into(), fixed_now);
        let first = transport.bearer(fixed_now()).unwrap();
        assert_eq!(transport.bearer(fixed_now() + 1).unwrap(), first);
        transport.mark_rejected(&first);
        assert_eq!(
            transport
                .bearer(fixed_now() + JWT_MIN_AGE_SECONDS - 1)
                .unwrap(),
            first
        );
        let renewed = transport.bearer(fixed_now() + JWT_MIN_AGE_SECONDS).unwrap();
        assert_ne!(renewed, first);
        let issued = fixed_now() + JWT_MIN_AGE_SECONDS;
        assert_eq!(
            transport
                .bearer(issued + JWT_RENEW_AFTER_SECONDS - 1)
                .unwrap(),
            renewed
        );
        assert_ne!(
            transport.bearer(issued + JWT_RENEW_AFTER_SECONDS).unwrap(),
            renewed
        );
    }

    struct Captured {
        token: String,
        headers: HeaderMap,
        body: Vec<u8>,
    }

    type Requests = Arc<std::sync::Mutex<Vec<Captured>>>;

    async fn capture(
        State(requests): State<Requests>,
        Path(token): Path<String>,
        headers: HeaderMap,
        body: Bytes,
    ) -> (StatusCode, &'static str) {
        let expired = token == "ee";
        requests.lock().unwrap().push(Captured {
            token,
            headers,
            body: body.to_vec(),
        });
        if expired {
            (
                StatusCode::FORBIDDEN,
                r#"{"reason":"ExpiredProviderToken"}"#,
            )
        } else {
            (StatusCode::OK, "")
        }
    }

    #[tokio::test]
    async fn token_transport_sends_liveactivity_headers() {
        let requests: Requests = Arc::default();
        let app = Router::new()
            .route("/3/device/{token}", post(capture))
            .with_state(requests.clone());
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let base_url = format!("http://{}", listener.local_addr().unwrap());
        tokio::spawn(async move { axum::serve(listener, app).await.unwrap() });
        let transport = test_transport(base_url, fixed_now);
        let body = payload(&LiveEvent::End, fixed_now()).unwrap();
        let request_id = Uuid::from_u128(7);
        for (priority, token, expected) in [
            (10, "0a0b", DeliveryOutcome::Accepted),
            (5, "ee", DeliveryOutcome::ConfigurationFault),
        ] {
            assert_eq!(
                transport
                    .send(
                        LiveActivityAttempt {
                            request_id,
                            expires_at: fixed_now() + 60,
                            priority,
                        },
                        token,
                        &body,
                    )
                    .await,
                expected
            );
        }
        let captured = requests.lock().unwrap();
        assert_eq!(captured.len(), 2);
        let first = &captured[0];
        assert_eq!(first.token, "0a0b");
        assert_eq!(first.body, body);
        let header = |name: &str| {
            first
                .headers
                .get(name)
                .unwrap()
                .to_str()
                .unwrap()
                .to_owned()
        };
        assert_eq!(header("apns-push-type"), "liveactivity");
        assert_eq!(
            header("apns-topic"),
            "com.bl4ko.buzz.push-type.liveactivity"
        );
        assert_eq!(header("apns-priority"), "10");
        assert_eq!(header("apns-expiration"), (fixed_now() + 60).to_string());
        assert_eq!(header("apns-id"), request_id.to_string());
        assert_eq!(header("content-type"), "application/json");
        let bearer = header("authorization");
        let jwt = bearer.strip_prefix("bearer ").unwrap();
        assert_eq!(
            jsonwebtoken::decode_header(jwt).unwrap().kid.as_deref(),
            Some("ABC123DEFG")
        );
        assert_eq!(captured[1].headers.get("apns-priority").unwrap(), "5");
        drop(captured);
        assert!(transport.cache.lock().unwrap().as_ref().unwrap().rejected);
    }
}
