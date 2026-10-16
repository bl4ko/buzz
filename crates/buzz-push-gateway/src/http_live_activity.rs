use super::{
    authority_error, delivery_auth, endpoint_bytes, error, valid_relay_pubkey,
    verify_installation_assertion, AppState, AssertionChallenge,
};
use crate::{
    apns::DeliveryOutcome,
    authority::{AuthorityError, DeliveryDisposition, LiveActivityTarget, SealedToken},
    config::{LIVE_ACTIVITY_AUDIENCE, LIVE_ACTIVITY_UPDATE_AUDIENCE},
    live_activity::{
        bound_origin_hash, payload, valid_origin, validate_state, ApprovalsState,
        LiveActivityAttempt, LiveActivityTransport, LiveEvent,
    },
    metrics::{record_live_activity_delivery, LiveActivityOutcome},
    model::*,
};
use axum::{
    body::Bytes,
    extract::{OriginalUri, State},
    http::{HeaderMap, StatusCode},
    response::{IntoResponse, Response},
    Json,
};
use std::sync::Arc;

pub(super) const DELIVERY_PATH: &str = "/v1/deliveries/live-activity";
pub(crate) const START_FINGERPRINT_DOMAIN: &[u8] = b"buzz.push.la-start.v1";
pub(crate) const UPDATE_FINGERPRINT_DOMAIN: &[u8] = b"buzz.push.la-update.v1";
pub(crate) const CARD_LIFETIME_SECONDS: i64 = 8 * 3600;
pub(crate) const START_RETRY_SECONDS: i64 = 30 * 60;
const START_PRIORITY: u8 = 10;

pub(crate) fn token_fingerprint(domain: &[u8], token: &[u8]) -> [u8; 32] {
    use sha2::{Digest, Sha256};
    let mut h = Sha256::new();
    h.update(domain);
    h.update([0]);
    h.update(token);
    h.finalize().into()
}

fn parse_hash(value: &str) -> Option<[u8; 32]> {
    valid_relay_pubkey(value)
        .then(|| hex::decode(value).ok()?.try_into().ok())
        .flatten()
}

fn seal(s: &AppState, domain: &[u8], token: &[u8]) -> Option<SealedToken> {
    s.token_keyring
        .seal(token)
        .ok()
        .map(|ciphertext| SealedToken {
            ciphertext,
            fingerprint: token_fingerprint(domain, token),
        })
}

#[derive(serde::Serialize)]
pub(crate) struct RegistrationTranscript<'a> {
    pub v: u8,
    pub audience: &'a str,
    pub challenge_id: uuid::Uuid,
    pub challenge: &'a str,
    pub installation_handle: uuid::Uuid,
    pub start_token: Option<&'a str>,
    pub origins: &'a [String],
}

#[derive(serde::Serialize)]
pub(crate) struct UpdateTokenTranscript<'a> {
    pub v: u8,
    pub audience: &'a str,
    pub challenge_id: uuid::Uuid,
    pub challenge: &'a str,
    pub installation_handle: uuid::Uuid,
    pub origin_hash: &'a str,
    pub update_token: Option<&'a str>,
}

pub(super) async fn register(State(s): State<AppState>, body: Bytes) -> Response {
    let r: LiveActivityRegistrationRequest = match crate::strict_json::from_slice(&body) {
        Ok(r) => r,
        Err(_) => return error(StatusCode::BAD_REQUEST, "invalid_request"),
    };
    let token = match r.start_token.as_deref().map(endpoint_bytes) {
        None => None,
        Some(Some(token)) => Some(token),
        Some(None) => return error(StatusCode::BAD_REQUEST, "invalid_request"),
    };
    let hashes = match r
        .origins
        .iter()
        .map(|origin| parse_hash(origin))
        .collect::<Option<Vec<_>>>()
    {
        Some(hashes) if crate::authority::valid_origin_hashes(&hashes) => hashes,
        _ => return error(StatusCode::BAD_REQUEST, "invalid_request"),
    };
    if r.v != WIRE_VERSION {
        return error(StatusCode::BAD_REQUEST, "invalid_request");
    }
    let t = RegistrationTranscript {
        v: r.v,
        audience: LIVE_ACTIVITY_AUDIENCE,
        challenge_id: r.challenge_id,
        challenge: &r.challenge,
        installation_handle: r.installation_handle,
        start_token: r.start_token.as_deref(),
        origins: &r.origins,
    };
    if let Err(e) = verify_installation_assertion(
        &s,
        r.installation_handle,
        AssertionChallenge {
            id: r.challenge_id,
            text: &r.challenge,
        },
        &r.assertion,
        "buzz.push.live-activity.v1",
        &t,
        false,
    )
    .await
    {
        return e;
    }
    let sealed = match token.map(|token| seal(&s, START_FINGERPRINT_DOMAIN, &token)) {
        None => None,
        Some(Some(sealed)) => Some(sealed),
        Some(None) => return error(StatusCode::SERVICE_UNAVAILABLE, "temporarily_unavailable"),
    };
    match s
        .authority
        .replace_live_activity_registration(r.installation_handle, sealed, hashes, (s.now)())
        .await
    {
        Ok(()) => StatusCode::NO_CONTENT.into_response(),
        Err(e) => authority_error(e),
    }
}

pub(super) async fn update_token(State(s): State<AppState>, body: Bytes) -> Response {
    let r: LiveActivityUpdateTokenRequest = match crate::strict_json::from_slice(&body) {
        Ok(r) => r,
        Err(_) => return error(StatusCode::BAD_REQUEST, "invalid_request"),
    };
    let token = match r.update_token.as_deref().map(endpoint_bytes) {
        None => None,
        Some(Some(token)) => Some(token),
        Some(None) => return error(StatusCode::BAD_REQUEST, "invalid_request"),
    };
    let Some(hash) = parse_hash(&r.origin_hash) else {
        return error(StatusCode::BAD_REQUEST, "invalid_request");
    };
    if r.v != WIRE_VERSION {
        return error(StatusCode::BAD_REQUEST, "invalid_request");
    }
    let t = UpdateTokenTranscript {
        v: r.v,
        audience: LIVE_ACTIVITY_UPDATE_AUDIENCE,
        challenge_id: r.challenge_id,
        challenge: &r.challenge,
        installation_handle: r.installation_handle,
        origin_hash: &r.origin_hash,
        update_token: r.update_token.as_deref(),
    };
    if let Err(e) = verify_installation_assertion(
        &s,
        r.installation_handle,
        AssertionChallenge {
            id: r.challenge_id,
            text: &r.challenge,
        },
        &r.assertion,
        "buzz.push.live-activity-update.v1",
        &t,
        false,
    )
    .await
    {
        return e;
    }
    let sealed = match token.map(|token| seal(&s, UPDATE_FINGERPRINT_DOMAIN, &token)) {
        None => None,
        Some(Some(sealed)) => Some(sealed),
        Some(None) => return error(StatusCode::SERVICE_UNAVAILABLE, "temporarily_unavailable"),
    };
    match s
        .authority
        .set_live_activity_update_token(r.installation_handle, hash, sealed, (s.now)())
        .await
    {
        Ok(()) => StatusCode::NO_CONTENT.into_response(),
        Err(e) => authority_error(e),
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum Plan {
    Update,
    Start { end_first: bool },
    Pending,
    End,
    AlreadyEnded,
}

pub(crate) fn plan(target: &LiveActivityTarget, op: LiveActivityOp, now: i64) -> Plan {
    let has_update = target.update_ciphertext.is_some();
    let age = target.started_at.map(|started| now.saturating_sub(started));
    match op {
        LiveActivityOp::Upsert if has_update && age.is_none_or(|a| a < CARD_LIFETIME_SECONDS) => {
            Plan::Update
        }
        LiveActivityOp::Upsert if !has_update && age.is_some_and(|a| a < START_RETRY_SECONDS) => {
            Plan::Pending
        }
        LiveActivityOp::Upsert => Plan::Start { end_first: false },
        LiveActivityOp::Restart => Plan::Start {
            end_first: has_update,
        },
        LiveActivityOp::End if has_update => Plan::End,
        LiveActivityOp::End => Plan::AlreadyEnded,
    }
}

enum Finished {
    Status(LiveActivityDeliveryResponse),
    Outcome(DeliveryOutcome),
    Unavailable,
}

impl Finished {
    fn disposition(&self) -> DeliveryDisposition {
        match self {
            Self::Outcome(DeliveryOutcome::Retry { .. } | DeliveryOutcome::ConfigurationFault)
            | Self::Unavailable => DeliveryDisposition::Retryable,
            _ => DeliveryDisposition::Terminal,
        }
    }
}

fn response(finished: Finished, op: LiveActivityOp) -> Response {
    let (status, body, outcome) = match finished {
        Finished::Status(body) => {
            let outcome = match body {
                LiveActivityDeliveryResponse::Started => LiveActivityOutcome::Started,
                LiveActivityDeliveryResponse::Updated => LiveActivityOutcome::Updated,
                LiveActivityDeliveryResponse::Ended => LiveActivityOutcome::Ended,
                LiveActivityDeliveryResponse::Pending => LiveActivityOutcome::Pending,
                LiveActivityDeliveryResponse::NotRegistered => LiveActivityOutcome::NotRegistered,
                LiveActivityDeliveryResponse::InvalidEndpoint { .. } => {
                    LiveActivityOutcome::InvalidEndpoint
                }
                LiveActivityDeliveryResponse::Retry { .. } => LiveActivityOutcome::Retry,
            };
            (StatusCode::OK, Json(body).into_response(), outcome)
        }
        Finished::Outcome(DeliveryOutcome::Retry {
            retry_after_seconds,
        }) => (
            StatusCode::SERVICE_UNAVAILABLE,
            Json(LiveActivityDeliveryResponse::Retry {
                retry_after_seconds,
            })
            .into_response(),
            LiveActivityOutcome::Retry,
        ),
        Finished::Outcome(DeliveryOutcome::ConfigurationFault) => (
            StatusCode::SERVICE_UNAVAILABLE,
            error(StatusCode::SERVICE_UNAVAILABLE, "configuration_fault"),
            LiveActivityOutcome::ConfigurationFault,
        ),
        Finished::Outcome(_) => (
            StatusCode::BAD_REQUEST,
            error(StatusCode::BAD_REQUEST, "invalid_request"),
            LiveActivityOutcome::InvalidRequest,
        ),
        Finished::Unavailable => (
            StatusCode::SERVICE_UNAVAILABLE,
            error(StatusCode::SERVICE_UNAVAILABLE, "temporarily_unavailable"),
            LiveActivityOutcome::Unavailable,
        ),
    };
    record_live_activity_delivery(op, outcome);
    (status, body).into_response()
}

struct Job {
    s: AppState,
    transport: Arc<dyn LiveActivityTransport>,
    installation: uuid::Uuid,
    origin: String,
    origin_hash: [u8; 32],
    state: Option<ApprovalsState>,
    attempt: LiveActivityAttempt,
    now: i64,
}

impl Job {
    fn open(&self, ciphertext: &[u8]) -> Option<String> {
        self.s.token_keyring.open(ciphertext).ok().map(hex::encode)
    }

    async fn send(
        &self,
        token: &str,
        event: &LiveEvent<'_>,
        attempt: LiveActivityAttempt,
    ) -> Finished {
        let body = match payload(event, self.now) {
            Ok(body) => body,
            Err(_) => return Finished::Outcome(DeliveryOutcome::PermanentRequestFault),
        };
        Finished::Outcome(self.transport.send(attempt, token, &body).await)
    }

    fn stored(
        result: Result<(), AuthorityError>,
        status: LiveActivityDeliveryResponse,
    ) -> Finished {
        match result {
            Ok(()) => Finished::Status(status),
            Err(_) => Finished::Unavailable,
        }
    }

    async fn clear(&self) -> Result<(), AuthorityError> {
        self.s
            .authority
            .clear_live_activity(self.installation, self.origin_hash, self.now)
            .await
    }

    async fn end(&self, update: &[u8], attempt: LiveActivityAttempt) -> Finished {
        let Some(token) = self.open(update) else {
            return Finished::Unavailable;
        };
        match self.send(&token, &LiveEvent::End, attempt).await {
            Finished::Outcome(
                DeliveryOutcome::Accepted | DeliveryOutcome::InvalidEndpoint { .. },
            ) => Self::stored(self.clear().await, LiveActivityDeliveryResponse::Ended),
            other => other,
        }
    }

    async fn run(self, target: LiveActivityTarget, op: LiveActivityOp) -> Finished {
        let update = target.update_ciphertext.clone();
        match plan(&target, op, self.now) {
            Plan::Pending => Finished::Status(LiveActivityDeliveryResponse::Pending),
            Plan::AlreadyEnded => Finished::Status(LiveActivityDeliveryResponse::Ended),
            Plan::End => {
                self.end(update.as_deref().unwrap_or_default(), self.attempt)
                    .await
            }
            Plan::Update => {
                let Some(token) = update.as_deref().and_then(|u| self.open(u)) else {
                    return Finished::Unavailable;
                };
                let Some(state) = self.state.as_ref() else {
                    return Finished::Outcome(DeliveryOutcome::PermanentRequestFault);
                };
                match self
                    .send(&token, &LiveEvent::Update { state }, self.attempt)
                    .await
                {
                    Finished::Outcome(DeliveryOutcome::Accepted) => {
                        Finished::Status(LiveActivityDeliveryResponse::Updated)
                    }
                    Finished::Outcome(DeliveryOutcome::InvalidEndpoint { .. }) => {
                        Self::stored(self.clear().await, LiveActivityDeliveryResponse::Pending)
                    }
                    other => other,
                }
            }
            Plan::Start { end_first } => {
                if end_first {
                    let attempt = LiveActivityAttempt {
                        request_id: uuid::Uuid::new_v4(),
                        priority: 10,
                        ..self.attempt
                    };
                    match self
                        .end(update.as_deref().unwrap_or_default(), attempt)
                        .await
                    {
                        Finished::Status(_) | Finished::Outcome(_) => {}
                        Finished::Unavailable => return Finished::Unavailable,
                    }
                }
                self.start(&target.start_ciphertext).await
            }
        }
    }

    async fn start(&self, start: &[u8]) -> Finished {
        let Some(token) = self.open(start) else {
            return Finished::Unavailable;
        };
        let Some(state) = self.state.as_ref() else {
            return Finished::Outcome(DeliveryOutcome::PermanentRequestFault);
        };
        let event = LiveEvent::Start {
            origin: &self.origin,
            state,
        };
        let attempt = LiveActivityAttempt {
            priority: START_PRIORITY,
            ..self.attempt
        };
        match self.send(&token, &event, attempt).await {
            Finished::Outcome(DeliveryOutcome::Accepted) => {
                let recorded = self
                    .s
                    .authority
                    .record_live_activity_start(self.installation, self.origin_hash, self.now)
                    .await;
                Self::stored(recorded, LiveActivityDeliveryResponse::Started)
            }
            Finished::Outcome(DeliveryOutcome::InvalidEndpoint { .. }) => {
                let removed = self
                    .s
                    .authority
                    .replace_live_activity_registration(
                        self.installation,
                        None,
                        Vec::new(),
                        self.now,
                    )
                    .await;
                Self::stored(removed, LiveActivityDeliveryResponse::NotRegistered)
            }
            other => other,
        }
    }
}

pub(super) async fn deliver(
    State(s): State<AppState>,
    OriginalUri(uri): OriginalUri,
    headers: HeaderMap,
    body: Bytes,
) -> Response {
    let r: LiveActivityDeliveryRequest = match crate::strict_json::from_slice(&body) {
        Ok(r) => r,
        Err(_) => return error(StatusCode::BAD_REQUEST, "invalid_request"),
    };
    let state_valid = match (r.op, r.state.as_ref()) {
        (LiveActivityOp::End, None) => true,
        (LiveActivityOp::Upsert | LiveActivityOp::Restart, Some(state)) => {
            validate_state(state).is_ok()
        }
        _ => false,
    };
    if r.v != WIRE_VERSION
        || !valid_origin(&r.origin)
        || !matches!(r.priority, 5 | 10)
        || !state_valid
    {
        return error(StatusCode::BAD_REQUEST, "invalid_request");
    }
    let Some(auth) = headers
        .get(axum::http::header::AUTHORIZATION)
        .and_then(|v| v.to_str().ok())
    else {
        return error(StatusCode::UNAUTHORIZED, "invalid_auth");
    };
    if uri.query().is_some() {
        return error(StatusCode::UNAUTHORIZED, "invalid_auth");
    }
    let Some((event_id, relay)) = delivery_auth(auth, &body, DELIVERY_PATH) else {
        return error(StatusCode::UNAUTHORIZED, "invalid_auth");
    };
    let Ok(grant) = s.grant_keyring.open(&r.endpoint_grant) else {
        return error(StatusCode::NOT_FOUND, "invalid_grant");
    };
    let now = (s.now)();
    if grant.v != WIRE_VERSION
        || !valid_relay_pubkey(&grant.relay_pubkey)
        || grant.relay_pubkey != relay
        || grant.endpoint_epoch < 1
        || grant.generation < 1
        || grant.expires_at < now
        || r.expires_at < now
        || r.expires_at > grant.expires_at
    {
        return error(StatusCode::NOT_FOUND, "invalid_grant");
    }
    let Some(hash) = bound_origin_hash(&r.origin, &grant.relay_pubkey) else {
        return error(StatusCode::NOT_FOUND, "invalid_grant");
    };
    let permit = match s
        .authority
        .authorize_delivery(
            grant.delegation_id,
            &relay,
            grant.endpoint_epoch,
            grant.generation,
            &event_id,
            r.request_id,
            r.expires_at,
            s.endpoint_quota_window_seconds,
            s.endpoint_quota_max_deliveries,
            now,
        )
        .await
    {
        Ok(permit) => permit,
        Err(AuthorityError::RateLimited) => {
            return error(StatusCode::TOO_MANY_REQUESTS, "rate_limited")
        }
        Err(AuthorityError::Unavailable) => {
            return error(StatusCode::SERVICE_UNAVAILABLE, "temporarily_unavailable")
        }
        Err(_) => return error(StatusCode::NOT_FOUND, "invalid_grant"),
    };
    if permit.authority.profile != grant.app_profile
        || permit.authority.profile != AppProfile::BuzzIosDogfood
    {
        let _ = s
            .authority
            .finish_delivery(permit, DeliveryDisposition::Terminal)
            .await;
        return error(StatusCode::NOT_FOUND, "invalid_grant");
    }
    let installation = permit.authority.installation_id;
    let op = r.op;
    let Some(transport) = s.profile.live_activity.clone() else {
        let _ = s
            .authority
            .finish_delivery(permit, DeliveryDisposition::Terminal)
            .await;
        return response(
            Finished::Status(LiveActivityDeliveryResponse::NotRegistered),
            op,
        );
    };
    let job = Job {
        s: s.clone(),
        transport,
        installation,
        origin: r.origin,
        origin_hash: hash,
        state: r.state,
        attempt: LiveActivityAttempt {
            request_id: r.request_id,
            expires_at: r.expires_at,
            priority: r.priority,
        },
        now,
    };
    let authority = Arc::clone(&s.authority);
    let delivery = tokio::spawn(async move {
        let finished = match authority
            .live_activity_target(installation, hash, now)
            .await
        {
            Ok(Some(target)) => job.run(target, op).await,
            Ok(None) => Finished::Status(LiveActivityDeliveryResponse::NotRegistered),
            Err(_) => Finished::Unavailable,
        };
        authority
            .finish_delivery(permit, finished.disposition())
            .await
            .map(|()| finished)
    });
    match delivery.await {
        Ok(Ok(finished)) => response(finished, op),
        _ => response(Finished::Unavailable, op),
    }
}

#[cfg(test)]
#[path = "http_live_activity_tests.rs"]
mod tests;

#[cfg(test)]
mod transcript_vector_tests {
    use super::super::transcript;
    use super::*;
    use sha2::{Digest, Sha256};

    const VECTORS_JSON: &str = include_str!("../tests/vectors/app_attest_transcripts.json");
    const CHALLENGE_ID: uuid::Uuid =
        uuid::Uuid::from_u128(0x1111_1111_1111_4111_8111_1111_1111_1111);
    const INSTALLATION: uuid::Uuid =
        uuid::Uuid::from_u128(0x2222_2222_2222_4222_8222_2222_2222_2222);
    const CHALLENGE: &str = "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8";
    const ENDPOINT: &str = "0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20";

    fn inputs() -> serde_json::Value {
        serde_json::from_str::<serde_json::Value>(VECTORS_JSON).unwrap()["inputs"].clone()
    }

    fn assert_vector(name: &str, actual: &str) {
        let file: serde_json::Value = serde_json::from_str(VECTORS_JSON).unwrap();
        let vector = file["vectors"]
            .as_array()
            .unwrap()
            .iter()
            .find(|v| v["name"] == name)
            .unwrap_or_else(|| panic!("vector {name} missing from fixture"));
        assert_eq!(actual, vector["transcript"].as_str().unwrap(), "{name}");
        assert_eq!(
            hex::encode(Sha256::digest(actual.as_bytes())),
            vector["sha256"].as_str().unwrap(),
            "{name} sha256"
        );
    }

    fn origin_hash_hex() -> String {
        let hash = hex::encode(
            bound_origin_hash(
                inputs()["live_activity_origin"].as_str().unwrap(),
                inputs()["relay_pubkey"].as_str().unwrap(),
            )
            .unwrap(),
        );
        assert_eq!(
            hash,
            inputs()["live_activity_origin_hash"].as_str().unwrap()
        );
        hash
    }

    #[test]
    fn live_activity_transcript_vector() {
        let origins = vec![origin_hash_hex()];
        assert_eq!(inputs()["live_activity_token"].as_str().unwrap(), ENDPOINT);
        for (name, start_token, origins) in [
            ("live_activity", Some(ENDPOINT), origins.as_slice()),
            ("live_activity_off", None, &[][..]),
        ] {
            let t = RegistrationTranscript {
                v: 1,
                audience: "https://push.buzz.xyz/v1/installations/live-activity",
                challenge_id: CHALLENGE_ID,
                challenge: CHALLENGE,
                installation_handle: INSTALLATION,
                start_token,
                origins,
            };
            assert_eq!(t.audience, LIVE_ACTIVITY_AUDIENCE);
            assert_vector(name, &transcript("buzz.push.live-activity.v1", &t).unwrap());
        }
    }

    #[test]
    fn live_activity_update_transcript_vector() {
        let hash = origin_hash_hex();
        for (name, update_token) in [
            ("live_activity_update", Some(ENDPOINT)),
            ("live_activity_update_clear", None),
        ] {
            let t = UpdateTokenTranscript {
                v: 1,
                audience: "https://push.buzz.xyz/v1/installations/live-activity/update-token",
                challenge_id: CHALLENGE_ID,
                challenge: CHALLENGE,
                installation_handle: INSTALLATION,
                origin_hash: &hash,
                update_token,
            };
            assert_eq!(t.audience, LIVE_ACTIVITY_UPDATE_AUDIENCE);
            assert_vector(
                name,
                &transcript("buzz.push.live-activity-update.v1", &t).unwrap(),
            );
        }
    }

    #[test]
    fn plan_follows_the_delivery_table() {
        let target = |update: bool, started_at: Option<i64>| LiveActivityTarget {
            start_ciphertext: vec![1],
            update_ciphertext: update.then(|| vec![2]),
            started_at,
        };
        let now = 100_000;
        for (update, started, op, expected) in [
            (true, Some(now - 10), LiveActivityOp::Upsert, Plan::Update),
            (true, None, LiveActivityOp::Upsert, Plan::Update),
            (
                true,
                Some(now - CARD_LIFETIME_SECONDS),
                LiveActivityOp::Upsert,
                Plan::Start { end_first: false },
            ),
            (false, Some(now - 59), LiveActivityOp::Upsert, Plan::Pending),
            (
                false,
                Some(now - START_RETRY_SECONDS + 1),
                LiveActivityOp::Upsert,
                Plan::Pending,
            ),
            (
                false,
                Some(now - START_RETRY_SECONDS),
                LiveActivityOp::Upsert,
                Plan::Start { end_first: false },
            ),
            (
                false,
                None,
                LiveActivityOp::Upsert,
                Plan::Start { end_first: false },
            ),
            (
                true,
                Some(now),
                LiveActivityOp::Restart,
                Plan::Start { end_first: true },
            ),
            (
                false,
                Some(now),
                LiveActivityOp::Restart,
                Plan::Start { end_first: false },
            ),
            (true, Some(now), LiveActivityOp::End, Plan::End),
            (false, Some(now), LiveActivityOp::End, Plan::AlreadyEnded),
        ] {
            assert_eq!(
                plan(&target(update, started), op, now),
                expected,
                "{update} {started:?} {op:?}"
            );
        }
    }
}
