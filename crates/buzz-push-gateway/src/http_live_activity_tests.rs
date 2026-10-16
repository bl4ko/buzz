use super::*;
use crate::{
    apns::DeliveryOutcome,
    app_attest::AppAttestVerifier,
    authority::{AuthorityStore, Challenge, Delegation, MemoryAuthorityStore, NewInstallation},
    grant::{GrantKey, GrantKeyring},
    http::ProfileRuntime,
    http_delivery_tests::signed_header,
    live_activity::LiveActivityTransport,
    router,
    token::{TokenKey, TokenKeyring},
};
use aws_lc_rs::{
    rand::SystemRandom,
    signature::{EcdsaKeyPair, KeyPair, ECDSA_P256_SHA256_ASN1_SIGNING},
};
use axum::{body::Body, http::Request};
use base64::{
    engine::general_purpose::{STANDARD, URL_SAFE_NO_PAD},
    Engine as _,
};
use nostr::Keys;
use sha2::{Digest, Sha256};
use std::{
    collections::HashMap,
    sync::{
        atomic::{AtomicBool, AtomicU8},
        Mutex,
    },
};
use tower::ServiceExt;
use uuid::Uuid;

const APP_ID: &str = "TEAMID.xyz.block.buzz.dogfood.mobile";
const ORIGIN: &str = "https://buzz.bl4ko.com";
const OTHER_ORIGIN: &str = "https://other.bl4ko.com";
const DELIVERY_URL: &str = "http://push.example:8080/v1/deliveries/live-activity";
const START: [u8; 8] = [0xaa; 8];
const UPDATE: [u8; 8] = [0xbb; 8];

fn now() -> i64 {
    1_750_000_000
}

fn hash_for(origin: &str, relay: &Keys) -> [u8; 32] {
    bound_origin_hash(origin, &relay.public_key().to_hex()).unwrap()
}

#[derive(Default)]
struct FakeLiveActivity {
    sends: Mutex<Vec<(String, serde_json::Value, u8)>>,
    outcomes: Mutex<HashMap<String, DeliveryOutcome>>,
}

#[async_trait::async_trait]
impl LiveActivityTransport for FakeLiveActivity {
    async fn send(
        &self,
        attempt: LiveActivityAttempt,
        token_hex: &str,
        payload: &[u8],
    ) -> DeliveryOutcome {
        self.sends.lock().unwrap().push((
            token_hex.to_owned(),
            serde_json::from_slice(payload).unwrap(),
            attempt.priority,
        ));
        self.outcomes
            .lock()
            .unwrap()
            .get(token_hex)
            .copied()
            .unwrap_or(DeliveryOutcome::Accepted)
    }
}

impl FakeLiveActivity {
    fn sent(&self) -> Vec<(String, String, u8)> {
        self.sends
            .lock()
            .unwrap()
            .iter()
            .map(|(token, body, priority)| {
                (
                    token.clone(),
                    body["aps"]["event"].as_str().unwrap().to_owned(),
                    *priority,
                )
            })
            .collect()
    }
}

struct NoAlerts;

#[async_trait::async_trait]
impl crate::apns::PushTransport for NoAlerts {
    async fn send(&self, _: crate::apns::DeliveryAttempt, _: &str) -> DeliveryOutcome {
        panic!("Live Activity routes never send alert pushes")
    }
}

struct Harness {
    app: axum::Router,
    state: AppState,
    relay: Keys,
    grant: String,
    installation: Uuid,
    device: EcdsaKeyPair,
    counter: AtomicU8,
    la: Arc<FakeLiveActivity>,
}

async fn harness(credentials: bool) -> Harness {
    let relay = Keys::generate();
    let device = EcdsaKeyPair::generate(&ECDSA_P256_SHA256_ASN1_SIGNING).unwrap();
    let authority = Arc::new(MemoryAuthorityStore::default());
    let token_keyring =
        Arc::new(TokenKeyring::new(vec![TokenKey::new("test", &[2; 32]).unwrap()]).unwrap());
    let grant_keyring =
        Arc::new(GrantKeyring::new(vec![GrantKey::new("test", &[1; 32]).unwrap()]).unwrap());
    let installation = Uuid::new_v4();
    authority
        .create_installation(
            NewInstallation {
                id: installation,
                app_attest_key_id: vec![3; 32],
                app_attest_public_key: device.public_key().as_ref().to_vec(),
                assertion_counter: 0,
                profile: AppProfile::BuzzIosDogfood,
                token_ciphertext: token_keyring.seal(&[1, 2, 3, 4]).unwrap(),
                token_fingerprint: [5; 32],
                endpoint_epoch: 1,
                expires_at: now() + 600,
            },
            now(),
        )
        .await
        .unwrap();
    let delegation_id = Uuid::new_v4();
    authority
        .upsert_delegation(Delegation {
            id: delegation_id,
            installation_id: installation,
            relay_pubkey: relay.public_key().to_hex(),
            endpoint_epoch: 1,
            generation: 1,
            not_before: now(),
            expires_at: now() + 600,
            revoked: false,
        })
        .await
        .unwrap();
    let grant = grant_keyring
        .issue(&EndpointGrant {
            v: 1,
            delegation_id,
            relay_pubkey: relay.public_key().to_hex(),
            app_profile: AppProfile::BuzzIosDogfood,
            endpoint_epoch: 1,
            generation: 1,
            expires_at: now() + 600,
        })
        .unwrap();
    let la = Arc::new(FakeLiveActivity::default());
    let live_activity: Option<Arc<dyn LiveActivityTransport>> =
        if credentials { Some(la.clone()) } else { None };
    let state = AppState {
        grant_keyring,
        authority,
        token_keyring,
        profile: Arc::new(ProfileRuntime {
            app_attest: Arc::new(
                AppAttestVerifier::new(
                    APP_ID.into(),
                    include_bytes!("../tests/fixtures/apple-app-attestation-root.pem").to_vec(),
                )
                .unwrap(),
            ),
            transport: Arc::new(NoAlerts),
            live_activity,
        }),
        max_grant_lifetime_seconds: 600,
        max_installation_lifetime_seconds: 600,
        endpoint_quota_window_seconds: 60,
        endpoint_quota_max_deliveries: 10,
        now,
        accepting: Arc::new(AtomicBool::new(true)),
    };
    let (app, _) = router(state.clone());
    Harness {
        app,
        state,
        relay,
        grant,
        installation,
        device,
        counter: AtomicU8::new(0),
        la,
    }
}

fn delivery_with(grant: &str, op: &str, origin: &str, state: serde_json::Value) -> Vec<u8> {
    serde_json::to_vec(&serde_json::json!({
        "v": 1,
        "endpoint_grant": grant,
        "request_id": Uuid::new_v4(),
        "expires_at": now() + 60,
        "origin": origin,
        "op": op,
        "priority": 10,
        "state": state,
    }))
    .unwrap()
}

fn state(open_count: u16) -> serde_json::Value {
    serde_json::json!({
        "askEventID": "ab".repeat(32),
        "caseID": "BUZZ-7",
        "ask": "Ship it?",
        "agent": "Zeus",
        "channel": "tasks-test",
        "openCount": open_count,
        "askedAt": now() - 5,
    })
}

impl Harness {
    fn hash(&self, origin: &str) -> [u8; 32] {
        hash_for(origin, &self.relay)
    }

    fn hash_hex(&self, origin: &str) -> String {
        hex::encode(self.hash(origin))
    }

    async fn foreign_relay(&self) -> (Keys, String) {
        let relay = Keys::generate();
        let delegation_id = Uuid::new_v4();
        self.state
            .authority
            .upsert_delegation(Delegation {
                id: delegation_id,
                installation_id: self.installation,
                relay_pubkey: relay.public_key().to_hex(),
                endpoint_epoch: 1,
                generation: 1,
                not_before: now(),
                expires_at: now() + 600,
                revoked: false,
            })
            .await
            .unwrap();
        let grant = self
            .state
            .grant_keyring
            .issue(&EndpointGrant {
                v: 1,
                delegation_id,
                relay_pubkey: relay.public_key().to_hex(),
                app_profile: AppProfile::BuzzIosDogfood,
                endpoint_epoch: 1,
                generation: 1,
                expires_at: now() + 600,
            })
            .unwrap();
        (relay, grant)
    }

    async fn challenge(&self) -> (Uuid, String) {
        let id = Uuid::new_v4();
        let value = *Uuid::new_v4().as_bytes();
        let value: [u8; 32] = [value, value].concat().try_into().unwrap();
        self.state
            .authority
            .put_challenge(Challenge {
                id,
                value,
                created_at: now(),
                expires_at: now() + 300,
            })
            .await
            .unwrap();
        (id, URL_SAFE_NO_PAD.encode(value))
    }

    fn assertion(&self, transcript: &str, counter: u32) -> String {
        let mut authenticator = Sha256::digest(APP_ID.as_bytes()).to_vec();
        authenticator.push(0x40);
        authenticator.extend(counter.to_be_bytes());
        let client_data_hash = Sha256::digest(transcript.as_bytes());
        let nonce = Sha256::digest([authenticator.as_slice(), &client_data_hash].concat());
        let signature = self.device.sign(&SystemRandom::new(), &nonce).unwrap();
        let mut cbor = vec![0xa2];
        for (key, value) in [
            ("signature", signature.as_ref()),
            ("authenticatorData", authenticator.as_slice()),
        ] {
            cbor.push(0x60 + key.len() as u8);
            cbor.extend(key.as_bytes());
            cbor.extend([0x58, value.len() as u8]);
            cbor.extend(value);
        }
        STANDARD.encode(cbor)
    }

    fn next_counter(&self) -> u32 {
        u32::from(
            self.counter
                .fetch_add(1, std::sync::atomic::Ordering::SeqCst)
                + 1,
        )
    }

    async fn post(&self, path: &str, body: serde_json::Value) -> (StatusCode, serde_json::Value) {
        let response = self
            .app
            .clone()
            .oneshot(
                Request::post(path)
                    .header("content-type", "application/json")
                    .body(Body::from(serde_json::to_vec(&body).unwrap()))
                    .unwrap(),
            )
            .await
            .unwrap();
        let status = response.status();
        let bytes = axum::body::to_bytes(response.into_body(), 64 * 1024)
            .await
            .unwrap();
        (
            status,
            serde_json::from_slice(&bytes).unwrap_or(serde_json::Value::Null),
        )
    }

    async fn register_with(
        &self,
        start_token: Option<&str>,
        origins: Vec<String>,
        counter: u32,
        extra: Option<(&str, serde_json::Value)>,
    ) -> (StatusCode, serde_json::Value) {
        let (challenge_id, challenge) = self.challenge().await;
        let t = RegistrationTranscript {
            v: 1,
            audience: LIVE_ACTIVITY_AUDIENCE,
            challenge_id,
            challenge: &challenge,
            installation_handle: self.installation,
            start_token,
            origins: &origins,
        };
        let transcript = super::super::transcript("buzz.push.live-activity.v1", &t).unwrap();
        let mut body = serde_json::json!({
            "v": 1,
            "challenge_id": challenge_id,
            "challenge": challenge,
            "installation_handle": self.installation,
            "start_token": start_token,
            "origins": origins,
            "assertion": self.assertion(&transcript, counter),
        });
        if let Some((key, value)) = extra {
            body[key] = value;
        }
        self.post("/v1/installations/live-activity", body).await
    }

    async fn register(&self, start_token: Option<&str>, origins: Vec<String>) -> StatusCode {
        self.register_with(start_token, origins, self.next_counter(), None)
            .await
            .0
    }

    async fn set_update(
        &self,
        origin_hash: &str,
        update_token: Option<&str>,
    ) -> (StatusCode, serde_json::Value) {
        let (challenge_id, challenge) = self.challenge().await;
        let t = UpdateTokenTranscript {
            v: 1,
            audience: LIVE_ACTIVITY_UPDATE_AUDIENCE,
            challenge_id,
            challenge: &challenge,
            installation_handle: self.installation,
            origin_hash,
            update_token,
        };
        let transcript = super::super::transcript("buzz.push.live-activity-update.v1", &t).unwrap();
        let body = serde_json::json!({
            "v": 1,
            "challenge_id": challenge_id,
            "challenge": challenge,
            "installation_handle": self.installation,
            "origin_hash": origin_hash,
            "update_token": update_token,
            "assertion": self.assertion(&transcript, self.next_counter()),
        });
        self.post("/v1/installations/live-activity/update-token", body)
            .await
    }

    async fn target(&self, origin: &str) -> Option<LiveActivityTarget> {
        self.state
            .authority
            .live_activity_target(self.installation, self.hash(origin), now())
            .await
            .unwrap()
    }

    async fn seed(&self, started_at: Option<i64>, update: bool) {
        let authority = &self.state.authority;
        let hash = self.hash(ORIGIN);
        authority
            .replace_live_activity_registration(
                self.installation,
                Some(SealedToken {
                    ciphertext: self.state.token_keyring.seal(&START).unwrap(),
                    fingerprint: token_fingerprint(START_FINGERPRINT_DOMAIN, &START),
                }),
                vec![hash],
                now(),
            )
            .await
            .unwrap();
        if let Some(started_at) = started_at {
            authority
                .record_live_activity_start(self.installation, hash, started_at)
                .await
                .unwrap();
        }
        if update {
            authority
                .set_live_activity_update_token(
                    self.installation,
                    hash,
                    Some(SealedToken {
                        ciphertext: self.state.token_keyring.seal(&UPDATE).unwrap(),
                        fingerprint: token_fingerprint(UPDATE_FINGERPRINT_DOMAIN, &UPDATE),
                    }),
                    now(),
                )
                .await
                .unwrap();
        }
    }

    fn delivery(&self, op: &str, origin: &str, state: serde_json::Value) -> Vec<u8> {
        delivery_with(&self.grant, op, origin, state)
    }

    async fn deliver_as(&self, relay: &Keys, body: Vec<u8>) -> (StatusCode, serde_json::Value) {
        let auth = signed_header(relay, DELIVERY_URL, "POST", &body);
        self.deliver_signed(body, auth).await
    }

    async fn deliver_signed(&self, body: Vec<u8>, auth: String) -> (StatusCode, serde_json::Value) {
        let response = self
            .app
            .clone()
            .oneshot(
                Request::post(DELIVERY_PATH)
                    .header("host", "push.example:8080")
                    .header("authorization", auth)
                    .body(Body::from(body))
                    .unwrap(),
            )
            .await
            .unwrap();
        let status = response.status();
        let bytes = axum::body::to_bytes(response.into_body(), 64 * 1024)
            .await
            .unwrap();
        (status, serde_json::from_slice(&bytes).unwrap())
    }

    async fn deliver(&self, body: Vec<u8>) -> (StatusCode, serde_json::Value) {
        let auth = signed_header(&self.relay, DELIVERY_URL, "POST", &body);
        self.deliver_signed(body, auth).await
    }

    async fn upsert(&self) -> (StatusCode, serde_json::Value) {
        self.deliver(self.delivery("upsert", ORIGIN, state(2)))
            .await
    }
}

fn status(name: &str) -> (StatusCode, serde_json::Value) {
    (StatusCode::OK, serde_json::json!({ "status": name }))
}

fn start_hex() -> String {
    hex::encode(START)
}

fn update_hex() -> String {
    hex::encode(UPDATE)
}

#[tokio::test]
async fn la_registration_and_update_token_round_trip() {
    let h = harness(true).await;
    let a = h.hash_hex(ORIGIN);
    let b = h.hash_hex(OTHER_ORIGIN);
    assert_eq!(
        h.register(Some(&start_hex()), vec![a.clone(), b.clone()])
            .await,
        StatusCode::NO_CONTENT
    );
    assert_eq!(
        h.set_update(&a, Some(&update_hex())).await.0,
        StatusCode::NO_CONTENT
    );
    let target = h.target(ORIGIN).await.unwrap();
    assert_eq!(
        h.state
            .token_keyring
            .open(&target.start_ciphertext)
            .unwrap(),
        START
    );
    assert_eq!(
        h.state
            .token_keyring
            .open(&target.update_ciphertext.unwrap())
            .unwrap(),
        UPDATE
    );
    assert!(h.target(OTHER_ORIGIN).await.is_some());
    assert_eq!(h.set_update(&a, None).await.0, StatusCode::NO_CONTENT);
    assert_eq!(h.target(ORIGIN).await.unwrap().update_ciphertext, None);
    assert_eq!(
        h.register(None, vec![a.clone()]).await,
        StatusCode::NO_CONTENT
    );
    assert!(h.target(ORIGIN).await.is_none());
    assert_eq!(
        h.register(Some(&start_hex()), vec![a.clone()]).await,
        StatusCode::NO_CONTENT
    );
    assert_eq!(
        h.register(Some(&start_hex()), vec![]).await,
        StatusCode::NO_CONTENT
    );
    assert!(h.target(ORIGIN).await.is_none());
}

#[tokio::test]
async fn la_registration_rejects_bad_input() {
    let h = harness(true).await;
    let a = h.hash_hex(ORIGIN);
    let many: Vec<String> = (0..17u8).map(|i| hex::encode([i; 32])).collect();
    for (start, origins, extra) in [
        (Some("zz".to_owned()), vec![a.clone()], None),
        (Some("AAAA".to_owned()), vec![a.clone()], None),
        (Some("abc".to_owned()), vec![a.clone()], None),
        (Some("ab".repeat(513)), vec![a.clone()], None),
        (Some(start_hex()), many, None),
        (Some(start_hex()), vec![a.clone(), a.clone()], None),
        (Some(start_hex()), vec![a.to_uppercase()], None),
        (Some(start_hex()), vec![a[..62].to_owned()], None),
        (
            Some(start_hex()),
            vec![a.clone()],
            Some(("extra", serde_json::json!(1))),
        ),
        (
            Some(start_hex()),
            vec![a.clone()],
            Some(("v", serde_json::json!(2))),
        ),
    ] {
        let (code, body) = h
            .register_with(start.as_deref(), origins, h.next_counter(), extra)
            .await;
        assert_eq!(code, StatusCode::BAD_REQUEST);
        assert_eq!(body, serde_json::json!({"error": "invalid_request"}));
    }
    for update in ["zz", "AB"] {
        assert_eq!(
            h.set_update(&a, Some(update)).await.0,
            StatusCode::BAD_REQUEST
        );
    }
    assert_eq!(
        h.set_update(&a.to_uppercase(), None).await.0,
        StatusCode::BAD_REQUEST
    );
    assert!(h.target(ORIGIN).await.is_none());
}

#[tokio::test]
async fn la_registration_rejects_stale_assertion_counter() {
    let h = harness(true).await;
    let a = h.hash_hex(ORIGIN);
    assert_eq!(
        h.register_with(Some(&start_hex()), vec![a.clone()], 3, None)
            .await
            .0,
        StatusCode::NO_CONTENT
    );
    let (code, body) = h.register_with(None, vec![], 3, None).await;
    assert_eq!(code, StatusCode::UNAUTHORIZED);
    assert_eq!(body, serde_json::json!({"error": "invalid_attestation"}));
    assert!(h.target(ORIGIN).await.is_some());
}

#[tokio::test]
async fn la_update_for_unregistered_origin_is_not_found() {
    let h = harness(true).await;
    let a = h.hash_hex(ORIGIN);
    assert_eq!(
        h.set_update(&a, Some(&update_hex())).await,
        (
            StatusCode::NOT_FOUND,
            serde_json::json!({"error": "not_found"})
        )
    );
    assert_eq!(
        h.register(Some(&start_hex()), vec![a]).await,
        StatusCode::NO_CONTENT
    );
    assert_eq!(
        h.set_update(&h.hash_hex(OTHER_ORIGIN), Some(&update_hex()))
            .await
            .0,
        StatusCode::NOT_FOUND
    );
}

#[tokio::test]
async fn la_not_registered_without_start_token() {
    let h = harness(true).await;
    assert_eq!(h.upsert().await, status("not_registered"));
    assert!(h.la.sent().is_empty());
}

#[tokio::test]
async fn la_without_credentials_answers_not_registered() {
    let h = harness(false).await;
    h.seed(None, false).await;
    assert_eq!(h.upsert().await, status("not_registered"));
    assert!(h.la.sent().is_empty());
}

#[tokio::test]
async fn la_upsert_starts_with_start_token() {
    let h = harness(true).await;
    h.seed(None, false).await;
    assert_eq!(h.upsert().await, status("started"));
    assert_eq!(h.la.sent(), [(start_hex(), "start".to_owned(), 10)]);
    let body = h.la.sends.lock().unwrap()[0].1.clone();
    assert_eq!(body["aps"]["attributes"]["origin"], ORIGIN);
    assert_eq!(body["aps"]["content-state"], state(2));
    assert_eq!(body["aps"]["alert"]["body"], "Ship it?");
    let target = h.target(ORIGIN).await.unwrap();
    assert_eq!(target.started_at, Some(now()));
    assert_eq!(target.update_ciphertext, None);
}

#[tokio::test]
async fn la_upsert_updates_with_update_token() {
    let h = harness(true).await;
    h.seed(Some(now() - 100), true).await;
    let mut body: serde_json::Value =
        serde_json::from_slice(&h.delivery("upsert", ORIGIN, state(3))).unwrap();
    body["priority"] = 5.into();
    assert_eq!(
        h.deliver(serde_json::to_vec(&body).unwrap()).await,
        status("updated")
    );
    assert_eq!(h.la.sent(), [(update_hex(), "update".to_owned(), 5)]);
    assert_eq!(
        h.la.sends.lock().unwrap()[0].1["aps"]["content-state"]["openCount"],
        3
    );
}

#[tokio::test]
async fn la_upsert_is_pending_inside_60s_after_start() {
    let h = harness(true).await;
    h.seed(Some(now() - 30), false).await;
    assert_eq!(h.upsert().await, status("pending"));
    assert!(h.la.sent().is_empty());
}

#[tokio::test]
async fn la_upsert_is_pending_inside_30min_without_update_token() {
    let h = harness(true).await;
    h.seed(Some(now() - START_RETRY_SECONDS + 1), false).await;
    assert_eq!(h.upsert().await, status("pending"));
    assert!(h.la.sent().is_empty());
}

#[tokio::test]
async fn la_upsert_restarts_after_30min_without_update_token() {
    let h = harness(true).await;
    h.seed(Some(now() - START_RETRY_SECONDS), false).await;
    assert_eq!(h.upsert().await, status("started"));
    assert_eq!(h.la.sent(), [(start_hex(), "start".to_owned(), 10)]);
    assert_eq!(h.target(ORIGIN).await.unwrap().started_at, Some(now()));
}

#[tokio::test]
async fn la_upsert_starts_again_after_8h_card_lifetime() {
    let h = harness(true).await;
    h.seed(Some(now() - CARD_LIFETIME_SECONDS), true).await;
    assert_eq!(h.upsert().await, status("started"));
    assert_eq!(h.la.sent(), [(start_hex(), "start".to_owned(), 10)]);
    assert_eq!(h.target(ORIGIN).await.unwrap().update_ciphertext, None);
}

#[tokio::test]
async fn la_restart_ends_old_then_starts() {
    let h = harness(true).await;
    h.seed(Some(now() - 7 * 3600), true).await;
    assert_eq!(
        h.deliver(h.delivery("restart", ORIGIN, state(1))).await,
        status("started")
    );
    assert_eq!(
        h.la.sent(),
        [
            (update_hex(), "end".to_owned(), 10),
            (start_hex(), "start".to_owned(), 10)
        ]
    );
    let target = h.target(ORIGIN).await.unwrap();
    assert_eq!(target.update_ciphertext, None);
    assert_eq!(target.started_at, Some(now()));
}

#[tokio::test]
async fn la_end_clears_update_token() {
    let h = harness(true).await;
    h.seed(Some(now() - 100), true).await;
    let end = || h.delivery("end", ORIGIN, serde_json::Value::Null);
    assert_eq!(h.deliver(end()).await, status("ended"));
    assert_eq!(h.la.sent(), [(update_hex(), "end".to_owned(), 10)]);
    let end_body = h.la.sends.lock().unwrap()[0].1.clone();
    assert_eq!(end_body["aps"]["dismissal-date"], now());
    let target = h.target(ORIGIN).await.unwrap();
    assert_eq!((target.update_ciphertext, target.started_at), (None, None));
    assert_eq!(h.deliver(end()).await, status("ended"));
    assert_eq!(h.la.sent().len(), 1);
}

#[tokio::test]
async fn la_rejects_unregistered_origin() {
    let h = harness(true).await;
    h.seed(None, false).await;
    assert_eq!(
        h.deliver(h.delivery("upsert", OTHER_ORIGIN, state(1)))
            .await,
        status("not_registered")
    );
    for origin in [
        "https://buzz.bl4ko.com/",
        "http://buzz.bl4ko.com",
        "https://Buzz.bl4ko.com",
    ] {
        assert_eq!(
            h.deliver(h.delivery("upsert", origin, state(1))).await,
            (
                StatusCode::BAD_REQUEST,
                serde_json::json!({"error": "invalid_request"})
            )
        );
    }
    assert!(h.la.sent().is_empty());
}

#[tokio::test]
async fn la_rejects_origin_registered_for_another_relay() {
    let h = harness(true).await;
    h.seed(Some(now() - 100), true).await;
    let (foreign, grant) = h.foreign_relay().await;
    for (op, state) in [
        ("upsert", state(1)),
        ("restart", state(1)),
        ("end", serde_json::Value::Null),
    ] {
        assert_eq!(
            h.deliver_as(&foreign, delivery_with(&grant, op, ORIGIN, state))
                .await,
            status("not_registered"),
            "{op}"
        );
    }
    assert!(h.la.sent().is_empty());
    let target = h.target(ORIGIN).await.unwrap();
    assert!(target.update_ciphertext.is_some());
    assert_eq!(target.started_at, Some(now() - 100));
    assert_eq!(h.upsert().await, status("updated"));
    assert_eq!(h.la.sent(), [(update_hex(), "update".to_owned(), 10)]);
}

#[tokio::test]
async fn la_rejects_update_token_registered_for_another_relay() {
    let h = harness(true).await;
    let (foreign, grant) = h.foreign_relay().await;
    let own = h.hash_hex(ORIGIN);
    let foreign_hash = hex::encode(hash_for(ORIGIN, &foreign));
    assert_ne!(own, foreign_hash);
    assert_eq!(
        h.register(Some(&start_hex()), vec![own.clone()]).await,
        StatusCode::NO_CONTENT
    );
    assert_eq!(
        h.set_update(&foreign_hash, Some(&update_hex())).await,
        (
            StatusCode::NOT_FOUND,
            serde_json::json!({"error": "not_found"})
        )
    );
    assert_eq!(
        h.set_update(&own, Some(&update_hex())).await.0,
        StatusCode::NO_CONTENT
    );
    for (op, state) in [("upsert", state(1)), ("end", serde_json::Value::Null)] {
        assert_eq!(
            h.deliver_as(&foreign, delivery_with(&grant, op, ORIGIN, state))
                .await,
            status("not_registered"),
            "{op}"
        );
    }
    assert!(h.la.sent().is_empty());
    assert!(h.target(ORIGIN).await.unwrap().update_ciphertext.is_some());
    assert_eq!(
        h.deliver(h.delivery("end", ORIGIN, serde_json::Value::Null))
            .await,
        status("ended")
    );
    assert_eq!(h.la.sent(), [(update_hex(), "end".to_owned(), 10)]);
}

#[tokio::test]
async fn la_rejects_wrong_relay_signer() {
    let h = harness(true).await;
    h.seed(None, false).await;
    let body = h.delivery("upsert", ORIGIN, state(1));
    let auth = signed_header(&Keys::generate(), DELIVERY_URL, "POST", &body);
    assert_eq!(
        h.deliver_signed(body, auth).await,
        (
            StatusCode::NOT_FOUND,
            serde_json::json!({"error": "invalid_grant"})
        )
    );
    let body = h.delivery("upsert", ORIGIN, state(1));
    let wrong_path = signed_header(
        &h.relay,
        "http://push.example:8080/v1/deliveries/apns",
        "POST",
        &body,
    );
    assert_eq!(
        h.deliver_signed(body, wrong_path).await.0,
        StatusCode::UNAUTHORIZED
    );
    assert!(h.la.sent().is_empty());
}

#[tokio::test]
async fn la_rejects_state_for_end() {
    let h = harness(true).await;
    h.seed(Some(now() - 100), true).await;
    let mut bad_priority: serde_json::Value =
        serde_json::from_slice(&h.delivery("upsert", ORIGIN, state(1))).unwrap();
    bad_priority["priority"] = 7.into();
    let mut decision = state(1);
    decision["decision"] = "approve".into();
    let mut unknown: serde_json::Value =
        serde_json::from_slice(&h.delivery("upsert", ORIGIN, state(1))).unwrap();
    unknown["title"] = "x".into();
    for body in [
        h.delivery("end", ORIGIN, state(1)),
        h.delivery("upsert", ORIGIN, serde_json::Value::Null),
        h.delivery("restart", ORIGIN, serde_json::Value::Null),
        h.delivery("upsert", ORIGIN, state(0)),
        h.delivery("upsert", ORIGIN, decision),
        h.delivery("refresh", ORIGIN, state(1)),
        serde_json::to_vec(&bad_priority).unwrap(),
        serde_json::to_vec(&unknown).unwrap(),
    ] {
        assert_eq!(h.deliver(body).await.0, StatusCode::BAD_REQUEST);
    }
    assert!(h.la.sent().is_empty());
}

#[tokio::test]
async fn la_replay_is_rejected() {
    let h = harness(true).await;
    h.seed(None, false).await;
    let body = h.delivery("upsert", ORIGIN, state(1));
    let auth = signed_header(&h.relay, DELIVERY_URL, "POST", &body);
    assert_eq!(
        h.deliver_signed(body.clone(), auth.clone()).await,
        status("started")
    );
    assert_eq!(
        h.deliver_signed(body, auth).await,
        (
            StatusCode::NOT_FOUND,
            serde_json::json!({"error": "invalid_grant"})
        )
    );
    assert_eq!(h.la.sent().len(), 1);
}

#[tokio::test]
async fn la_unregistered_update_token_is_cleared() {
    let h = harness(true).await;
    h.seed(Some(now() - 100), true).await;
    h.la.outcomes.lock().unwrap().insert(
        update_hex(),
        DeliveryOutcome::InvalidEndpoint {
            unregistered_at: None,
        },
    );
    assert_eq!(h.upsert().await, status("pending"));
    let target = h.target(ORIGIN).await.unwrap();
    assert_eq!((target.update_ciphertext, target.started_at), (None, None));

    h.la.outcomes.lock().unwrap().insert(
        start_hex(),
        DeliveryOutcome::InvalidEndpoint {
            unregistered_at: None,
        },
    );
    assert_eq!(h.upsert().await, status("not_registered"));
    assert!(h.target(ORIGIN).await.is_none());
    assert_eq!(
        h.la.sent(),
        [
            (update_hex(), "update".to_owned(), 10),
            (start_hex(), "start".to_owned(), 10)
        ]
    );
}

#[tokio::test]
async fn la_retry_keeps_state_and_releases_request_id() {
    let h = harness(true).await;
    h.seed(None, false).await;
    h.la.outcomes.lock().unwrap().insert(
        start_hex(),
        DeliveryOutcome::Retry {
            retry_after_seconds: Some(30),
        },
    );
    let body = h.delivery("upsert", ORIGIN, state(1));
    assert_eq!(
        h.deliver(body.clone()).await,
        (
            StatusCode::SERVICE_UNAVAILABLE,
            serde_json::json!({"status": "retry", "retry_after_seconds": 30})
        )
    );
    assert_eq!(h.target(ORIGIN).await.unwrap().started_at, None);
    h.la.outcomes.lock().unwrap().clear();
    tokio::time::sleep(std::time::Duration::from_millis(1100)).await;
    assert_eq!(h.deliver(body).await, status("started"));
}
