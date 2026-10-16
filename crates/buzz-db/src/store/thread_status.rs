use buzz_core::kind::KIND_THREAD_STATUS;
use buzz_core::{CommunityId, StoredEvent};
use chrono::{DateTime, Utc};
use uuid::Uuid;

use crate::{error::Result, event::row_to_stored_event, Db};

const EVENT_COLUMNS: &str =
    "id, pubkey, created_at, kind, tags, content, sig, received_at, channel_id";

fn stored(rows: Vec<sqlx::postgres::PgRow>) -> Result<Vec<StoredEvent>> {
    rows.into_iter()
        .filter_map(|row| row_to_stored_event(row).transpose())
        .collect()
}

impl Db {
    /// Current thread status event of each root; newest wins, then the lower ID.
    pub async fn latest_thread_statuses(
        &self,
        community_id: CommunityId,
        channel_id: Uuid,
        root_ids: &[String],
    ) -> Result<Vec<StoredEvent>> {
        if root_ids.is_empty() {
            return Ok(Vec::new());
        }
        let mut connection = crate::observability::acquire_writer(
            &self.pool,
            crate::observability::WriterOperation::SubscriptionHistory,
        )
        .await?;
        let sql = format!(
            "SELECT DISTINCT ON (d_tag) {EVENT_COLUMNS} FROM events \
             WHERE community_id = $1 AND channel_id = $2 AND kind = $3 AND d_tag = ANY($4) \
             AND deleted_at IS NULL ORDER BY d_tag, created_at DESC, id ASC"
        );
        let rows = sqlx::query(sqlx::AssertSqlSafe(sql))
            .bind(community_id.as_uuid())
            .bind(channel_id)
            .bind(KIND_THREAD_STATUS as i32)
            .bind(root_ids)
            .fetch_all(&mut *connection)
            .await?;
        stored(rows)
    }

    /// Current statuses of all open tasks plus the newest done tasks.
    pub async fn channel_task_statuses(
        &self,
        community_id: CommunityId,
        channel_id: Uuid,
        done_limit: i64,
    ) -> Result<Vec<StoredEvent>> {
        let mut connection = crate::observability::acquire_writer(
            &self.pool,
            crate::observability::WriterOperation::SubscriptionHistory,
        )
        .await?;
        let sql = format!(
            "WITH latest AS (SELECT DISTINCT ON (d_tag) {EVENT_COLUMNS}, \
             tags @> '[[\"status\",\"done\"]]'::jsonb AS done FROM events \
             WHERE community_id = $1 AND channel_id = $2 AND kind = $3 AND deleted_at IS NULL \
             ORDER BY d_tag, created_at DESC, id ASC) \
             (SELECT {EVENT_COLUMNS} FROM latest WHERE NOT done) UNION ALL \
             (SELECT {EVENT_COLUMNS} FROM latest WHERE done ORDER BY created_at DESC, id ASC LIMIT $4)"
        );
        let rows = sqlx::query(sqlx::AssertSqlSafe(sql))
            .bind(community_id.as_uuid())
            .bind(channel_id)
            .bind(KIND_THREAD_STATUS as i32)
            .bind(done_limit)
            .fetch_all(&mut *connection)
            .await?;
        stored(rows)
    }

    /// Live channel messages with an attachment or a link, newest first.
    pub async fn channel_files_and_links(
        &self,
        community_id: CommunityId,
        channel_id: Uuid,
        kinds: &[i32],
        until: Option<DateTime<Utc>>,
        limit: i64,
    ) -> Result<Vec<StoredEvent>> {
        let mut connection = crate::observability::acquire_writer(
            &self.pool,
            crate::observability::WriterOperation::SubscriptionHistory,
        )
        .await?;
        let sql = format!(
            "SELECT {EVENT_COLUMNS} FROM events WHERE community_id = $1 AND channel_id = $2 \
             AND kind = ANY($3) AND deleted_at IS NULL \
             AND ($4::timestamptz IS NULL OR created_at <= $4) \
             AND (tags @> '[[\"imeta\"]]'::jsonb OR content ~* 'https?://') \
             ORDER BY created_at DESC, id ASC LIMIT $5"
        );
        let rows = sqlx::query(sqlx::AssertSqlSafe(sql))
            .bind(community_id.as_uuid())
            .bind(channel_id)
            .bind(kinds)
            .bind(until)
            .bind(limit)
            .fetch_all(&mut *connection)
            .await?;
        stored(rows)
    }
}
