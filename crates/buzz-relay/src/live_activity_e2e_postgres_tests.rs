use std::sync::{atomic::AtomicBool, Mutex};

use buzz_push_gateway::{
    apns::{DeliveryAttempt, DeliveryOutcome, PushTransport},
    app_attest::AppAttestVerifier,
    authority::{Delegation, MemoryAuthorityStore, NewInstallation, SealedToken},
    grant::{GrantKey, GrantKeyring},
    http::ProfileRuntime,
    live_activity::{bound_origin_hash, LiveActivityAttempt, LiveActivityTransport},
    model::{AppProfile, EndpointGrant},
    token::{TokenKey, TokenKeyring},
};
use nostr::{Event, EventBuilder, Keys, Kind, Tag, Timestamp};
use serde_json::{json, Value};
use sqlx::PgPool;

use super::*;

const APP_ID: &str = "TEAMID.xyz.block.buzz.dogfood.mobile";
const OWNER_START: [u8; 8] = [0xa1; 8];
const OWNER_UPDATE: [u8; 8] = [0xb2; 8];
const MEMBER_START: [u8; 8] = [0xc3; 8];

fn real_now() -> i64 {
    Utc::now().timestamp()
}

#[derive(Default)]
struct RecordingTransport {
    sends: Mutex<Vec<(String, Value, u8)>>,
}

#[async_trait::async_trait]
impl LiveActivityTransport for RecordingTransport {
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
        DeliveryOutcome::Accepted
    }
}

impl RecordingTransport {
    fn sends(&self) -> Vec<(String, Value, u8)> {
        self.sends.lock().unwrap().clone()
    }
}

struct NoAlerts;

#[async_trait::async_trait]
impl PushTransport for NoAlerts {
    async fn send(&self, _: DeliveryAttempt, _: &str) -> DeliveryOutcome {
        panic!("live activity deliveries never send alert pushes")
    }
}

struct Gateway {
    url: url::Url,
    state: buzz_push_gateway::AppState,
    transport: Arc<RecordingTransport>,
}

impl Gateway {
    async fn start() -> Self {
        let authority = Arc::new(MemoryAuthorityStore::default());
        let transport = Arc::new(RecordingTransport::default());
        let live_activity: Arc<dyn LiveActivityTransport> = transport.clone();
        let state = buzz_push_gateway::AppState {
            grant_keyring: Arc::new(
                GrantKeyring::new(vec![GrantKey::new("test", &[1; 32]).unwrap()]).unwrap(),
            ),
            authority,
            token_keyring: Arc::new(
                TokenKeyring::new(vec![TokenKey::new("test", &[2; 32]).unwrap()]).unwrap(),
            ),
            profile: Arc::new(ProfileRuntime {
                app_attest: Arc::new(
                    AppAttestVerifier::new(
                        APP_ID.into(),
                        include_bytes!(
                            "../../buzz-push-gateway/tests/fixtures/apple-app-attestation-root.pem"
                        )
                        .to_vec(),
                    )
                    .unwrap(),
                ),
                transport: Arc::new(NoAlerts),
                live_activity: Some(live_activity),
            }),
            max_grant_lifetime_seconds: 3600,
            max_installation_lifetime_seconds: 3600,
            endpoint_quota_window_seconds: 60,
            endpoint_quota_max_deliveries: 100,
            live_activity_quota_window_seconds: 60,
            live_activity_quota_max_deliveries: 100,
            now: real_now,
            accepting: Arc::new(AtomicBool::new(true)),
        };
        let (app, _) = buzz_push_gateway::router(state.clone());
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let address = listener.local_addr().unwrap();
        tokio::spawn(async move { axum::serve(listener, app).await.unwrap() });
        Self {
            url: format!("http://{address}/v1/deliveries/live-activity")
                .parse()
                .unwrap(),
            state,
            transport,
        }
    }

    fn sealed(&self, token: &[u8]) -> SealedToken {
        SealedToken {
            ciphertext: self.state.token_keyring.seal(token).unwrap(),
            fingerprint: Sha256::digest(token).into(),
        }
    }

    async fn installation(&self, relay: &Keys, start: &[u8], origin: &str) -> (Uuid, String) {
        let now = real_now();
        let installation = Uuid::new_v4();
        let authority = &self.state.authority;
        authority
            .create_installation(
                NewInstallation {
                    id: installation,
                    app_attest_key_id: installation.as_bytes().repeat(2),
                    app_attest_public_key: vec![4; 65],
                    assertion_counter: 0,
                    profile: AppProfile::BuzzIosDogfood,
                    token_ciphertext: self
                        .state
                        .token_keyring
                        .seal(installation.as_bytes())
                        .unwrap(),
                    token_fingerprint: Sha256::digest(installation.as_bytes()).into(),
                    endpoint_epoch: 1,
                    expires_at: now + 3600,
                },
                now,
            )
            .await
            .unwrap();
        let delegation = Uuid::new_v4();
        authority
            .upsert_delegation(Delegation {
                id: delegation,
                installation_id: installation,
                relay_pubkey: relay.public_key().to_hex(),
                endpoint_epoch: 1,
                generation: 1,
                not_before: now,
                expires_at: now + 3600,
                revoked: false,
            })
            .await
            .unwrap();
        authority
            .replace_live_activity_registration(
                installation,
                Some(self.sealed(start)),
                vec![bound_origin_hash(origin, &relay.public_key().to_hex()).unwrap()],
                now,
            )
            .await
            .unwrap();
        let grant = self
            .state
            .grant_keyring
            .issue(&EndpointGrant {
                v: 1,
                delegation_id: delegation,
                relay_pubkey: relay.public_key().to_hex(),
                app_profile: AppProfile::BuzzIosDogfood,
                endpoint_epoch: 1,
                generation: 1,
                expires_at: now + 3600,
            })
            .unwrap();
        (installation, grant)
    }

    async fn register_update_token(
        &self,
        relay: &Keys,
        installation: Uuid,
        origin: &str,
        token: &[u8],
    ) {
        self.state
            .authority
            .set_live_activity_update_token(
                installation,
                bound_origin_hash(origin, &relay.public_key().to_hex()).unwrap(),
                Some(self.sealed(token)),
                real_now(),
            )
            .await
            .unwrap();
    }
}

struct Relay {
    state: Arc<AppState>,
    pool: PgPool,
    community: CommunityId,
    origin: String,
    channel: Uuid,
    channel_name: String,
}

impl Relay {
    async fn start() -> Self {
        let pool = PgPool::connect(&crate::test_support::database_url())
            .await
            .expect("connect test database");
        if std::env::var("BUZZ_TEST_SCHEMA_MODE").as_deref() != Ok("desired") {
            buzz_db::migration::run_migrations(&pool)
                .await
                .expect("run migrations");
        }
        let mut config = crate::config::Config::for_test();
        config.require_relay_membership = false;
        config.redis_url = "redis://127.0.0.1:1".to_owned();
        config.read_database_url = None;
        config.relay_url = "wss://relay.test".to_owned();
        let state = crate::state::tests::build_test_state(config, pool.clone()).await;
        state
            .db
            .ensure_future_partitions(1, true)
            .await
            .expect("ensure partitions");
        let id = Uuid::new_v4();
        let host = format!("la-e2e-{}.test", id.simple());
        sqlx::query("INSERT INTO communities (id, host) VALUES ($1, $2)")
            .bind(id)
            .bind(&host)
            .execute(&pool)
            .await
            .expect("insert community");
        let channel = Uuid::new_v4();
        let channel_name = format!("tasks-{}", &channel.simple().to_string()[..8]);
        sqlx::query(
            "INSERT INTO channels (community_id, id, name, visibility, channel_type, created_by) \
             VALUES ($1, $2, $3, 'open'::channel_visibility, 'stream', $4)",
        )
        .bind(id)
        .bind(channel)
        .bind(&channel_name)
        .bind(vec![0_u8; 32])
        .execute(&pool)
        .await
        .expect("insert channel");
        Self {
            state,
            pool,
            community: CommunityId::from_uuid(id),
            origin: format!("https://{host}"),
            channel,
            channel_name,
        }
    }

    async fn join(&self, keys: &Keys, role: Option<&str>, display_name: Option<&str>) {
        let pool = &self.pool;
        let community = self.community.as_uuid();
        sqlx::query(
            "INSERT INTO channel_members (community_id, channel_id, pubkey) VALUES ($1, $2, $3)",
        )
        .bind(community)
        .bind(self.channel)
        .bind(keys.public_key().to_bytes().as_slice())
        .execute(pool)
        .await
        .expect("insert channel member");
        if let Some(role) = role {
            sqlx::query(
                "INSERT INTO relay_members (community_id, pubkey, role) VALUES ($1, $2, $3)",
            )
            .bind(community)
            .bind(keys.public_key().to_hex())
            .bind(role)
            .execute(pool)
            .await
            .expect("insert relay member");
        }
        if let Some(name) = display_name {
            sqlx::query(
                "INSERT INTO users (community_id, pubkey, display_name) VALUES ($1, $2, $3)",
            )
            .bind(community)
            .bind(keys.public_key().to_bytes().as_slice())
            .bind(name)
            .execute(pool)
            .await
            .expect("insert user");
        }
    }

    async fn lease(&self, keys: &Keys, installation: &str, grant: &str) {
        sqlx::query(
            "INSERT INTO push_leases (community_id, author, installation_id, source_event_id, \
                 source_created_at, generation, active, app_profile, endpoint_hash, \
                 endpoint_grant, max_class, subscriptions, expires_at) \
             VALUES ($1, $2, $3, $4, 1, 1, true, 'buzz-ios-dogfood', $5, $6, 'default', \
                 '[]'::jsonb, EXTRACT(EPOCH FROM now())::bigint + 3000)",
        )
        .bind(self.community.as_uuid())
        .bind(keys.public_key().to_bytes().as_slice())
        .bind(installation)
        .bind(Sha256::digest(installation.as_bytes()).as_slice())
        .bind(Sha256::digest(grant.as_bytes()).as_slice())
        .bind(grant)
        .execute(&self.pool)
        .await
        .expect("insert lease");
    }

    async fn publish(&self, builder: EventBuilder, author: &Keys) -> Event {
        let event = builder.sign_with_keys(author).expect("sign event");
        self.state
            .db
            .insert_event(self.community, &event, Some(self.channel))
            .await
            .expect("insert event");
        event
    }

    async fn message(&self, author: &Keys, content: &str, created_at: i64) -> Event {
        self.publish(
            EventBuilder::new(Kind::Custom(9), content)
                .tag(Tag::parse(["h", &self.channel.to_string()]).unwrap())
                .custom_created_at(Timestamp::from(created_at as u64)),
            author,
        )
        .await
    }

    async fn awaiting_owner(
        &self,
        agent: &Keys,
        root: &Event,
        ask: &str,
        ask_event: &Event,
        created_at: i64,
    ) -> Event {
        let root_id = root.id.to_hex();
        self.publish(
            EventBuilder::new(Kind::Custom(30320), "")
                .tags([
                    Tag::parse(["d", &root_id]).unwrap(),
                    Tag::parse(["h", &self.channel.to_string()]).unwrap(),
                    Tag::parse(["e", &root_id]).unwrap(),
                    Tag::parse(["status", "awaiting_owner"]).unwrap(),
                    Tag::parse(["title", "Task"]).unwrap(),
                    Tag::parse(["ask", ask, &ask_event.id.to_hex()]).unwrap(),
                ])
                .custom_created_at(Timestamp::from(created_at as u64)),
            agent,
        )
        .await
    }

    async fn react(&self, author: &Keys, target: &Event, content: &str) -> Event {
        self.publish(
            EventBuilder::new(Kind::Reaction, content)
                .tag(Tag::parse(["e", &target.id.to_hex()]).unwrap())
                .custom_created_at(Timestamp::from((real_now() - 5) as u64)),
            author,
        )
        .await
    }

    async fn queued(&self) -> bool {
        sqlx::query_scalar(
            "SELECT EXISTS (SELECT 1 FROM push_live_activity_queue WHERE community_id = $1)",
        )
        .bind(self.community.as_uuid())
        .fetch_one(&self.pool)
        .await
        .expect("read queue")
    }

    async fn run_job(&self, gateway: &HttpLiveActivityGateway) {
        assert!(self.queued().await, "trigger must queue the community");
        sqlx::query(
            "UPDATE push_live_activity_queue SET due_at = CASE WHEN community_id = $1 \
                 THEN now() - interval '1 second' ELSE now() + interval '1 day' END \
             WHERE state = 'pending'",
        )
        .bind(self.community.as_uuid())
        .execute(&self.pool)
        .await
        .expect("isolate due job");
        let job = self
            .state
            .db
            .claim_due_live_activity_job(Utc::now() + TimeDelta::seconds(30))
            .await
            .expect("claim")
            .expect("claimed job");
        assert_eq!(job.community, self.community);
        process_job(&self.state, gateway, job).await;
        assert!(!self.queued().await, "job must complete without a retry");
    }

    async fn state_row(&self, author: &Keys) -> LiveActivityStateRow {
        let author = author.public_key().to_bytes().to_vec();
        let rows = self
            .state
            .db
            .live_activity_states(self.community)
            .await
            .expect("states");
        assert!(rows.iter().all(|row| row.author == author));
        rows.into_iter()
            .find(|row| row.author == author)
            .expect("owner state row")
    }
}

fn content_state(
    ask_event: &Event,
    case_id: Option<&str>,
    ask: &str,
    channel: &str,
    open_count: u16,
    asked_at: i64,
) -> Value {
    let mut state = json!({
        "askEventID": ask_event.id.to_hex(),
        "ask": ask,
        "agent": "Zeus",
        "channel": channel,
        "openCount": open_count,
        "askedAt": asked_at,
    });
    if let Some(case_id) = case_id {
        state["caseID"] = json!(case_id);
    }
    state
}

#[tokio::test]
#[ignore = "requires Postgres"]
async fn relay_drives_gateway_card_through_asks_and_decisions() {
    let gateway = Gateway::start().await;
    let relay = Relay::start().await;
    let owner = Keys::generate();
    let member = Keys::generate();
    let agent = Keys::generate();
    relay.join(&owner, Some("owner"), None).await;
    relay.join(&member, Some("member"), None).await;
    relay.join(&agent, None, Some("Zeus")).await;

    let relay_keys = relay.state.relay_keypair.clone();
    let (owner_installation, owner_grant) = gateway
        .installation(&relay_keys, &OWNER_START, &relay.origin)
        .await;
    let (_, member_grant) = gateway
        .installation(&relay_keys, &MEMBER_START, &relay.origin)
        .await;
    relay.lease(&owner, "owner-phone", &owner_grant).await;
    relay.lease(&member, "member-phone", &member_grant).await;
    let client = HttpLiveActivityGateway::new(
        reqwest::Client::builder()
            .timeout(Duration::from_secs(5))
            .build()
            .unwrap(),
        gateway.url.clone(),
        relay_keys,
    );

    let now = real_now();
    let root_one = relay.message(&agent, "Release 1.2", now - 120).await;
    let ask_one = relay
        .message(&agent, "BUZZ-42 · awaiting owner\nShip 1.2?", now - 110)
        .await;
    relay
        .awaiting_owner(&agent, &root_one, "Ship 1.2?", &ask_one, now - 100)
        .await;
    relay.run_job(&client).await;

    let sends = gateway.transport.sends();
    assert_eq!(sends.len(), 1);
    let (token, start, priority) = &sends[0];
    assert_eq!(token, &hex::encode(OWNER_START));
    assert_eq!(*priority, 10);
    let aps = &start["aps"];
    assert_eq!(aps["event"], "start");
    assert_eq!(aps["attributes-type"], "BuzzApprovalsActivityAttributes");
    assert_eq!(aps["attributes"], json!({ "origin": relay.origin }));
    assert_eq!(aps["input-push-token"], 1);
    assert_eq!(
        aps["alert"],
        json!({ "title": "Needs you", "body": "Ship 1.2?" })
    );
    assert_eq!(
        aps["content-state"],
        content_state(
            &ask_one,
            Some("BUZZ-42"),
            "Ship 1.2?",
            &relay.channel_name,
            1,
            now - 100
        )
    );
    let started = relay.state_row(&owner).await;
    assert_eq!(started.result, "started");
    assert_eq!(started.installation_id, "owner-phone");
    assert!(started.started_at.is_some());

    gateway
        .register_update_token(
            &relay.state.relay_keypair,
            owner_installation,
            &relay.origin,
            &OWNER_UPDATE,
        )
        .await;
    let root_two = relay.message(&agent, "Rotate keys", now - 90).await;
    let ask_two = relay
        .message(&agent, "Rotate the signing key?", now - 80)
        .await;
    relay
        .awaiting_owner(
            &agent,
            &root_two,
            "Rotate the signing key?",
            &ask_two,
            now - 70,
        )
        .await;
    relay.run_job(&client).await;

    let sends = gateway.transport.sends();
    assert_eq!(sends.len(), 2);
    let (token, update, priority) = &sends[1];
    assert_eq!(token, &hex::encode(OWNER_UPDATE));
    assert_eq!(*priority, 10);
    assert_eq!(update["aps"]["event"], "update");
    assert_eq!(
        update["aps"]["content-state"],
        content_state(
            &ask_two,
            None,
            "Rotate the signing key?",
            &relay.channel_name,
            2,
            now - 70
        )
    );
    let updated = relay.state_row(&owner).await;
    assert_eq!(updated.result, "updated");
    assert_eq!(updated.started_at, started.started_at);
    assert_eq!(updated.open_count, 2);

    relay.react(&member, &ask_two, "✅").await;
    relay.run_job(&client).await;
    assert_eq!(gateway.transport.sends().len(), 2);
    assert_eq!(relay.state_row(&owner).await, updated);

    relay.react(&owner, &ask_two, "✅").await;
    relay.run_job(&client).await;
    let sends = gateway.transport.sends();
    assert_eq!(sends.len(), 3);
    let (token, update, priority) = &sends[2];
    assert_eq!(token, &hex::encode(OWNER_UPDATE));
    assert_eq!(*priority, 10);
    assert_eq!(update["aps"]["event"], "update");
    assert_eq!(
        update["aps"]["content-state"],
        content_state(
            &ask_one,
            Some("BUZZ-42"),
            "Ship 1.2?",
            &relay.channel_name,
            1,
            now - 100
        )
    );

    relay.react(&owner, &ask_one, "❌").await;
    relay.run_job(&client).await;
    let sends = gateway.transport.sends();
    assert_eq!(sends.len(), 4);
    let (token, end, priority) = &sends[3];
    assert_eq!(token, &hex::encode(OWNER_UPDATE));
    assert_eq!(*priority, 10);
    let aps = &end["aps"];
    assert_eq!(aps["event"], "end");
    assert_eq!(aps["dismissal-date"], aps["timestamp"]);
    assert_eq!(aps["content-state"]["openCount"], 0);
    assert_eq!(aps["content-state"]["askEventID"], "");
    let ended = relay.state_row(&owner).await;
    assert_eq!(ended.result, "ended");
    assert_eq!(ended.open_count, 0);
    assert!(ended.ask_event_id.is_none());

    let target = gateway
        .state
        .authority
        .live_activity_target(
            owner_installation,
            bound_origin_hash(
                &relay.origin,
                &relay.state.relay_keypair.public_key().to_hex(),
            )
            .unwrap(),
            real_now(),
        )
        .await
        .unwrap()
        .expect("start registration stays");
    assert!(target.update_ciphertext.is_none());
    assert!(gateway
        .transport
        .sends()
        .iter()
        .all(|(token, _, _)| token != &hex::encode(MEMBER_START)));
}

#[tokio::test]
#[ignore = "requires Postgres"]
async fn new_ask_after_the_start_bound_replaces_a_card_that_may_be_cleared() {
    let gateway = Gateway::start().await;
    let relay = Relay::start().await;
    let owner = Keys::generate();
    let agent = Keys::generate();
    relay.join(&owner, Some("owner"), None).await;
    relay.join(&agent, None, Some("Zeus")).await;
    let relay_keys = relay.state.relay_keypair.clone();
    let (installation, grant) = gateway
        .installation(&relay_keys, &OWNER_START, &relay.origin)
        .await;
    relay.lease(&owner, "owner-phone", &grant).await;
    let client = HttpLiveActivityGateway::new(
        reqwest::Client::builder()
            .timeout(Duration::from_secs(5))
            .build()
            .unwrap(),
        gateway.url.clone(),
        relay_keys.clone(),
    );
    let hash = bound_origin_hash(&relay.origin, &relay_keys.public_key().to_hex()).unwrap();
    let now = real_now();
    let ask = |name: &'static str, at: i64| {
        let relay = &relay;
        let agent = &agent;
        async move {
            let root = relay.message(agent, name, at - 20).await;
            let ask = relay.message(agent, name, at - 10).await;
            relay.awaiting_owner(agent, &root, name, &ask, at).await;
            ask
        }
    };

    ask("First?", now - 100).await;
    relay.run_job(&client).await;
    gateway
        .register_update_token(&relay_keys, installation, &relay.origin, &OWNER_UPDATE)
        .await;
    let aged = now - NEW_ASK_RESTART_AFTER_SECS - 60;
    gateway
        .state
        .authority
        .record_live_activity_start(installation, hash, aged)
        .await
        .unwrap();
    gateway
        .register_update_token(&relay_keys, installation, &relay.origin, &OWNER_UPDATE)
        .await;
    sqlx::query("UPDATE push_live_activity_state SET started_at = $2 WHERE community_id = $1")
        .bind(relay.community.as_uuid())
        .bind(aged)
        .execute(&relay.pool)
        .await
        .unwrap();

    let second = ask("Second?", now - 50).await;
    relay.run_job(&client).await;
    let sends = gateway.transport.sends();
    let events: Vec<(String, String)> = sends
        .iter()
        .map(|(token, body, _)| {
            (
                token.clone(),
                body["aps"]["event"].as_str().unwrap().to_owned(),
            )
        })
        .collect();
    assert_eq!(
        events[1..],
        [
            (hex::encode(OWNER_UPDATE), "end".to_owned()),
            (hex::encode(OWNER_START), "start".to_owned()),
        ]
    );
    let start = &sends[2].1["aps"];
    assert_eq!(start["content-state"]["askEventID"], second.id.to_hex());
    assert_eq!(start["content-state"]["openCount"], 2);
    let restarted = relay.state_row(&owner).await;
    assert_eq!(restarted.result, "started");
    assert!(restarted.started_at.is_some_and(|started| started >= now));

    gateway
        .register_update_token(&relay_keys, installation, &relay.origin, &OWNER_UPDATE)
        .await;
    ask("Third?", now - 20).await;
    relay.run_job(&client).await;
    let sends = gateway.transport.sends();
    assert_eq!(sends.len(), 4);
    assert_eq!(sends[3].0, hex::encode(OWNER_UPDATE));
    assert_eq!(sends[3].1["aps"]["event"], "update");
    assert_eq!(sends[3].1["aps"]["content-state"]["openCount"], 3);
}
