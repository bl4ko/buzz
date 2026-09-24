//! Delivery authentication through the public router, with an in-memory authority
//! store and APNs transport. No external service or credentials are used.
use std::sync::{
    atomic::{AtomicBool, AtomicUsize, Ordering},
    Arc,
};

use crate::{
    apns::{DeliveryAttempt, DeliveryOutcome, PushTransport},
    app_attest::AppAttestVerifier,
    authority::{AuthorityStore, Delegation, MemoryAuthorityStore, NewInstallation},
    config::GatewayUrls,
    grant::{GrantKey, GrantKeyring},
    http::ProfileRuntime,
    model::{AppProfile, EndpointGrant},
    router,
    token::{TokenKey, TokenKeyring},
    AppState,
};
use axum::{
    body::Body,
    http::{Request, StatusCode},
};
use base64::{engine::general_purpose::STANDARD, Engine as _};
use nostr::{EventBuilder, Keys, Kind, Tag};
use sha2::{Digest, Sha256};
use tower::ServiceExt;
use uuid::Uuid;

const INTERNAL: &str = "http://push-gateway.gateway.svc.cluster.local:8080/v1/deliveries/apns";
const EXTERNAL: &str = "https://push.example/v1/deliveries/apns";

struct TestTransport(Arc<AtomicUsize>);
#[async_trait::async_trait]
impl PushTransport for TestTransport {
    async fn send(&self, _: DeliveryAttempt, endpoint: &str) -> DeliveryOutcome {
        assert_eq!(endpoint, "01020304");
        self.0.fetch_add(1, Ordering::SeqCst);
        DeliveryOutcome::Accepted
    }
}

fn now() -> i64 {
    1_750_000_000
}

async fn fixture() -> (axum::Router, Keys, Vec<u8>, Arc<AtomicUsize>) {
    let keys = Keys::generate();
    let authority = Arc::new(MemoryAuthorityStore::default());
    let token_keyring =
        Arc::new(TokenKeyring::new(vec![TokenKey::new("test", &[2; 32]).unwrap()]).unwrap());
    let grant_keyring =
        Arc::new(GrantKeyring::new(vec![GrantKey::new("test", &[1; 32]).unwrap()]).unwrap());
    let installation_id = Uuid::new_v4();
    authority
        .create_installation(
            NewInstallation {
                id: installation_id,
                app_attest_key_id: vec![3; 32],
                app_attest_public_key: vec![4; 65],
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
            installation_id,
            relay_pubkey: keys.public_key().to_hex(),
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
            relay_pubkey: keys.public_key().to_hex(),
            app_profile: AppProfile::BuzzIosDogfood,
            endpoint_epoch: 1,
            generation: 1,
            expires_at: now() + 600,
        })
        .unwrap();
    let sends = Arc::new(AtomicUsize::new(0));
    let (app, _) = router(AppState {
        grant_keyring,
        authority,
        token_keyring,
        profile: Arc::new(ProfileRuntime {
            app_attest: Arc::new(
                AppAttestVerifier::new(
                    "TEAMID.xyz.block.buzz.dogfood.mobile".into(),
                    include_bytes!("../tests/fixtures/apple-app-attestation-root.pem").to_vec(),
                )
                .unwrap(),
            ),
            transport: Arc::new(TestTransport(sends.clone())),
        }),
        gateway_urls: Arc::new(
            GatewayUrls::from_origin("https://push.example".parse().unwrap()).unwrap(),
        ),
        max_grant_lifetime_seconds: 600,
        max_installation_lifetime_seconds: 600,
        endpoint_quota_window_seconds: 60,
        endpoint_quota_max_deliveries: 10,
        now,
        accepting: Arc::new(AtomicBool::new(true)),
    });
    let body = serde_json::to_vec(&serde_json::json!({
        "v": 1, "endpoint_grant": grant, "request_id": Uuid::new_v4(), "expires_at": now() + 60,
    }))
    .unwrap();
    (app, keys, body, sends)
}

fn signed_header(keys: &Keys, url: &str, method: &str, body: &[u8]) -> String {
    let hash = hex::encode(Sha256::digest(body));
    let event = EventBuilder::new(Kind::HttpAuth, "")
        .tags([
            Tag::parse(["u", url]).unwrap(),
            Tag::parse(["method", method]).unwrap(),
            Tag::parse(["payload", &hash]).unwrap(),
        ])
        .sign_with_keys(keys)
        .unwrap();
    format!(
        "Nostr {}",
        STANDARD.encode(serde_json::to_vec(&event).unwrap())
    )
}

fn request(url: &str, proto: Option<&str>, auth: String, body: Vec<u8>) -> Request<Body> {
    let url = url::Url::parse(url).unwrap();
    let authority = &url[url::Position::BeforeHost..url::Position::AfterPort];
    let path = &url[url::Position::BeforePath..url::Position::AfterQuery];
    let mut request = Request::post(path)
        .header("host", authority)
        .header("authorization", auth);
    if let Some(proto) = proto {
        request = request.header("x-forwarded-proto", proto);
    }
    request.body(Body::from(body)).unwrap()
}

#[tokio::test]
async fn internal_http_and_external_https_deliver_using_request_url() {
    for (url, proto) in [(INTERNAL, None), (EXTERNAL, Some("https"))] {
        let (app, keys, body, sends) = fixture().await;
        let auth = signed_header(&keys, url, "POST", &body);
        let response = app.oneshot(request(url, proto, auth, body)).await.unwrap();
        assert_eq!(response.status(), StatusCode::OK, "{url}");
        assert_eq!(sends.load(Ordering::SeqCst), 1);
    }
}

#[tokio::test]
async fn absolute_request_authority_is_supported() {
    let (app, keys, body, sends) = fixture().await;
    let auth = signed_header(&keys, INTERNAL, "POST", &body);
    let request = Request::post(INTERNAL)
        .header("authorization", auth)
        .body(Body::from(body))
        .unwrap();
    assert_eq!(app.oneshot(request).await.unwrap().status(), StatusCode::OK);
    assert_eq!(sends.load(Ordering::SeqCst), 1);
}

#[tokio::test]
async fn signature_is_bound_to_received_url_method_and_body() {
    for (signed_url, method, changed_body) in [
        (EXTERNAL, "POST", false),
        (
            "http://other.gateway.svc.cluster.local:8080/v1/deliveries/apns",
            "POST",
            false,
        ),
        (
            "http://push-gateway.gateway.svc.cluster.local:8081/v1/deliveries/apns",
            "POST",
            false,
        ),
        (
            "https://push-gateway.gateway.svc.cluster.local:8080/v1/deliveries/apns",
            "POST",
            false,
        ),
        (
            "http://push-gateway.gateway.svc.cluster.local:8080/v1/other",
            "POST",
            false,
        ),
        (INTERNAL, "GET", false),
        (INTERNAL, "POST", true),
    ] {
        let (app, keys, mut body, sends) = fixture().await;
        let auth = signed_header(&keys, signed_url, method, &body);
        if changed_body {
            body.push(b' ');
        }
        let response = app
            .oneshot(request(INTERNAL, None, auth, body))
            .await
            .unwrap();
        assert_eq!(
            response.status(),
            StatusCode::UNAUTHORIZED,
            "{signed_url} {method} {changed_body}"
        );
        assert_eq!(sends.load(Ordering::SeqCst), 0);
    }
}

#[tokio::test]
async fn query_is_part_of_received_url() {
    let with_query = format!("{INTERNAL}?mode=one");
    for signed_url in [INTERNAL, with_query.as_str()] {
        let (app, keys, body, sends) = fixture().await;
        let auth = signed_header(&keys, signed_url, "POST", &body);
        let response = app
            .oneshot(request(&with_query, None, auth, body))
            .await
            .unwrap();
        let matching = signed_url == with_query;
        assert_eq!(
            response.status(),
            if matching {
                StatusCode::OK
            } else {
                StatusCode::UNAUTHORIZED
            }
        );
        assert_eq!(sends.load(Ordering::SeqCst), usize::from(matching));
    }
}

#[tokio::test]
async fn invalid_forwarded_scheme_is_rejected() {
    for proto in ["ftp", "https,http", ""] {
        let (app, keys, body, sends) = fixture().await;
        let auth = signed_header(&keys, EXTERNAL, "POST", &body);
        let response = app
            .oneshot(request(EXTERNAL, Some(proto), auth, body))
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(sends.load(Ordering::SeqCst), 0);
    }
}
