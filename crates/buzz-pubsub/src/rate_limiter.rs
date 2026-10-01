//! Redis-backed rate limiter using atomic Lua script (INCR + EXPIRE).
//!
//! Implements the [`RateLimiter`] trait from `buzz-auth`.
//! Uses a single Lua script to atomically INCR and conditionally EXPIRE,
//! eliminating the crash window where a key could exist without a TTL.
//!
//! ⚠️ Fixed windows allow up to 2× burst at boundaries. Upgrade to sliding
//! window or token bucket for strict limiting.

use std::net::IpAddr;

use buzz_auth::{
    error::AuthError,
    rate_limit::{LimitType, RateLimitResult, RateLimiter},
};
use buzz_core::TenantContext;
use nostr::PublicKey;
use redis::Script;

/// Atomically INCR the key, set EXPIRE on first call, and return (count, ttl).
///
/// Using a Lua script ensures INCR and EXPIRE are executed atomically —
/// a crash between them can no longer leave a key without a TTL.
const RATE_LIMIT_SCRIPT: &str = r#"
local count = redis.call('INCR', KEYS[1])
if count == 1 then
    redis.call('EXPIRE', KEYS[1], ARGV[1])
end
local ttl = redis.call('TTL', KEYS[1])
return {count, ttl}
"#;

/// Run the atomic rate-limit Lua script against `key` and return a
/// [`RateLimitResult`].
///
/// If the TTL comes back negative (key exists without expiry — broken state
/// from a prior crash), the key is repaired with a fresh EXPIRE and a warning
/// is logged.
async fn run_rate_limit(
    pool: &deadpool_redis::Pool,
    key: &str,
    window_secs: u64,
    limit: u64,
) -> Result<RateLimitResult, AuthError> {
    let mut retried = false;
    let (mut conn, count, ttl) = loop {
        let mut conn = pool
            .get()
            .await
            .map_err(|e| AuthError::Internal(format!("Redis pool: {e}")))?;

        let script = Script::new(RATE_LIMIT_SCRIPT);
        let result: redis::RedisResult<(u64, i64)> = script
            .key(key)
            .arg(window_secs as i64)
            .invoke_async(&mut *conn)
            .await;
        match result {
            Ok((count, ttl)) => break (conn, count, ttl),
            Err(error) => {
                if error.kind() == redis::ErrorKind::Server(redis::ServerErrorKind::ReadOnly) {
                    drop(deadpool_redis::Connection::take(conn));
                    if !retried {
                        retried = true;
                        continue;
                    }
                }
                return Err(AuthError::Internal(format!(
                    "Redis rate limit script: {error}"
                )));
            }
        }
    };

    // ttl == -1 means the key exists but has no expiry — broken state from a
    // prior crash between INCR and EXPIRE. Repair it now.
    let reset_in_secs = if ttl < 0 {
        tracing::warn!(key = %key, "rate limit key has no TTL — repairing");
        let _: () = redis::cmd("EXPIRE")
            .arg(key)
            .arg(window_secs as i64)
            .query_async(&mut *conn)
            .await
            .map_err(|e| AuthError::Internal(format!("Redis EXPIRE repair: {e}")))?;
        // After repair, the window resets to the full duration.
        window_secs
    } else {
        ttl.max(0) as u64
    };

    if count <= limit {
        Ok(RateLimitResult::allowed(count, limit, reset_in_secs))
    } else {
        Ok(RateLimitResult::denied(count, limit, reset_in_secs))
    }
}

/// Redis-backed rate limiter using fixed-window counters.
///
/// Pubkey keys are community-scoped via `&TenantContext`:
/// `buzz:{community}:ratelimit:{pubkey_hex}:{suffix}`. IP keys remain
/// operator-global: `buzz:ratelimit:ip:{ip}:conn`. The counter and its TTL are
/// managed atomically via a Lua script to prevent keys from persisting without
/// expiry.
pub struct RedisRateLimiter {
    pool: deadpool_redis::Pool,
}

impl RedisRateLimiter {
    /// Create a new `RedisRateLimiter` backed by the given connection pool.
    pub fn new(pool: deadpool_redis::Pool) -> Self {
        Self { pool }
    }
}

impl RateLimiter for RedisRateLimiter {
    async fn check_and_increment(
        &self,
        ctx: &TenantContext,
        pubkey: &PublicKey,
        limit_type: LimitType,
        window_secs: u64,
        limit: u64,
    ) -> Result<RateLimitResult, AuthError> {
        let key = buzz_auth::rate_limit::rate_limit_key(ctx, pubkey, &limit_type);
        run_rate_limit(&self.pool, &key, window_secs, limit).await
    }

    async fn check_ip_connection(
        &self,
        ip: &IpAddr,
        window_secs: u64,
        limit: u64,
    ) -> Result<RateLimitResult, AuthError> {
        let key = buzz_auth::rate_limit::ip_rate_limit_key(ip);
        run_rate_limit(&self.pool, &key, window_secs, limit).await
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    #[ignore = "requires a dedicated Redis instance in BUZZ_TEST_REDIS_URL"]
    async fn readonly_connections_leave_the_pool_and_recover_after_promotion() {
        let url = std::env::var("BUZZ_TEST_REDIS_URL").expect("dedicated Redis URL");
        let mut config = deadpool_redis::Config::from_url(url);
        config.pool = Some(deadpool_redis::PoolConfig::new(1));
        let pool = config
            .create_pool(Some(deadpool_redis::Runtime::Tokio1))
            .unwrap();
        let mut admin = pool.get().await.unwrap().clone();
        let _: () = redis::cmd("REPLICAOF")
            .arg("127.0.0.1")
            .arg(9)
            .query_async(&mut admin)
            .await
            .unwrap();
        let result = run_rate_limit(&pool, "failover-check", 5, 10).await;
        let remaining = pool.status().size;
        let _: () = redis::cmd("REPLICAOF")
            .arg("NO")
            .arg("ONE")
            .query_async(&mut admin)
            .await
            .unwrap();
        assert!(result.is_err());
        assert_eq!(remaining, 0);
        assert!(
            run_rate_limit(&pool, "failover-check", 5, 10)
                .await
                .unwrap()
                .allowed
        );
    }
}
