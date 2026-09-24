//! Relay-staff moderation authority, end to end against Postgres.
//!
//! Relay staff (config operators and `relay_operators` rows) hold ban,
//! timeout, lift, report resolution and the moderation reads in every
//! community — and nothing else. The negative cases drive each excluded
//! capability through its real handler to pin that none of them started
//! consulting the relay roster.

use std::sync::Arc;

use axum::{body::Body, http::Request};
use base64::Engine;
use buzz_core::{
    channel::{ChannelType, ChannelVisibility},
    tenant::TenantContext,
};
use nostr::{Event, EventBuilder, Keys, Kind, Tag};
use sha2::{Digest, Sha256};
use tower::ServiceExt;
use uuid::Uuid;

use crate::handlers::ingest::{ingest_event, HttpAuthMethod, IngestAuth};
use crate::state::AppState;

struct Fixture {
    state: Arc<AppState>,
    tenant: TenantContext,
    host: String,
    owner: Keys,
    admin: Keys,
    operator: Keys,
    moderator: Keys,
    channel: Uuid,
    pool: sqlx::PgPool,
}

impl Fixture {
    async fn new() -> Self {
        let state = super::postgres_tests::bridge_handler_test_state()
            .await
            .expect("local Postgres + Redis required");
        let operator = Keys::generate();
        let mut state = (*state).clone();
        {
            let config = Arc::make_mut(&mut state.config);
            config.relay_operator_pubkeys = vec![operator.public_key().to_hex()];
            config.relay_owner_pubkey = None;
        }
        let state = Arc::new(state);

        let host = format!("relay-staff-{}.local", Uuid::new_v4().simple());
        let community = state
            .db
            .ensure_configured_community(&host)
            .await
            .expect("ensure community")
            .id;
        let tenant = TenantContext::resolved(community, &host);

        let (owner, admin, moderator) = (Keys::generate(), Keys::generate(), Keys::generate());
        for (keys, role) in [(&owner, "owner"), (&admin, "admin")] {
            state
                .db
                .add_relay_member(community, &keys.public_key().to_hex(), role, None)
                .await
                .expect("add relay member");
        }
        state
            .db
            .upsert_relay_operator(
                &moderator.public_key().to_bytes(),
                "moderator",
                &operator.public_key().to_bytes(),
                true,
            )
            .await
            .expect("insert relay moderator");

        let channel = Uuid::new_v4();
        state
            .db
            .create_channel_with_id(
                community,
                channel,
                "relay-staff",
                ChannelType::Stream,
                ChannelVisibility::Open,
                None,
                &owner.public_key().to_bytes(),
                None,
            )
            .await
            .expect("create channel");

        let pool = sqlx::PgPool::connect(&crate::test_support::database_url())
            .await
            .expect("connect test pool");
        Self {
            pool,
            state,
            tenant,
            host,
            owner,
            admin,
            operator,
            moderator,
            channel,
        }
    }

    async fn submit(&self, event: Event) -> Result<(), String> {
        let auth = IngestAuth::Http {
            pubkey: event.pubkey,
            scopes: buzz_auth::Scope::all_known(),
            auth_method: HttpAuthMethod::Nip98,
        };
        ingest_event(&self.state, &self.tenant, event, auth)
            .await
            .map(|_| ())
            .map_err(|e| format!("{e:?}"))
    }

    async fn get(&self, keys: &Keys, path: &str) -> (u16, serde_json::Value) {
        self.request(keys, "GET", path, Vec::new()).await
    }

    async fn request(
        &self,
        keys: &Keys,
        method: &str,
        path: &str,
        body: Vec<u8>,
    ) -> (u16, serde_json::Value) {
        let url = super::nip98_expected_url(&self.state.config.relay_url, &self.tenant, path);
        let mut tags = vec![
            Tag::parse(["u", url.as_str()]).unwrap(),
            Tag::parse(["method", method]).unwrap(),
        ];
        if !body.is_empty() {
            let digest = hex::encode(Sha256::digest(&body));
            tags.push(Tag::parse(["payload", digest.as_str()]).unwrap());
        }
        let auth = EventBuilder::new(Kind::HttpAuth, "")
            .tags(tags)
            .sign_with_keys(keys)
            .unwrap();
        let header = format!(
            "Nostr {}",
            base64::engine::general_purpose::STANDARD.encode(serde_json::to_string(&auth).unwrap())
        );
        let response = crate::router::build_router(self.state.clone())
            .oneshot(
                Request::builder()
                    .method(method)
                    .uri(path)
                    .header("host", &self.host)
                    .header("authorization", header)
                    .header("content-type", "application/json")
                    .body(Body::from(body))
                    .unwrap(),
            )
            .await
            .unwrap();
        let status = response.status().as_u16();
        let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
            .await
            .unwrap();
        (status, serde_json::from_slice(&bytes).unwrap_or_default())
    }

    async fn last_audit_authority(&self, action: &str) -> String {
        sqlx::query_scalar(
            "SELECT actor_authority FROM moderation_actions \
             WHERE community_id = $1 AND action = $2 ORDER BY created_at DESC LIMIT 1",
        )
        .bind(*self.tenant.community().as_uuid())
        .bind(action)
        .fetch_one(&self.pool)
        .await
        .expect("audit row")
    }

    async fn cleanup(self) {
        sqlx::query("DELETE FROM relay_operators WHERE pubkey = $1")
            .bind(self.moderator.public_key().to_bytes().to_vec())
            .execute(&self.pool)
            .await
            .expect("remove relay moderator");
    }
}

fn signed(keys: &Keys, kind: u16, tags: &[&[&str]]) -> Event {
    EventBuilder::new(Kind::Custom(kind), "")
        .tags(tags.iter().map(|t| Tag::parse(t.iter().copied()).unwrap()))
        .sign_with_keys(keys)
        .unwrap()
}

fn future_secs(delta: i64) -> String {
    (chrono::Utc::now().timestamp() + delta).to_string()
}

#[tokio::test]
#[ignore = "requires Postgres + Redis"]
async fn relay_moderator_without_community_role_bans_the_owner() {
    let f = Fixture::new().await;
    let owner_hex = f.owner.public_key().to_hex();
    f.submit(signed(&f.moderator, 9040, &[&["p", &owner_hex]]))
        .await
        .expect("relay moderator must be able to ban the community owner");
    assert_eq!(f.last_audit_authority("ban").await, "relay_moderator");

    f.submit(signed(&f.moderator, 9041, &[&["p", &owner_hex]]))
        .await
        .expect("relay moderator must be able to lift the ban");
    assert_eq!(f.last_audit_authority("unban").await, "relay_moderator");
    f.cleanup().await;
}

#[tokio::test]
#[ignore = "requires Postgres + Redis"]
async fn config_operator_times_out_and_releases_a_community_admin() {
    let f = Fixture::new().await;
    let admin_hex = f.admin.public_key().to_hex();
    let until = future_secs(600);
    f.submit(signed(
        &f.operator,
        9042,
        &[&["p", &admin_hex], &["expiration", &until]],
    ))
    .await
    .expect("config operator must be able to time out a community admin");
    assert_eq!(f.last_audit_authority("timeout").await, "relay_operator");

    f.submit(signed(&f.operator, 9043, &[&["p", &admin_hex]]))
        .await
        .expect("config operator must be able to clear the timeout");
    assert_eq!(f.last_audit_authority("untimeout").await, "relay_operator");
    f.cleanup().await;
}

#[tokio::test]
#[ignore = "requires Postgres + Redis"]
async fn community_admin_who_is_relay_staff_bans_the_owner_as_relay_staff() {
    let f = Fixture::new().await;
    f.state
        .db
        .add_relay_member(
            f.tenant.community(),
            &f.moderator.public_key().to_hex(),
            "admin",
            None,
        )
        .await
        .expect("make moderator a community admin");
    let owner_hex = f.owner.public_key().to_hex();
    f.submit(signed(&f.moderator, 9040, &[&["p", &owner_hex]]))
        .await
        .expect("admin+staff must be able to ban the owner");
    assert_eq!(f.last_audit_authority("ban").await, "relay_moderator");
    f.cleanup().await;
}

#[tokio::test]
#[ignore = "requires Postgres + Redis"]
async fn community_owner_who_is_relay_staff_is_audited_as_community() {
    let f = Fixture::new().await;
    f.state
        .db
        .upsert_relay_operator(
            &f.owner.public_key().to_bytes(),
            "moderator",
            &f.operator.public_key().to_bytes(),
            true,
        )
        .await
        .expect("make owner relay staff");
    let admin_hex = f.admin.public_key().to_hex();
    let result = f
        .submit(signed(&f.owner, 9040, &[&["p", &admin_hex]]))
        .await;
    sqlx::query("DELETE FROM relay_operators WHERE pubkey = $1")
        .bind(f.owner.public_key().to_bytes().to_vec())
        .execute(&f.pool)
        .await
        .unwrap();
    result.expect("owner must be able to ban an admin");
    assert_eq!(f.last_audit_authority("ban").await, "community");
    f.cleanup().await;
}

#[tokio::test]
#[ignore = "requires Postgres + Redis"]
async fn relay_staff_resolve_a_report_audited_as_relay_staff() {
    let f = Fixture::new().await;
    let report_event_id = [7u8; 16]
        .iter()
        .chain(Uuid::new_v4().as_bytes())
        .copied()
        .collect::<Vec<u8>>();
    sqlx::query(
        "INSERT INTO moderation_reports (community_id, report_event_id, reporter_pubkey, \
         target_kind, target_pubkey, report_type) VALUES ($1, $2, $3, 'pubkey', $4, 'spam')",
    )
    .bind(*f.tenant.community().as_uuid())
    .bind(&report_event_id)
    .bind(f.admin.public_key().to_bytes().to_vec())
    .bind(f.owner.public_key().to_bytes().to_vec())
    .execute(&f.pool)
    .await
    .expect("insert report");

    let report_hex = hex::encode(&report_event_id);
    f.submit(signed(
        &f.moderator,
        9044,
        &[
            &["report", &report_hex],
            &["status", "dismissed"],
            &["action", "dismiss"],
        ],
    ))
    .await
    .expect("relay moderator must be able to resolve a report");
    assert_eq!(
        f.last_audit_authority("dismiss_report").await,
        "relay_moderator"
    );
    f.cleanup().await;
}

#[tokio::test]
#[ignore = "requires Postgres + Redis"]
async fn moderation_reads_admit_relay_staff_and_deny_strangers() {
    let f = Fixture::new().await;
    let stranger = Keys::generate();
    for path in [
        "/moderation/reports",
        "/moderation/audit",
        "/moderation/restricted",
    ] {
        for staff in [&f.operator, &f.moderator] {
            assert_eq!(f.get(staff, path).await.0, 200, "staff must read {path}");
        }
        assert_eq!(
            f.get(&stranger, path).await.0,
            403,
            "a stranger must not read {path}"
        );
    }
    f.cleanup().await;
}

#[tokio::test]
#[ignore = "requires Postgres + Redis"]
async fn moderation_me_reports_only_the_callers_own_role() {
    let f = Fixture::new().await;
    for (keys, expected) in [
        (&f.operator, serde_json::json!("operator")),
        (&f.moderator, serde_json::json!("moderator")),
        (&f.owner, serde_json::Value::Null),
    ] {
        let (status, body) = f.get(keys, "/moderation/me").await;
        assert_eq!(status, 200);
        assert_eq!(body, serde_json::json!({ "relayStaff": expected }));
    }
    let unsigned = crate::router::build_router(f.state.clone())
        .oneshot(
            Request::builder()
                .uri("/moderation/me")
                .header("host", &f.host)
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(unsigned.status().as_u16(), 401);
    f.cleanup().await;
}

/// Every capability outside the moderation-only set stays denied to relay
/// staff who hold no community or channel role.
#[tokio::test]
#[ignore = "requires Postgres + Redis"]
async fn relay_staff_cannot_reach_any_excluded_capability() {
    let f = Fixture::new().await;
    let channel = f.channel.to_string();
    let owner_hex = f.owner.public_key().to_hex();
    let admin_hex = f.admin.public_key().to_hex();
    let stranger_hex = Keys::generate().public_key().to_hex();

    let message = signed(&f.admin, 9, &[&["h", &channel]]);
    f.submit(message.clone()).await.expect("seed a message");
    let message_id = message.id.to_hex();

    for staff in [&f.operator, &f.moderator] {
        let excluded: [(&str, &str, Event); 8] = [
            (
                "9005 delete another's message",
                "must be event author or channel owner/admin",
                signed(staff, 9005, &[&["h", &channel], &["e", &message_id]]),
            ),
            (
                "9001 kick",
                "actor not authorized",
                signed(staff, 9001, &[&["h", &channel], &["p", &admin_hex]]),
            ),
            (
                "9002 channel settings",
                "actor not authorized",
                signed(staff, 9002, &[&["h", &channel], &["name", "renamed"]]),
            ),
            (
                "9030 add member",
                "must be admin or owner",
                signed(staff, 9030, &[&["p", &stranger_hex]]),
            ),
            (
                "9031 remove member",
                "must be admin or owner",
                signed(staff, 9031, &[&["p", &admin_hex]]),
            ),
            (
                "9032 role change",
                "must be owner",
                signed(staff, 9032, &[&["p", &admin_hex], &["role", "member"]]),
            ),
            (
                "9033 community icon",
                "must be admin or owner",
                signed(staff, 9033, &[&["icon", "https://example.com/i.png"]]),
            ),
            (
                "9035 identity archive",
                // Not an admin consent path: falls to owner-consent, which needs a signed auth tag.
                "missing auth tag",
                signed(staff, 9035, &[&["p", &owner_hex], &["-"]]),
            ),
        ];
        for (label, denial, event) in excluded {
            let err = f.submit(event).await.expect_err(label);
            assert!(
                err.contains(denial),
                "relay staff must NOT be able to {label}; expected `{denial}`, got {err}"
            );
        }
        let (status, _) = f
            .request(staff, "POST", "/api/invites", b"{}".to_vec())
            .await;
        assert_eq!(status, 403, "relay staff must NOT be able to mint invites");
    }
    f.cleanup().await;
}
