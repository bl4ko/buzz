use std::time::Duration;

use buzz_core::CommunityId;
use chrono::{DateTime, Utc};
use sqlx::{PgPool, Row as _};
use uuid::Uuid;

use crate::error::Result;
use crate::Db;

const REFRESH_AFTER_SECS: i64 = 90 * 60;
const RESTART_AFTER_SECS: i64 = 7 * 60 * 60;

/// One claimed community job from the Live Activity queue.
#[derive(Debug, Clone)]
pub struct ClaimedLiveActivityJob {
    /// Community whose ask state must be recomputed.
    pub community: CommunityId,
    /// Fencing token for complete and retry.
    pub claim_id: Uuid,
    /// Attempt number, starting at one for the first claim.
    pub attempts: i32,
    /// Whether the refresh sweep marked this job.
    pub refresh: bool,
}

/// Open approval asks of one community owner.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct OwnerAskSummary {
    /// Owner raw public key.
    pub owner: Vec<u8>,
    /// Number of undecided asks for this owner.
    pub open_count: i64,
    /// Kind 30320 event ID of the shown ask.
    pub status_event_id: Vec<u8>,
    /// Kind 30320 `created_at` of the shown ask, in Unix seconds.
    pub status_created_at: i64,
    /// Kind 30320 author raw public key.
    pub status_author: Vec<u8>,
    /// Channel of the shown ask.
    pub channel_id: Uuid,
    /// Text of the `ask` tag.
    pub ask_text: String,
    /// Ask event ID from the `ask` tag.
    pub ask_event_id: Vec<u8>,
    /// Content of the ask event.
    pub ask_content: String,
}

/// Last Live Activity delivery result for one owner lease.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LiveActivityStateRow {
    /// Lease author raw public key.
    pub author: Vec<u8>,
    /// Lease installation ID.
    pub installation_id: String,
    /// Lease generation used for the delivery.
    pub lease_generation: i64,
    /// Ask event ID shown on the card, if any.
    pub ask_event_id: Option<Vec<u8>>,
    /// Open ask count shown on the card.
    pub open_count: i32,
    /// SHA-256 of the delivered card content.
    pub content_hash: Vec<u8>,
    /// Gateway result: started, updated, ended, pending, or not_registered.
    pub result: String,
    /// Unix seconds of the last card start.
    pub started_at: Option<i64>,
    /// Unix seconds of the last delivery.
    pub last_sent_at: i64,
}

/// Active push lease of a community owner, with its delivery grant.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LiveActivityLease {
    /// Lease author raw public key.
    pub author: Vec<u8>,
    /// Lease installation ID.
    pub installation_id: String,
    /// Lease generation.
    pub generation: i64,
    /// Opaque gateway endpoint grant.
    pub endpoint_grant: String,
    /// Lease expiry in Unix seconds.
    pub expires_at: i64,
}

async fn maintenance_connection(
    pool: &PgPool,
) -> Result<sqlx::pool::PoolConnection<sqlx::Postgres>> {
    Ok(crate::observability::acquire_writer(
        pool,
        crate::observability::WriterOperation::Maintenance,
    )
    .await?)
}

async fn claim_due_job(
    pool: &PgPool,
    lease_until: DateTime<Utc>,
) -> Result<Option<ClaimedLiveActivityJob>> {
    let claim_id = Uuid::new_v4();
    let mut connection = maintenance_connection(pool).await?;
    let row = sqlx::query(
        "WITH target AS ( \
             SELECT community_id, refresh FROM push_live_activity_queue \
             WHERE ((state = 'pending' AND due_at <= now()) \
                 OR (state = 'running' AND lease_until < now())) \
               AND community_write_allowed(community_id) \
             ORDER BY due_at \
             FOR UPDATE SKIP LOCKED \
             LIMIT 1 \
         ) \
         UPDATE push_live_activity_queue q \
         SET state = 'running', claim_id = $1, lease_until = $2, attempts = q.attempts + 1, \
             dirty = false, refresh = false \
         FROM target t WHERE q.community_id = t.community_id \
         RETURNING q.community_id, q.attempts, t.refresh",
    )
    .bind(claim_id)
    .bind(lease_until)
    .fetch_optional(&mut *connection)
    .await?;
    row.map(|row| {
        Ok(ClaimedLiveActivityJob {
            community: CommunityId::from_uuid(row.try_get("community_id")?),
            claim_id,
            attempts: row.try_get("attempts")?,
            refresh: row.try_get("refresh")?,
        })
    })
    .transpose()
}

async fn complete_job(pool: &PgPool, community: CommunityId, claim_id: Uuid) -> Result<()> {
    let mut connection = maintenance_connection(pool).await?;
    sqlx::query(
        "UPDATE push_live_activity_queue \
         SET state = 'pending', due_at = now() + interval '1 second', attempts = 0, \
             claim_id = NULL, lease_until = NULL, dirty = false \
         WHERE community_id = $1 AND claim_id = $2 AND state = 'running' AND dirty",
    )
    .bind(community.as_uuid())
    .bind(claim_id)
    .execute(&mut *connection)
    .await?;
    sqlx::query(
        "DELETE FROM push_live_activity_queue \
         WHERE community_id = $1 AND claim_id = $2 AND state = 'running' AND NOT dirty",
    )
    .bind(community.as_uuid())
    .bind(claim_id)
    .execute(&mut *connection)
    .await?;
    Ok(())
}

async fn retry_job(
    pool: &PgPool,
    community: CommunityId,
    claim_id: Uuid,
    delay: Duration,
) -> Result<()> {
    let mut connection = maintenance_connection(pool).await?;
    sqlx::query(
        "UPDATE push_live_activity_queue \
         SET state = 'pending', \
             due_at = CASE WHEN dirty THEN now() + interval '1 second' \
                 ELSE now() + make_interval(secs => $3) END, \
             claim_id = NULL, lease_until = NULL, dirty = false \
         WHERE community_id = $1 AND claim_id = $2 AND state = 'running'",
    )
    .bind(community.as_uuid())
    .bind(claim_id)
    .bind(delay.as_secs_f64())
    .execute(&mut *connection)
    .await?;
    Ok(())
}

async fn mark_refresh_due(pool: &PgPool, now: i64) -> Result<u64> {
    let mut connection = maintenance_connection(pool).await?;
    Ok(sqlx::query(
        "INSERT INTO push_live_activity_queue (community_id, due_at, refresh) \
         SELECT DISTINCT community_id, now(), true FROM push_live_activity_state \
         WHERE open_count > 0 AND result IN ('started', 'updated', 'pending') \
           AND (last_sent_at < $1 - $2 OR started_at < $1 - $3) \
           AND community_write_allowed(community_id) \
         ON CONFLICT (community_id) DO UPDATE \
         SET refresh = true, \
             dirty = push_live_activity_queue.dirty OR push_live_activity_queue.state = 'running'",
    )
    .bind(now)
    .bind(REFRESH_AFTER_SECS)
    .bind(RESTART_AFTER_SECS)
    .execute(&mut *connection)
    .await?
    .rows_affected())
}

async fn owner_asks(
    pool: &PgPool,
    community: CommunityId,
    owners: &[Vec<u8>],
) -> Result<Vec<OwnerAskSummary>> {
    if owners.is_empty() {
        return Ok(Vec::new());
    }
    let mut connection = maintenance_connection(pool).await?;
    let rows = sqlx::query(
        "WITH latest AS ( \
             SELECT DISTINCT ON (channel_id, d_tag) id, pubkey, created_at, channel_id, tags \
             FROM events \
             WHERE community_id = $1 AND kind = 30320 AND deleted_at IS NULL \
               AND d_tag IS NOT NULL AND channel_id IS NOT NULL \
             ORDER BY channel_id, d_tag, created_at DESC, id ASC \
         ), \
         asks AS ( \
             SELECT l.id, l.pubkey, l.created_at, l.channel_id, a.tag ->> 1 AS ask_text, \
                 CASE WHEN a.tag ->> 2 ~ '^[0-9a-f]{64}$' THEN decode(a.tag ->> 2, 'hex') END \
                     AS ask_event_id \
             FROM latest l \
             CROSS JOIN LATERAL ( \
                 SELECT t AS tag FROM jsonb_array_elements(l.tags) t \
                 WHERE t ->> 0 = 'ask' LIMIT 1 \
             ) a \
             WHERE l.tags @> '[[\"status\",\"awaiting_owner\"]]'::jsonb \
               AND a.tag ->> 1 <> '' \
         ), \
         open AS ( \
             SELECT o.owner, a.id, a.pubkey, a.created_at, a.channel_id, a.ask_text, \
                 a.ask_event_id, e.content AS ask_content \
             FROM unnest($2::bytea[]) AS o(owner) \
             CROSS JOIN asks a \
             JOIN events e ON e.community_id = $1 AND e.id = a.ask_event_id \
                 AND e.deleted_at IS NULL \
             WHERE EXISTS ( \
                 SELECT 1 FROM channel_members cm \
                 JOIN channels c ON c.community_id = cm.community_id AND c.id = cm.channel_id \
                     AND c.deleted_at IS NULL \
                 WHERE cm.community_id = $1 AND cm.channel_id = a.channel_id \
                   AND cm.pubkey = o.owner AND cm.removed_at IS NULL \
             ) \
             AND NOT EXISTS ( \
                 SELECT 1 FROM events r \
                 WHERE r.community_id = $1 AND r.kind = 7 AND r.pubkey = o.owner \
                   AND r.deleted_at IS NULL AND r.content IN ('✅', '❌') \
                   AND r.tags @> jsonb_build_array(jsonb_build_array('e', encode(a.ask_event_id, 'hex'))) \
             ) \
         ) \
         SELECT DISTINCT ON (owner) owner, count(*) OVER (PARTITION BY owner) AS open_count, \
             id, pubkey, EXTRACT(EPOCH FROM created_at)::bigint AS created_at, channel_id, \
             ask_text, ask_event_id, ask_content \
         FROM open \
         ORDER BY owner, created_at DESC, id ASC",
    )
    .bind(community.as_uuid())
    .bind(owners)
    .fetch_all(&mut *connection)
    .await?;
    rows.into_iter()
        .map(|row| {
            Ok(OwnerAskSummary {
                owner: row.try_get("owner")?,
                open_count: row.try_get("open_count")?,
                status_event_id: row.try_get("id")?,
                status_created_at: row.try_get("created_at")?,
                status_author: row.try_get("pubkey")?,
                channel_id: row.try_get("channel_id")?,
                ask_text: row.try_get("ask_text")?,
                ask_event_id: row.try_get("ask_event_id")?,
                ask_content: row.try_get("ask_content")?,
            })
        })
        .collect()
}

async fn owner_leases(
    pool: &PgPool,
    community: CommunityId,
    owners: &[Vec<u8>],
) -> Result<Vec<LiveActivityLease>> {
    if owners.is_empty() {
        return Ok(Vec::new());
    }
    let mut connection = maintenance_connection(pool).await?;
    let rows = sqlx::query(
        "SELECT author, installation_id, generation, endpoint_grant, expires_at \
         FROM push_leases WHERE community_id = $1 AND author = ANY($2) \
           AND active AND endpoint_enabled \
           AND expires_at > EXTRACT(EPOCH FROM now())::bigint \
         ORDER BY author, installation_id",
    )
    .bind(community.as_uuid())
    .bind(owners)
    .fetch_all(&mut *connection)
    .await?;
    rows.into_iter()
        .map(|row| {
            Ok(LiveActivityLease {
                author: row.try_get("author")?,
                installation_id: row.try_get("installation_id")?,
                generation: row.try_get("generation")?,
                endpoint_grant: row.try_get("endpoint_grant")?,
                expires_at: row.try_get("expires_at")?,
            })
        })
        .collect()
}

async fn states(pool: &PgPool, community: CommunityId) -> Result<Vec<LiveActivityStateRow>> {
    let mut connection = maintenance_connection(pool).await?;
    let rows = sqlx::query(
        "SELECT author, installation_id, lease_generation, ask_event_id, open_count, \
             content_hash, result, started_at, last_sent_at \
         FROM push_live_activity_state WHERE community_id = $1 \
         ORDER BY author, installation_id",
    )
    .bind(community.as_uuid())
    .fetch_all(&mut *connection)
    .await?;
    rows.into_iter()
        .map(|row| {
            Ok(LiveActivityStateRow {
                author: row.try_get("author")?,
                installation_id: row.try_get("installation_id")?,
                lease_generation: row.try_get("lease_generation")?,
                ask_event_id: row.try_get("ask_event_id")?,
                open_count: row.try_get("open_count")?,
                content_hash: row.try_get("content_hash")?,
                result: row.try_get("result")?,
                started_at: row.try_get("started_at")?,
                last_sent_at: row.try_get("last_sent_at")?,
            })
        })
        .collect()
}

async fn record_result(
    pool: &PgPool,
    community: CommunityId,
    row: &LiveActivityStateRow,
) -> Result<()> {
    let mut connection = maintenance_connection(pool).await?;
    sqlx::query(
        "INSERT INTO push_live_activity_state (community_id, author, installation_id, \
             lease_generation, ask_event_id, open_count, content_hash, result, started_at, \
             last_sent_at, attempts, next_attempt_at) \
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, 0, now()) \
         ON CONFLICT (community_id, author, installation_id) DO UPDATE \
         SET lease_generation = EXCLUDED.lease_generation, ask_event_id = EXCLUDED.ask_event_id, \
             open_count = EXCLUDED.open_count, content_hash = EXCLUDED.content_hash, \
             result = EXCLUDED.result, started_at = EXCLUDED.started_at, \
             last_sent_at = EXCLUDED.last_sent_at, \
             attempts = push_live_activity_state.attempts + 1, next_attempt_at = now()",
    )
    .bind(community.as_uuid())
    .bind(&row.author)
    .bind(&row.installation_id)
    .bind(row.lease_generation)
    .bind(&row.ask_event_id)
    .bind(row.open_count)
    .bind(&row.content_hash)
    .bind(&row.result)
    .bind(row.started_at)
    .bind(row.last_sent_at)
    .execute(&mut *connection)
    .await?;
    Ok(())
}

impl Db {
    /// Claim the next due Live Activity community job.
    pub async fn claim_due_live_activity_job(
        &self,
        until: DateTime<Utc>,
    ) -> Result<Option<ClaimedLiveActivityJob>> {
        claim_due_job(&self.pool, until).await
    }

    /// Finish a claimed job; requeue it when it became dirty while running.
    pub async fn complete_live_activity_job(
        &self,
        community: CommunityId,
        claim_id: Uuid,
    ) -> Result<()> {
        complete_job(&self.pool, community, claim_id).await
    }

    /// Release a claimed job for another attempt after `delay`.
    pub async fn retry_live_activity_job(
        &self,
        community: CommunityId,
        claim_id: Uuid,
        delay: Duration,
    ) -> Result<()> {
        retry_job(&self.pool, community, claim_id, delay).await
    }

    /// Queue refresh jobs for open cards that are old or near their age limit.
    pub async fn mark_live_activity_refresh_due(&self, now: i64) -> Result<u64> {
        mark_refresh_due(&self.pool, now).await
    }

    /// Undecided approval asks per owner, one row per owner with asks.
    pub async fn owner_ask_summaries(
        &self,
        community: CommunityId,
        owners: &[Vec<u8>],
    ) -> Result<Vec<OwnerAskSummary>> {
        owner_asks(&self.pool, community, owners).await
    }

    /// Active endpoint-enabled push leases of the given owners.
    pub async fn live_activity_leases(
        &self,
        community: CommunityId,
        owners: &[Vec<u8>],
    ) -> Result<Vec<LiveActivityLease>> {
        owner_leases(&self.pool, community, owners).await
    }

    /// Stored Live Activity results of one community.
    pub async fn live_activity_states(
        &self,
        community: CommunityId,
    ) -> Result<Vec<LiveActivityStateRow>> {
        states(&self.pool, community).await
    }

    /// Store the Live Activity result of one owner lease.
    pub async fn record_live_activity_result(
        &self,
        community: CommunityId,
        row: &LiveActivityStateRow,
    ) -> Result<()> {
        record_result(&self.pool, community, row).await
    }
}
