use std::time::Duration;

use buzz_core::CommunityId;
use chrono::{TimeDelta, Utc};
use nostr::{Event, EventBuilder, Keys, Kind, Tag, Timestamp};
use sqlx::PgPool;
use uuid::Uuid;

use super::live_activity::{LiveActivityStateRow, OwnerAskSummary};
use crate::Db;

static CLAIM_LOCK: tokio::sync::Mutex<()> = tokio::sync::Mutex::const_new(());

async fn db() -> Db {
    let pool = PgPool::connect(&crate::test_support::database_url())
        .await
        .expect("connect test database");
    if std::env::var("BUZZ_TEST_SCHEMA_MODE").as_deref() != Ok("desired") {
        crate::migration::run_migrations(&pool)
            .await
            .expect("run migrations");
    }
    let db = Db::from_pool(pool);
    db.ensure_future_partitions(1, true)
        .await
        .expect("ensure partitions");
    db
}

async fn community(db: &Db) -> CommunityId {
    let id = Uuid::new_v4();
    sqlx::query("INSERT INTO communities (id, host) VALUES ($1, $2)")
        .bind(id)
        .bind(format!("la-{}.test", id.simple()))
        .execute(&db.pool)
        .await
        .expect("insert community");
    CommunityId::from_uuid(id)
}

async fn channel(db: &Db, community: CommunityId, members: &[&Keys]) -> Uuid {
    let id = Uuid::new_v4();
    sqlx::query(
        "INSERT INTO channels (community_id, id, name, visibility, channel_type, created_by) \
         VALUES ($1, $2, $3, 'open'::channel_visibility, 'stream', $4)",
    )
    .bind(community.as_uuid())
    .bind(id)
    .bind(format!("ch-{}", id.simple()))
    .bind(vec![0_u8; 32])
    .execute(&db.pool)
    .await
    .expect("insert channel");
    for member in members {
        sqlx::query(
            "INSERT INTO channel_members (community_id, channel_id, pubkey) VALUES ($1, $2, $3)",
        )
        .bind(community.as_uuid())
        .bind(id)
        .bind(member.public_key().to_bytes().as_slice())
        .execute(&db.pool)
        .await
        .expect("insert member");
    }
    id
}

fn now_secs() -> u64 {
    Utc::now().timestamp() as u64
}

async fn store(db: &Db, community: CommunityId, channel: Option<Uuid>, event: &Event) {
    db.insert_event(community, event, channel)
        .await
        .expect("insert event");
}

async fn message(
    db: &Db,
    community: CommunityId,
    channel: Uuid,
    author: &Keys,
    content: &str,
) -> Event {
    let event = EventBuilder::new(Kind::Custom(9), content)
        .tag(Tag::parse(["h", &channel.to_string()]).expect("h tag"))
        .custom_created_at(Timestamp::from(now_secs() - 60))
        .sign_with_keys(author)
        .expect("sign message");
    store(db, community, Some(channel), &event).await;
    event
}

#[allow(clippy::too_many_arguments)]
async fn status(
    db: &Db,
    community: CommunityId,
    channel: Uuid,
    author: &Keys,
    root: &Event,
    value: &str,
    ask: Option<(&str, &Event)>,
    created_at: u64,
) -> Event {
    let root_id = root.id.to_hex();
    let mut tags = vec![
        Tag::parse(["d", &root_id]).expect("d tag"),
        Tag::parse(["h", &channel.to_string()]).expect("h tag"),
        Tag::parse(["e", &root_id]).expect("e tag"),
        Tag::parse(["status", value]).expect("status tag"),
        Tag::parse(["title", "Task"]).expect("title tag"),
    ];
    if let Some((text, event)) = ask {
        tags.push(Tag::parse(["ask", text, &event.id.to_hex()]).expect("ask tag"));
    }
    let event = EventBuilder::new(Kind::Custom(30320), "")
        .tags(tags)
        .custom_created_at(Timestamp::from(created_at))
        .sign_with_keys(author)
        .expect("sign status");
    store(db, community, Some(channel), &event).await;
    event
}

async fn reaction(
    db: &Db,
    community: CommunityId,
    channel: Uuid,
    author: &Keys,
    target: &Event,
    content: &str,
) -> Event {
    let event = EventBuilder::new(Kind::Reaction, content)
        .tag(Tag::parse(["e", &target.id.to_hex()]).expect("e tag"))
        .custom_created_at(Timestamp::from(now_secs() - 5))
        .sign_with_keys(author)
        .expect("sign reaction");
    store(db, community, Some(channel), &event).await;
    event
}

async fn soft_delete(db: &Db, community: CommunityId, event: &Event) {
    sqlx::query("UPDATE events SET deleted_at = now() WHERE community_id = $1 AND id = $2")
        .bind(community.as_uuid())
        .bind(event.id.as_bytes().as_slice())
        .execute(&db.pool)
        .await
        .expect("soft delete");
}

async fn queue_rows(db: &Db, community: CommunityId) -> Vec<(String, bool, bool)> {
    sqlx::query_as(
        "SELECT state, dirty, refresh FROM push_live_activity_queue WHERE community_id = $1",
    )
    .bind(community.as_uuid())
    .fetch_all(&db.pool)
    .await
    .expect("read queue")
}

async fn clear_queue(db: &Db, community: CommunityId) {
    sqlx::query("DELETE FROM push_live_activity_queue WHERE community_id = $1")
        .bind(community.as_uuid())
        .execute(&db.pool)
        .await
        .expect("clear queue");
}

async fn claim_only(
    db: &Db,
    community: CommunityId,
) -> super::live_activity::ClaimedLiveActivityJob {
    sqlx::query(
        "UPDATE push_live_activity_queue SET due_at = CASE WHEN community_id = $1 \
             THEN now() - interval '1 second' ELSE now() + interval '1 day' END \
         WHERE state = 'pending'",
    )
    .bind(community.as_uuid())
    .execute(&db.pool)
    .await
    .expect("isolate due job");
    sqlx::query(
        "UPDATE push_live_activity_queue SET lease_until = now() + interval '1 day' \
         WHERE state = 'running' AND community_id <> $1",
    )
    .bind(community.as_uuid())
    .execute(&db.pool)
    .await
    .expect("park stale running jobs");
    let job = db
        .claim_due_live_activity_job(Utc::now() + TimeDelta::seconds(30))
        .await
        .expect("claim")
        .expect("claimed job");
    assert_eq!(job.community, community);
    job
}

async fn summaries(db: &Db, community: CommunityId, owners: &[&Keys]) -> Vec<OwnerAskSummary> {
    let owners: Vec<Vec<u8>> = owners
        .iter()
        .map(|keys| keys.public_key().to_bytes().to_vec())
        .collect();
    db.owner_ask_summaries(community, &owners)
        .await
        .expect("owner ask summaries")
}

#[tokio::test]
#[ignore = "requires Postgres"]
async fn kind_30320_insert_enqueues_community() {
    let db = db().await;
    let community = community(&db).await;
    let owner = Keys::generate();
    let agent = Keys::generate();
    let channel = channel(&db, community, &[&owner, &agent]).await;
    let root = message(&db, community, channel, &agent, "root").await;
    assert!(queue_rows(&db, community).await.is_empty());
    status(
        &db,
        community,
        channel,
        &agent,
        &root,
        "open",
        None,
        now_secs() - 30,
    )
    .await;
    assert_eq!(
        queue_rows(&db, community).await,
        vec![("pending".to_owned(), false, false)]
    );
    let due_in_future: bool = sqlx::query_scalar(
        "SELECT due_at > now() FROM push_live_activity_queue WHERE community_id = $1",
    )
    .bind(community.as_uuid())
    .fetch_one(&db.pool)
    .await
    .expect("read due");
    assert!(due_in_future);
}

#[tokio::test]
#[ignore = "requires Postgres"]
async fn owner_check_reaction_enqueues_but_thumbs_up_does_not() {
    let db = db().await;
    let community = community(&db).await;
    let owner = Keys::generate();
    let channel = channel(&db, community, &[&owner]).await;
    let target = message(&db, community, channel, &owner, "ask").await;
    reaction(&db, community, channel, &owner, &target, "👍").await;
    assert!(queue_rows(&db, community).await.is_empty());
    reaction(&db, community, channel, &owner, &target, "❌").await;
    assert_eq!(queue_rows(&db, community).await.len(), 1);
    clear_queue(&db, community).await;
    reaction(&db, community, channel, &owner, &target, "✅").await;
    assert_eq!(queue_rows(&db, community).await.len(), 1);
}

#[tokio::test]
#[ignore = "requires Postgres"]
async fn reaction_soft_delete_enqueues() {
    let db = db().await;
    let community = community(&db).await;
    let owner = Keys::generate();
    let channel = channel(&db, community, &[&owner]).await;
    let target = message(&db, community, channel, &owner, "ask").await;
    let approve = reaction(&db, community, channel, &owner, &target, "✅").await;
    clear_queue(&db, community).await;
    soft_delete(&db, community, &approve).await;
    assert_eq!(queue_rows(&db, community).await.len(), 1);
    clear_queue(&db, community).await;
    sqlx::query("UPDATE events SET content = content WHERE community_id = $1 AND id = $2")
        .bind(community.as_uuid())
        .bind(approve.id.as_bytes().as_slice())
        .execute(&db.pool)
        .await
        .expect("touch row");
    assert!(queue_rows(&db, community).await.is_empty());
}

#[tokio::test]
#[ignore = "requires Postgres"]
async fn burst_coalesces_to_one_row() {
    let db = db().await;
    let community = community(&db).await;
    let owner = Keys::generate();
    let agent = Keys::generate();
    let channel = channel(&db, community, &[&owner, &agent]).await;
    let root = message(&db, community, channel, &agent, "root").await;
    for offset in 0..5 {
        status(
            &db,
            community,
            channel,
            &agent,
            &root,
            "open",
            None,
            now_secs() - 50 + offset,
        )
        .await;
        reaction(&db, community, channel, &owner, &root, "✅").await;
    }
    assert_eq!(queue_rows(&db, community).await.len(), 1);
}

#[tokio::test]
#[ignore = "requires Postgres"]
async fn dirty_while_running_requeues_on_complete() {
    let _guard = CLAIM_LOCK.lock().await;
    let db = db().await;
    let community = community(&db).await;
    let owner = Keys::generate();
    let channel = channel(&db, community, &[&owner]).await;
    let target = message(&db, community, channel, &owner, "ask").await;
    reaction(&db, community, channel, &owner, &target, "✅").await;

    let job = claim_only(&db, community).await;
    assert_eq!(job.attempts, 1);
    assert!(!job.refresh);
    assert_eq!(
        queue_rows(&db, community).await,
        vec![("running".to_owned(), false, false)]
    );
    reaction(&db, community, channel, &owner, &target, "❌").await;
    assert_eq!(
        queue_rows(&db, community).await,
        vec![("running".to_owned(), true, false)]
    );
    db.complete_live_activity_job(community, job.claim_id)
        .await
        .expect("complete");
    assert_eq!(
        queue_rows(&db, community).await,
        vec![("pending".to_owned(), false, false)]
    );

    let job = claim_only(&db, community).await;
    assert_eq!(job.attempts, 1);
    db.complete_live_activity_job(community, Uuid::new_v4())
        .await
        .expect("stale complete");
    assert_eq!(queue_rows(&db, community).await.len(), 1);
    db.retry_live_activity_job(community, job.claim_id, Duration::from_secs(15), false)
        .await
        .expect("retry");
    let delay: f64 = sqlx::query_scalar(
        "SELECT EXTRACT(EPOCH FROM due_at - now())::float8 FROM push_live_activity_queue \
         WHERE community_id = $1 AND state = 'pending'",
    )
    .bind(community.as_uuid())
    .fetch_one(&db.pool)
    .await
    .expect("read retry due");
    assert!((10.0..=16.0).contains(&delay), "retry delay {delay}");

    let job = claim_only(&db, community).await;
    assert_eq!(job.attempts, 2);
    db.complete_live_activity_job(community, job.claim_id)
        .await
        .expect("complete");
    assert!(queue_rows(&db, community).await.is_empty());
}

async fn queue_job(db: &Db, community: CommunityId, refresh: bool) {
    sqlx::query(
        "INSERT INTO push_live_activity_queue (community_id, due_at, refresh) \
         VALUES ($1, now(), $2)",
    )
    .bind(community.as_uuid())
    .bind(refresh)
    .execute(&db.pool)
    .await
    .expect("queue job");
}

#[tokio::test]
#[ignore = "requires Postgres"]
async fn complete_requeues_when_marked_dirty_concurrently() {
    let _guard = CLAIM_LOCK.lock().await;
    let db = db().await;
    let community = community(&db).await;
    queue_job(&db, community, false).await;
    let job = claim_only(&db, community).await;

    let mut marker = db.pool.begin().await.expect("begin marker");
    sqlx::query(
        "INSERT INTO push_live_activity_queue (community_id, due_at) \
         VALUES ($1, now() + interval '1 second') \
         ON CONFLICT (community_id) DO UPDATE \
         SET dirty = push_live_activity_queue.dirty OR push_live_activity_queue.state = 'running'",
    )
    .bind(community.as_uuid())
    .execute(&mut *marker)
    .await
    .expect("mark dirty");
    let completing = tokio::spawn({
        let db = db.clone();
        async move { db.complete_live_activity_job(community, job.claim_id).await }
    });
    tokio::time::sleep(Duration::from_millis(300)).await;
    marker.commit().await.expect("commit marker");
    completing.await.expect("join complete").expect("complete");
    assert_eq!(
        queue_rows(&db, community).await,
        vec![("pending".to_owned(), false, false)]
    );
}

#[tokio::test]
#[ignore = "requires Postgres"]
async fn retry_keeps_the_refresh_flag() {
    let _guard = CLAIM_LOCK.lock().await;
    let db = db().await;
    let community = community(&db).await;
    queue_job(&db, community, true).await;
    let job = claim_only(&db, community).await;
    assert!(job.refresh);
    db.retry_live_activity_job(community, job.claim_id, Duration::ZERO, job.refresh)
        .await
        .expect("retry");
    assert_eq!(
        queue_rows(&db, community).await,
        vec![("pending".to_owned(), false, true)]
    );
    let job = claim_only(&db, community).await;
    assert!(job.refresh);
    assert_eq!(job.attempts, 2);
    db.retry_live_activity_job(community, job.claim_id, Duration::ZERO, false)
        .await
        .expect("retry");
    let job = claim_only(&db, community).await;
    assert!(!job.refresh);
    db.complete_live_activity_job(community, job.claim_id)
        .await
        .expect("complete");
    assert!(queue_rows(&db, community).await.is_empty());
}

async fn lease(db: &Db, community: CommunityId, author: &Keys, installation: &str) {
    let source: [u8; 32] = rand::random();
    sqlx::query(
        "INSERT INTO push_leases (community_id, author, installation_id, source_event_id, \
             source_created_at, generation, active, app_profile, endpoint_hash, endpoint_grant, \
             max_class, subscriptions, expires_at) \
         VALUES ($1, $2, $3, $4, 1, 1, true, 'buzz-ios-dogfood', $5, 'grant', 'default', \
             '[]'::jsonb, EXTRACT(EPOCH FROM now())::bigint + 86400)",
    )
    .bind(community.as_uuid())
    .bind(author.public_key().to_bytes().as_slice())
    .bind(installation)
    .bind(source.as_slice())
    .bind(rand::random::<[u8; 32]>().as_slice())
    .execute(&db.pool)
    .await
    .expect("insert lease");
}

fn state_row(
    author: &Keys,
    installation: &str,
    open_count: i32,
    result: &str,
    started_at: Option<i64>,
    last_sent_at: i64,
) -> LiveActivityStateRow {
    LiveActivityStateRow {
        author: author.public_key().to_bytes().to_vec(),
        installation_id: installation.to_owned(),
        lease_generation: 1,
        ask_event_id: (open_count > 0).then(|| vec![7; 32]),
        open_count,
        content_hash: vec![1; 32],
        result: result.to_owned(),
        started_at,
        last_sent_at,
    }
}

#[tokio::test]
#[ignore = "requires Postgres"]
async fn refresh_sweep_marks_old_and_aged_rows() {
    let _guard = CLAIM_LOCK.lock().await;
    let db = db().await;
    let now = Utc::now().timestamp();
    let owner = Keys::generate();
    let cases = [
        (1, "updated", Some(now - 600), now - 5_500, true, true),
        (1, "started", Some(now - 25_300), now - 60, true, true),
        (1, "pending", Some(now - 600), now - 5_500, true, true),
        (1, "updated", Some(now - 600), now - 60, true, false),
        (0, "ended", None, now - 9_000, true, false),
        (1, "not_registered", None, now - 9_000, true, false),
        (1, "not_registered", None, now - 21_700, true, true),
        (1, "updated", Some(now - 600), now - 5_500, false, false),
        (1, "not_registered", None, now - 21_700, false, false),
    ];
    let mut communities = Vec::new();
    for (open_count, result, started_at, last_sent_at, enabled, expected) in cases {
        let community = community(&db).await;
        lease(&db, community, &owner, "install").await;
        sqlx::query("UPDATE push_leases SET endpoint_enabled = $2 WHERE community_id = $1")
            .bind(community.as_uuid())
            .bind(enabled)
            .execute(&db.pool)
            .await
            .expect("set endpoint state");
        let row = state_row(
            &owner,
            "install",
            open_count,
            result,
            started_at,
            last_sent_at,
        );
        db.record_live_activity_result(community, &row)
            .await
            .expect("record result");
        assert_eq!(
            db.live_activity_states(community).await.expect("states"),
            vec![row]
        );
        communities.push((community, expected));
    }
    let marked = db.mark_live_activity_refresh_due(now).await.expect("sweep");
    assert!(marked >= 4);
    for (community, expected) in communities {
        let rows = queue_rows(&db, community).await;
        if expected {
            assert_eq!(rows, vec![("pending".to_owned(), false, true)]);
        } else {
            assert!(rows.is_empty(), "unexpected refresh for {community}");
        }
    }
}

struct AskFixture {
    db: Db,
    community: CommunityId,
    channel: Uuid,
    owner: Keys,
    agent: Keys,
}

impl AskFixture {
    async fn new() -> Self {
        let db = db().await;
        let community = community(&db).await;
        let owner = Keys::generate();
        let agent = Keys::generate();
        let channel = channel(&db, community, &[&owner, &agent]).await;
        Self {
            db,
            community,
            channel,
            owner,
            agent,
        }
    }

    async fn ask(&self, author: &Keys, text: &str, created_at: u64) -> (Event, Event) {
        self.ask_in(self.channel, author, text, created_at).await
    }

    async fn ask_in(
        &self,
        channel: Uuid,
        author: &Keys,
        text: &str,
        created_at: u64,
    ) -> (Event, Event) {
        let root = message(
            &self.db,
            self.community,
            channel,
            author,
            &format!("{text} root"),
        )
        .await;
        let ask = message(
            &self.db,
            self.community,
            channel,
            author,
            &format!("{text} body"),
        )
        .await;
        let status = status(
            &self.db,
            self.community,
            channel,
            author,
            &root,
            "awaiting_owner",
            Some((text, &ask)),
            created_at,
        )
        .await;
        (status, ask)
    }

    async fn summaries(&self) -> Vec<OwnerAskSummary> {
        summaries(&self.db, self.community, &[&self.owner]).await
    }
}

#[tokio::test]
#[ignore = "requires Postgres"]
async fn newest_awaiting_status_wins_across_authors() {
    let f = AskFixture::new().await;
    let other = Keys::generate();
    sqlx::query(
        "INSERT INTO channel_members (community_id, channel_id, pubkey) VALUES ($1, $2, $3)",
    )
    .bind(f.community.as_uuid())
    .bind(f.channel)
    .bind(other.public_key().to_bytes().as_slice())
    .execute(&f.db.pool)
    .await
    .expect("add member");
    let now = now_secs();
    let root = message(&f.db, f.community, f.channel, &f.agent, "root").await;
    let first_ask = message(&f.db, f.community, f.channel, &f.agent, "first").await;
    let second_ask = message(&f.db, f.community, f.channel, &other, "second").await;
    status(
        &f.db,
        f.community,
        f.channel,
        &f.agent,
        &root,
        "awaiting_owner",
        Some(("First?", &first_ask)),
        now - 20,
    )
    .await;
    let newer = status(
        &f.db,
        f.community,
        f.channel,
        &other,
        &root,
        "awaiting_owner",
        Some(("Second?", &second_ask)),
        now - 10,
    )
    .await;

    let rows = f.summaries().await;
    assert_eq!(rows.len(), 1);
    let row = &rows[0];
    assert_eq!(row.owner, f.owner.public_key().to_bytes().to_vec());
    assert_eq!(row.open_count, 1);
    assert_eq!(row.status_event_id, newer.id.as_bytes().to_vec());
    assert_eq!(row.status_created_at, (now - 10) as i64);
    assert_eq!(row.status_author, other.public_key().to_bytes().to_vec());
    assert_eq!(row.channel_id, f.channel);
    assert_eq!(row.ask_text, "Second?");
    assert_eq!(row.ask_event_id, second_ask.id.as_bytes().to_vec());
    assert_eq!(row.ask_content, "second");
}

#[tokio::test]
#[ignore = "requires Postgres"]
async fn same_second_tie_prefers_lower_status_id() {
    let f = AskFixture::new().await;
    let other = Keys::generate();
    let now = now_secs() - 10;
    let root = message(&f.db, f.community, f.channel, &f.agent, "root").await;
    let a_ask = message(&f.db, f.community, f.channel, &f.agent, "a").await;
    let b_ask = message(&f.db, f.community, f.channel, &other, "b").await;
    let a = status(
        &f.db,
        f.community,
        f.channel,
        &f.agent,
        &root,
        "awaiting_owner",
        Some(("A?", &a_ask)),
        now,
    )
    .await;
    let b = status(
        &f.db,
        f.community,
        f.channel,
        &other,
        &root,
        "awaiting_owner",
        Some(("B?", &b_ask)),
        now,
    )
    .await;
    let winner = if a.id.as_bytes() < b.id.as_bytes() {
        &a
    } else {
        &b
    };

    let rows = f.summaries().await;
    assert_eq!(rows.len(), 1);
    assert_eq!(rows[0].open_count, 1);
    assert_eq!(rows[0].status_event_id, winner.id.as_bytes().to_vec());
}

#[tokio::test]
#[ignore = "requires Postgres"]
async fn owner_approve_and_deny_both_decide() {
    let f = AskFixture::new().await;
    let now = now_secs();
    let (_, first) = f.ask(&f.agent, "First?", now - 30).await;
    let (_, second) = f.ask(&f.agent, "Second?", now - 20).await;
    assert_eq!(f.summaries().await[0].open_count, 2);
    reaction(&f.db, f.community, f.channel, &f.owner, &first, "✅").await;
    let rows = f.summaries().await;
    assert_eq!(rows[0].open_count, 1);
    assert_eq!(rows[0].ask_event_id, second.id.as_bytes().to_vec());
    reaction(&f.db, f.community, f.channel, &f.owner, &second, "❌").await;
    assert!(f.summaries().await.is_empty());
}

#[tokio::test]
#[ignore = "requires Postgres"]
async fn non_owner_reaction_does_not_decide() {
    let f = AskFixture::new().await;
    let (_, ask) = f.ask(&f.agent, "Ship?", now_secs() - 20).await;
    reaction(&f.db, f.community, f.channel, &f.agent, &ask, "✅").await;
    reaction(&f.db, f.community, f.channel, &f.owner, &ask, "👍").await;
    let rows = f.summaries().await;
    assert_eq!(rows.len(), 1);
    assert_eq!(rows[0].open_count, 1);
}

#[tokio::test]
#[ignore = "requires Postgres"]
async fn deleted_owner_reaction_reopens_ask() {
    let f = AskFixture::new().await;
    let (_, ask) = f.ask(&f.agent, "Ship?", now_secs() - 20).await;
    let approve = reaction(&f.db, f.community, f.channel, &f.owner, &ask, "✅").await;
    assert!(f.summaries().await.is_empty());
    soft_delete(&f.db, f.community, &approve).await;
    assert_eq!(f.summaries().await[0].open_count, 1);
}

#[tokio::test]
#[ignore = "requires Postgres"]
async fn done_status_removes_ask() {
    let f = AskFixture::new().await;
    let now = now_secs();
    let root = message(&f.db, f.community, f.channel, &f.agent, "root").await;
    let ask = message(&f.db, f.community, f.channel, &f.agent, "ask").await;
    status(
        &f.db,
        f.community,
        f.channel,
        &f.agent,
        &root,
        "awaiting_owner",
        Some(("Ship?", &ask)),
        now - 20,
    )
    .await;
    assert_eq!(f.summaries().await.len(), 1);
    status(
        &f.db,
        f.community,
        f.channel,
        &f.agent,
        &root,
        "done",
        None,
        now - 10,
    )
    .await;
    assert!(f.summaries().await.is_empty());
}

#[tokio::test]
#[ignore = "requires Postgres"]
async fn deleted_ask_event_is_skipped() {
    let f = AskFixture::new().await;
    let now = now_secs();
    let (_, kept) = f.ask(&f.agent, "Kept?", now - 30).await;
    let (_, gone) = f.ask(&f.agent, "Gone?", now - 20).await;
    soft_delete(&f.db, f.community, &gone).await;
    let rows = f.summaries().await;
    assert_eq!(rows[0].open_count, 1);
    assert_eq!(rows[0].ask_event_id, kept.id.as_bytes().to_vec());
}

#[tokio::test]
#[ignore = "requires Postgres"]
async fn owner_not_in_channel_is_skipped() {
    let f = AskFixture::new().await;
    let elsewhere = channel(&f.db, f.community, &[&f.agent]).await;
    let now = now_secs();
    f.ask_in(elsewhere, &f.agent, "Hidden?", now - 20).await;
    assert!(f.summaries().await.is_empty());
    let (_, visible) = f.ask(&f.agent, "Visible?", now - 30).await;
    sqlx::query(
        "UPDATE channel_members SET removed_at = now() \
         WHERE community_id = $1 AND channel_id = $2 AND pubkey = $3",
    )
    .bind(f.community.as_uuid())
    .bind(f.channel)
    .bind(f.owner.public_key().to_bytes().as_slice())
    .execute(&f.db.pool)
    .await
    .expect("remove owner");
    assert!(f.summaries().await.is_empty());
    sqlx::query(
        "UPDATE channel_members SET removed_at = NULL \
         WHERE community_id = $1 AND channel_id = $2 AND pubkey = $3",
    )
    .bind(f.community.as_uuid())
    .bind(f.channel)
    .bind(f.owner.public_key().to_bytes().as_slice())
    .execute(&f.db.pool)
    .await
    .expect("restore owner");
    let rows = f.summaries().await;
    assert_eq!(rows[0].open_count, 1);
    assert_eq!(rows[0].ask_event_id, visible.id.as_bytes().to_vec());
}

#[tokio::test]
#[ignore = "requires Postgres"]
async fn other_community_is_isolated() {
    let f = AskFixture::new().await;
    let g = AskFixture::new().await;
    let (_, mine) = f.ask(&f.agent, "Mine?", now_secs() - 20).await;
    assert!(summaries(&g.db, g.community, &[&f.owner]).await.is_empty());
    let channel_b = channel(&g.db, g.community, &[&f.owner, &f.agent]).await;
    let root = message(&g.db, g.community, channel_b, &f.agent, "root").await;
    let other_ask = message(&f.db, f.community, f.channel, &f.agent, "foreign").await;
    status(
        &g.db,
        g.community,
        channel_b,
        &f.agent,
        &root,
        "awaiting_owner",
        Some(("Foreign?", &other_ask)),
        now_secs() - 10,
    )
    .await;
    assert!(summaries(&g.db, g.community, &[&f.owner]).await.is_empty());
    reaction(&g.db, g.community, channel_b, &f.owner, &mine, "✅").await;
    assert_eq!(f.summaries().await[0].open_count, 1);
}

#[tokio::test]
#[ignore = "requires Postgres"]
async fn count_spans_channels() {
    let f = AskFixture::new().await;
    let second_channel = channel(&f.db, f.community, &[&f.owner, &f.agent]).await;
    let now = now_secs();
    f.ask(&f.agent, "Old?", now - 30).await;
    let (status, ask) = f.ask_in(second_channel, &f.agent, "New?", now - 10).await;
    let rows = f.summaries().await;
    assert_eq!(rows.len(), 1);
    assert_eq!(rows[0].open_count, 2);
    assert_eq!(rows[0].channel_id, second_channel);
    assert_eq!(rows[0].status_event_id, status.id.as_bytes().to_vec());
    assert_eq!(rows[0].ask_event_id, ask.id.as_bytes().to_vec());
    assert_eq!(rows[0].ask_text, "New?");
    assert_eq!(rows[0].ask_content, "New? body");
}

#[tokio::test]
#[ignore = "requires Postgres"]
async fn leases_are_limited_to_active_owner_leases() {
    let db = db().await;
    let community = community(&db).await;
    let owner = Keys::generate();
    let member = Keys::generate();
    lease(&db, community, &owner, "phone").await;
    lease(&db, community, &member, "phone").await;
    let leases = db
        .live_activity_leases(community, &[owner.public_key().to_bytes().to_vec()])
        .await
        .expect("leases");
    assert_eq!(leases.len(), 1);
    assert_eq!(leases[0].author, owner.public_key().to_bytes().to_vec());
    assert_eq!(leases[0].installation_id, "phone");
    assert_eq!(leases[0].endpoint_grant, "grant");
}

async fn la_objects(pool: &PgPool) -> (bool, bool, i64, i64, i64) {
    sqlx::query_as(
        "SELECT to_regclass('push_live_activity_queue') IS NOT NULL, \
             to_regclass('push_live_activity_state') IS NOT NULL, \
             (SELECT count(*) FROM pg_proc WHERE proname = 'enqueue_live_activity_job'), \
             (SELECT count(*) FROM pg_trigger WHERE tgname LIKE 'events_enqueue_live_activity%'), \
             (SELECT count(*) FROM _sqlx_migrations WHERE version = 9001)",
    )
    .fetch_one(pool)
    .await
    .expect("read live activity objects")
}

#[tokio::test]
#[ignore = "requires Postgres"]
async fn rollback_script_removes_9001_and_allows_reapply() {
    let admin_url = crate::test_support::database_url();
    let admin = PgPool::connect(&admin_url).await.expect("connect admin");
    let name = format!("buzz_la_rollback_{}", Uuid::new_v4().simple());
    sqlx::query(sqlx::AssertSqlSafe(format!("CREATE DATABASE {name}")))
        .execute(&admin)
        .await
        .expect("create scratch database");
    let path_start = admin_url.rfind('/').expect("database URL path");
    let pool = PgPool::connect(&format!("{}/{}", &admin_url[..path_start], name))
        .await
        .expect("connect scratch database");
    crate::migration::run_migrations(&pool)
        .await
        .expect("migrate");
    Db::from_pool(pool.clone())
        .ensure_future_partitions(1, true)
        .await
        .expect("partitions");
    let (queue, state, functions, triggers, applied) = la_objects(&pool).await;
    assert!(queue && state);
    assert_eq!((functions, applied), (1, 1));
    assert!(triggers > 2, "partition trigger clones: {triggers}");

    sqlx::raw_sql(include_str!(
        "../../../../migrations/rollback/9001_live_activity.down.sql"
    ))
    .execute(&pool)
    .await
    .expect("rollback script");
    assert_eq!(la_objects(&pool).await, (false, false, 0, 0, 0));
    let newest: i64 = sqlx::query_scalar("SELECT max(version) FROM _sqlx_migrations")
        .fetch_one(&pool)
        .await
        .expect("newest migration");
    assert!(newest < 9001, "{newest}");

    crate::migration::run_migrations(&pool)
        .await
        .expect("re-apply 9001");
    let (queue, state, functions, triggers, applied) = la_objects(&pool).await;
    assert!(queue && state);
    assert_eq!((functions, applied), (1, 1));
    assert!(triggers > 2);

    pool.close().await;
    sqlx::query(sqlx::AssertSqlSafe(format!(
        "DROP DATABASE IF EXISTS {name} WITH (FORCE)"
    )))
    .execute(&admin)
    .await
    .expect("drop scratch database");
    admin.close().await;
}
