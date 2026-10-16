use super::*;

const STARTS: &str = "push_gateway_live_activity_starts";
const ACTIVITIES: &str = "push_gateway_live_activities";

fn hashes(origin_hashes: &[[u8; 32]]) -> Vec<Vec<u8>> {
    origin_hashes.iter().map(|hash| hash.to_vec()).collect()
}

async fn registered(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    installation: Uuid,
    origin_hash: [u8; 32],
) -> Result<(), AuthorityError> {
    let found: Option<bool> = sqlx::query_scalar(
        "SELECT $2 = ANY(origin_hashes) FROM push_gateway_live_activity_starts
         WHERE installation_id=$1 FOR UPDATE",
    )
    .bind(installation)
    .bind(origin_hash.to_vec())
    .fetch_optional(&mut **tx)
    .await
    .map_err(db)?;
    found
        .filter(|found| *found)
        .map(|_| ())
        .ok_or(AuthorityError::NotFound)
}

pub(super) async fn replace_registration(
    pool: &PgPool,
    installation: Uuid,
    start: Option<SealedToken>,
    origin_hashes: Vec<[u8; 32]>,
    now: i64,
) -> Result<(), AuthorityError> {
    if !valid_origin_hashes(&origin_hashes) {
        return Err(AuthorityError::Rejected);
    }
    let mut tx = pool.begin().await.map_err(db)?;
    let expires_at: DateTime<Utc> = sqlx::query_scalar(
        "SELECT expires_at FROM push_gateway_installations
         WHERE id=$1 AND revoked_at IS NULL AND expires_at >= $2 FOR UPDATE",
    )
    .bind(installation)
    .bind(at(now)?)
    .fetch_optional(&mut *tx)
    .await
    .map_err(db)?
    .ok_or(AuthorityError::Rejected)?;
    match start {
        Some(token) if !origin_hashes.is_empty() => {
            let origin_hashes = hashes(&origin_hashes);
            sqlx::query(
                "INSERT INTO push_gateway_live_activity_starts
                   (installation_id,token_ciphertext,token_fingerprint,origin_hashes,updated_at,expires_at)
                 VALUES($1,$2,$3,$4,$5,$6)
                 ON CONFLICT(installation_id) DO UPDATE SET
                   token_ciphertext=EXCLUDED.token_ciphertext,
                   token_fingerprint=EXCLUDED.token_fingerprint,
                   origin_hashes=EXCLUDED.origin_hashes,
                   updated_at=EXCLUDED.updated_at,
                   expires_at=EXCLUDED.expires_at",
            )
            .bind(installation)
            .bind(token.ciphertext)
            .bind(token.fingerprint.to_vec())
            .bind(&origin_hashes)
            .bind(at(now)?)
            .bind(expires_at)
            .execute(&mut *tx)
            .await
            .map_err(db)?;
            sqlx::query(
                "DELETE FROM push_gateway_live_activities
                 WHERE installation_id=$1 AND NOT (origin_hash = ANY($2))",
            )
            .bind(installation)
            .bind(&origin_hashes)
            .execute(&mut *tx)
            .await
            .map_err(db)?;
        }
        _ => {
            delete_installation_rows(&mut tx, &[installation]).await?;
        }
    }
    tx.commit().await.map_err(db)
}

pub(super) async fn delete_installation_rows(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    installations: &[Uuid],
) -> Result<(), AuthorityError> {
    sqlx::query("DELETE FROM push_gateway_live_activity_starts WHERE installation_id = ANY($1)")
        .bind(installations)
        .execute(&mut **tx)
        .await
        .map_err(db)?;
    Ok(())
}

pub(super) async fn set_update_token(
    pool: &PgPool,
    installation: Uuid,
    origin_hash: [u8; 32],
    token: Option<SealedToken>,
    now: i64,
) -> Result<(), AuthorityError> {
    let mut tx = pool.begin().await.map_err(db)?;
    registered(&mut tx, installation, origin_hash).await?;
    match token {
        Some(token) => {
            sqlx::query(
                "INSERT INTO push_gateway_live_activities
                   (installation_id,origin_hash,update_token_ciphertext,update_token_fingerprint,started_at,updated_at,expires_at)
                 VALUES($1,$2,$3,$4,NULL,$5,$6)
                 ON CONFLICT(installation_id,origin_hash) DO UPDATE SET
                   update_token_ciphertext=EXCLUDED.update_token_ciphertext,
                   update_token_fingerprint=EXCLUDED.update_token_fingerprint,
                   updated_at=EXCLUDED.updated_at,
                   expires_at=EXCLUDED.expires_at",
            )
            .bind(installation)
            .bind(origin_hash.to_vec())
            .bind(token.ciphertext)
            .bind(token.fingerprint.to_vec())
            .bind(at(now)?)
            .bind(at(now.saturating_add(LIVE_ACTIVITY_UPDATE_RETENTION_SECONDS))?)
            .execute(&mut *tx)
            .await
            .map_err(db)?;
        }
        None => {
            clear_in(&mut tx, installation, origin_hash).await?;
        }
    }
    tx.commit().await.map_err(db)
}

async fn clear_in(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    installation: Uuid,
    origin_hash: [u8; 32],
) -> Result<(), AuthorityError> {
    sqlx::query(
        "DELETE FROM push_gateway_live_activities WHERE installation_id=$1 AND origin_hash=$2",
    )
    .bind(installation)
    .bind(origin_hash.to_vec())
    .execute(&mut **tx)
    .await
    .map_err(db)?;
    Ok(())
}

pub(super) async fn target(
    pool: &PgPool,
    installation: Uuid,
    origin_hash: [u8; 32],
) -> Result<Option<LiveActivityTarget>, AuthorityError> {
    let row = sqlx::query(
        "SELECT s.token_ciphertext, a.update_token_ciphertext, a.started_at
         FROM push_gateway_live_activity_starts s
         LEFT JOIN push_gateway_live_activities a
           ON a.installation_id = s.installation_id AND a.origin_hash = $2
         WHERE s.installation_id = $1 AND $2 = ANY(s.origin_hashes)",
    )
    .bind(installation)
    .bind(origin_hash.to_vec())
    .fetch_optional(pool)
    .await
    .map_err(db)?;
    row.map(|row| {
        Ok(LiveActivityTarget {
            start_ciphertext: row.try_get("token_ciphertext").map_err(db)?,
            update_ciphertext: row.try_get("update_token_ciphertext").map_err(db)?,
            started_at: row
                .try_get::<Option<DateTime<Utc>>, _>("started_at")
                .map_err(db)?
                .map(ts),
        })
    })
    .transpose()
}

pub(super) async fn record_start(
    pool: &PgPool,
    installation: Uuid,
    origin_hash: [u8; 32],
    now: i64,
) -> Result<(), AuthorityError> {
    let mut tx = pool.begin().await.map_err(db)?;
    registered(&mut tx, installation, origin_hash).await?;
    sqlx::query(
        "INSERT INTO push_gateway_live_activities
           (installation_id,origin_hash,update_token_ciphertext,update_token_fingerprint,started_at,updated_at,expires_at)
         VALUES($1,$2,NULL,NULL,$3,$3,$4)
         ON CONFLICT(installation_id,origin_hash) DO UPDATE SET
           update_token_ciphertext=NULL,
           update_token_fingerprint=NULL,
           started_at=EXCLUDED.started_at,
           updated_at=EXCLUDED.updated_at,
           expires_at=EXCLUDED.expires_at",
    )
    .bind(installation)
    .bind(origin_hash.to_vec())
    .bind(at(now)?)
    .bind(at(now.saturating_add(LIVE_ACTIVITY_UPDATE_RETENTION_SECONDS))?)
    .execute(&mut *tx)
    .await
    .map_err(db)?;
    tx.commit().await.map_err(db)
}

pub(super) async fn clear(
    pool: &PgPool,
    installation: Uuid,
    origin_hash: [u8; 32],
) -> Result<(), AuthorityError> {
    let mut tx = pool.begin().await.map_err(db)?;
    clear_in(&mut tx, installation, origin_hash).await?;
    tx.commit().await.map_err(db)
}

pub(super) async fn reap(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    now: i64,
) -> Result<(), AuthorityError> {
    sqlx::query("DELETE FROM push_gateway_live_activities WHERE expires_at < $1")
        .bind(at(now)?)
        .execute(&mut **tx)
        .await
        .map_err(db)?;
    sqlx::query(
        "DELETE FROM push_gateway_live_activity_starts s
         WHERE EXISTS (
             SELECT 1 FROM push_gateway_installations i
             WHERE i.id = s.installation_id AND i.expires_at < $1
         )",
    )
    .bind(at(now)?)
    .execute(&mut **tx)
    .await
    .map_err(db)?;
    Ok(())
}

pub(super) const TABLES: [&str; 2] = [STARTS, ACTIVITIES];
