use std::sync::Arc;

use buzz_auth::Scope;
use buzz_core::TenantContext;
use nostr::nips::nip44;
use nostr::{EventBuilder, Keys, Kind, Tag, Timestamp};

use crate::handlers::group_state_postgres_tests::community;
use crate::handlers::ingest::{ingest_event, HttpAuthMethod, IngestAuth, IngestError};
use crate::state::AppState;

struct Relay {
    state: Arc<AppState>,
    tenant: TenantContext,
    origin: String,
    now: i64,
}

impl Relay {
    async fn start() -> Self {
        let mut state = crate::handlers::group_state_postgres_tests::state().await;
        if std::env::var("BUZZ_TEST_SCHEMA_MODE").as_deref() != Ok("desired") {
            state.db.migrate().await.expect("migrate test database");
        }
        Arc::get_mut(&mut Arc::get_mut(&mut state).expect("sole state").config)
            .expect("sole config")
            .push_enabled = true;
        let tenant = community(&state, "push-repair").await;
        let origin = super::canonical_origin(&state.config.relay_url, tenant.host()).unwrap();
        Self {
            state,
            tenant,
            origin,
            now: chrono::Utc::now().timestamp(),
        }
    }

    async fn publish(
        &self,
        author: &Keys,
        installation: &str,
        seconds_ago: i64,
        generation: u64,
        grant: Option<&str>,
    ) -> Result<(), String> {
        let hex = author.public_key().to_hex();
        let body = match grant {
            Some(grant) => serde_json::json!({
                "v": 1, "origin": self.origin, "generation": generation, "active": true,
                "transport": "apns", "endpoint": grant,
                "subscriptions": [{"filter": {"kinds": [9], "#p": [hex]}, "class": "default"}],
            }),
            None => serde_json::json!({
                "v": 1, "origin": self.origin, "generation": generation, "active": false,
            }),
        };
        let content = nip44::encrypt(
            author.secret_key(),
            &self.state.relay_keypair.public_key(),
            body.to_string(),
            nip44::Version::V2,
        )
        .expect("encrypt lease");
        let event = EventBuilder::new(Kind::Custom(super::KIND_PUSH_LEASE as u16), content)
            .tags([
                Tag::parse(["d", installation]).unwrap(),
                Tag::parse(["expiration", &(self.now + 86_400).to_string()]).unwrap(),
                Tag::parse(["exec", &self.state.config.push_executor_key_id]).unwrap(),
            ])
            .custom_created_at(Timestamp::from((self.now - seconds_ago) as u64))
            .sign_with_keys(author)
            .expect("sign lease");
        self.ingest(event, author).await
    }

    async fn ingest(&self, event: nostr::Event, author: &Keys) -> Result<(), String> {
        let auth = IngestAuth::Http {
            pubkey: author.public_key(),
            scopes: vec![Scope::UsersWrite],
            auth_method: HttpAuthMethod::Nip98,
        };
        match ingest_event(&self.state, &self.tenant, event, auth).await {
            Ok(result) if result.accepted => Ok(()),
            Ok(result) => Err(result.message),
            Err(IngestError::Rejected(message)) => Err(message),
            Err(other) => panic!("lease ingest failed: {other:?}"),
        }
    }

    async fn active(&self, author: &Keys) -> Vec<String> {
        sqlx::query_scalar(
            "SELECT installation_id FROM push_leases \
             WHERE community_id=$1 AND author=$2 AND active ORDER BY installation_id",
        )
        .bind(self.tenant.community().as_uuid())
        .bind(author.public_key().as_bytes().as_slice())
        .fetch_all(self.state.db.pool())
        .await
        .expect("active leases")
    }
}

#[tokio::test]
#[ignore = "requires Postgres"]
async fn repaired_iphone_replaces_its_own_lease_on_the_same_grant() {
    let relay = Relay::start().await;
    let owner = Keys::generate();

    relay
        .publish(&owner, "before-repair", 60, 5, Some("device-grant"))
        .await
        .expect("first pairing");
    relay
        .publish(&owner, "after-repair", 30, 1, Some("device-grant"))
        .await
        .expect("a re-paired installation takes over its own endpoint");
    assert_eq!(relay.active(&owner).await, ["after-repair"]);

    assert_eq!(
        relay
            .publish(&owner, "before-repair", 45, 6, Some("device-grant"))
            .await,
        Err("invalid: stale replacement".to_owned()),
        "an old-installation lease signed before the re-pair cannot reclaim the endpoint"
    );
    assert_eq!(relay.active(&owner).await, ["after-repair"]);

    let other = Keys::generate();
    let _ = relay
        .publish(&other, "other-device", 20, 1, Some("device-grant"))
        .await;
    assert_eq!(
        relay.active(&owner).await,
        ["after-repair"],
        "another author cannot retire this author's lease"
    );

    relay
        .publish(&owner, "after-repair", 10, 2, None)
        .await
        .expect("revoke the replacement");
    assert_eq!(
        relay
            .publish(&owner, "before-repair", 45, 6, Some("device-grant"))
            .await,
        Err("invalid: stale replacement".to_owned()),
        "revocation does not revive the replaced lease"
    );
    assert!(relay.active(&owner).await.is_empty());
}
