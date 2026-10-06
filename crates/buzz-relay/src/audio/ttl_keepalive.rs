//! Keeps ephemeral huddle channels alive while their audio rooms hold peers.

use std::sync::Arc;
use std::time::Duration;

use tracing::error;

use crate::state::AppState;

/// Refresh period: one sixth of the huddle channel TTL.
pub fn interval(ephemeral_ttl_override: Option<i32>) -> Duration {
    let ttl = crate::handlers::ingest::expected_huddle_backing_ttl(ephemeral_ttl_override);
    Duration::from_secs((u64::from(ttl.unsigned_abs()) / 6).max(1))
}

/// Extend the TTL of every channel whose local audio room holds peers.
pub async fn refresh_occupied_rooms(state: &AppState) {
    for (community_id, channel_id) in state.audio_rooms.occupied_channels() {
        if let Err(e) = state.db.refresh_channel_ttl(community_id, channel_id).await {
            error!(channel_id = %channel_id, "huddle TTL keepalive failed: {e}");
        }
    }
}

/// Run [`refresh_occupied_rooms`] for the life of the relay.
pub async fn run(state: Arc<AppState>) {
    let mut ticker = tokio::time::interval(interval(state.config.ephemeral_ttl_override));
    ticker.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
    loop {
        ticker.tick().await;
        refresh_occupied_rooms(&state).await;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn interval_is_a_sixth_of_the_huddle_ttl() {
        assert_eq!(interval(None), Duration::from_secs(600));
        assert_eq!(interval(Some(60)), Duration::from_secs(10));
        assert_eq!(interval(Some(1)), Duration::from_secs(1));
    }

    #[tokio::test]
    #[ignore = "requires Postgres"]
    async fn refreshes_only_channels_whose_rooms_hold_peers() {
        let pool = sqlx::PgPool::connect(&crate::test_support::database_url())
            .await
            .expect("connect test Postgres");
        let state = crate::state::tests::test_state_with_database_pool(pool.clone()).await;
        let community = buzz_core::CommunityId::from_uuid(uuid::Uuid::new_v4());
        sqlx::query("INSERT INTO communities (id, host) VALUES ($1, $2)")
            .bind(community.as_uuid())
            .bind(format!(
                "ttl-keepalive-{}.example",
                community.as_uuid().simple()
            ))
            .execute(&pool)
            .await
            .expect("seed community");
        let creator = nostr::Keys::generate().public_key().to_bytes().to_vec();
        let (occupied, empty) = (uuid::Uuid::new_v4(), uuid::Uuid::new_v4());
        for channel in [occupied, empty] {
            sqlx::query(
                "INSERT INTO channels \
                 (id, community_id, name, channel_type, visibility, created_by, ttl_seconds, ttl_deadline) \
                 VALUES ($1, $2, $3, 'stream', 'private', $4, 3600, NOW() - interval '1 second')",
            )
            .bind(channel)
            .bind(community.as_uuid())
            .bind(format!("huddle-{}", channel.simple()))
            .bind(&creator)
            .execute(&pool)
            .await
            .expect("seed ephemeral channel");
        }
        state
            .audio_rooms
            .get_or_create(community, occupied)
            .add_peer("a".repeat(64), 2)
            .expect("admit peer");
        state.audio_rooms.get_or_create(community, empty);

        refresh_occupied_rooms(&state).await;

        let deadline = |channel| {
            let pool = pool.clone();
            async move {
                sqlx::query_scalar::<_, chrono::DateTime<chrono::Utc>>(
                    "SELECT ttl_deadline FROM channels WHERE community_id = $1 AND id = $2",
                )
                .bind(community.as_uuid())
                .bind(channel)
                .fetch_one(&pool)
                .await
                .expect("load deadline")
            }
        };
        let now = chrono::Utc::now();
        assert!(deadline(occupied).await > now + chrono::Duration::seconds(3500));
        assert!(deadline(empty).await < now);
    }
}
