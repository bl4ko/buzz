use super::postgres_tests::{drop_schema, full_schema, TEST_DB_URL};
use super::*;
use crate::authority::live_activity_conformance as conformance;
use sqlx::{postgres::PgPoolOptions, AssertSqlSafe};

async fn with_store<F, Fut>(run: F)
where
    F: FnOnce(PostgresAuthorityStore) -> Fut,
    Fut: std::future::Future<Output = ()>,
{
    let (pool, schema) = full_schema(2).await;
    run(PostgresAuthorityStore::new(pool.clone())).await;
    pool.close().await;
    drop_schema(&schema).await;
}

#[tokio::test]
#[ignore = "requires PostgreSQL"]
async fn live_activity_registration_replaces_origins() {
    with_store(|store| async move { conformance::registration_replaces_origins(&store).await })
        .await;
}

#[tokio::test]
#[ignore = "requires PostgreSQL"]
async fn quota_buckets_are_separate() {
    with_store(|store| async move { conformance::quota_buckets_are_separate(&store).await }).await;
}

#[tokio::test]
#[ignore = "requires PostgreSQL"]
async fn update_token_needs_registered_origin() {
    with_store(
        |store| async move { conformance::update_token_needs_registered_origin(&store).await },
    )
    .await;
}

#[tokio::test]
#[ignore = "requires PostgreSQL"]
async fn revoke_installation_drops_live_activity_rows() {
    with_store(|store| async move {
        conformance::revoke_installation_drops_live_activity_rows(&store).await;
        let rows: i64 = sqlx::query_scalar(
            "SELECT (SELECT count(*) FROM push_gateway_live_activity_starts)
                  + (SELECT count(*) FROM push_gateway_live_activities)",
        )
        .fetch_one(&store.pool)
        .await
        .unwrap();
        assert_eq!(rows, 0);
    })
    .await;
}

#[tokio::test]
#[ignore = "requires PostgreSQL"]
async fn reaper_drops_stale_update_rows() {
    with_store(|store| async move {
        conformance::reaper_drops_stale_update_rows(&store).await;
        let rows: i64 = sqlx::query_scalar(
            "SELECT (SELECT count(*) FROM push_gateway_live_activity_starts)
                  + (SELECT count(*) FROM push_gateway_live_activities)
                  + (SELECT count(*) FROM push_gateway_installations)",
        )
        .fetch_one(&store.pool)
        .await
        .unwrap();
        assert_eq!(rows, 0);
    })
    .await;
}

#[tokio::test]
#[ignore = "requires PostgreSQL"]
async fn origin_hash_array_constraints_hold_in_schema() {
    with_store(|store| async move {
        let id = conformance::seed(&store).await;
        for hashes in [
            vec![vec![1u8; 31]],
            vec![vec![1u8; 32], vec![1u8; 32]],
            (0..17u8).map(|i| vec![i; 32]).collect::<Vec<_>>(),
        ] {
            assert!(sqlx::query(
                "INSERT INTO push_gateway_live_activity_starts
                   (installation_id,token_ciphertext,token_fingerprint,origin_hashes,expires_at)
                 VALUES($1,'\\x01',$2,$3,now())",
            )
            .bind(id)
            .bind(vec![2u8; 32])
            .bind(&hashes)
            .execute(&store.pool)
            .await
            .is_err());
        }
    })
    .await;
}

struct RuntimeDatabase {
    admin: PgPool,
    migration: PgPool,
    runtime: PgPool,
    database: String,
    role: String,
}

impl RuntimeDatabase {
    async fn create() -> Self {
        let admin_url = std::env::var("BUZZ_TEST_DATABASE_URL")
            .or_else(|_| std::env::var("DATABASE_URL"))
            .unwrap_or_else(|_| TEST_DB_URL.to_owned());
        let admin = PgPoolOptions::new()
            .max_connections(1)
            .connect(&admin_url)
            .await
            .expect("connect as PostgreSQL test administrator");
        let suffix = Uuid::new_v4().simple().to_string();
        let database = format!("push_la_{suffix}");
        let role = format!("push_la_runtime_{suffix}");
        sqlx::query(AssertSqlSafe(format!(
            "CREATE ROLE {role} LOGIN PASSWORD 'runtime_test'"
        )))
        .execute(&admin)
        .await
        .expect("create runtime role");
        sqlx::query(AssertSqlSafe(format!("CREATE DATABASE {database}")))
            .execute(&admin)
            .await
            .expect("create gateway database");
        let mut migration_url = url::Url::parse(&admin_url).unwrap();
        migration_url.set_path(&database);
        let mut runtime_url = migration_url.clone();
        runtime_url.set_username(&role).unwrap();
        runtime_url.set_password(Some("runtime_test")).unwrap();
        let migration = PgPoolOptions::new()
            .max_connections(1)
            .connect(migration_url.as_str())
            .await
            .expect("connect migration role");
        PostgresAuthorityStore::apply_migrations_and_grants(&migration, &role)
            .await
            .expect("migrate and grant runtime role");
        let runtime = PgPoolOptions::new()
            .max_connections(1)
            .connect(runtime_url.as_str())
            .await
            .expect("connect runtime role");
        Self {
            admin,
            migration,
            runtime,
            database,
            role,
        }
    }

    async fn drop(self) {
        self.runtime.close().await;
        self.migration.close().await;
        sqlx::query(AssertSqlSafe(format!("DROP DATABASE {}", self.database)))
            .execute(&self.admin)
            .await
            .expect("drop test database");
        sqlx::query(AssertSqlSafe(format!("DROP ROLE {}", self.role)))
            .execute(&self.admin)
            .await
            .expect("drop test role");
    }
}

#[tokio::test]
#[ignore = "requires PostgreSQL with CREATEDB/CREATEROLE"]
async fn migration_grants_runtime_dml_on_live_activity_tables() {
    let db = RuntimeDatabase::create().await;
    let store = PostgresAuthorityStore::new(db.runtime.clone());
    assert!(store.ready().await.is_ok());
    for table in live_activity::TABLES {
        for privilege in ["SELECT", "INSERT", "UPDATE", "DELETE"] {
            let granted: bool =
                sqlx::query_scalar("SELECT has_table_privilege(current_user, $1, $2)")
                    .bind(format!("public.{table}"))
                    .bind(privilege)
                    .fetch_one(&db.runtime)
                    .await
                    .unwrap();
            assert!(granted, "{privilege} on {table}");
        }
    }
    conformance::registration_replaces_origins(&store).await;
    db.drop().await;
}

#[tokio::test]
#[ignore = "requires PostgreSQL with CREATEDB/CREATEROLE"]
async fn readiness_fails_without_live_activity_dml() {
    let db = RuntimeDatabase::create().await;
    let store = PostgresAuthorityStore::new(db.runtime.clone());
    assert!(store.ready().await.is_ok());
    for table in live_activity::TABLES {
        sqlx::query(AssertSqlSafe(format!(
            "REVOKE DELETE ON {table} FROM {}",
            db.role
        )))
        .execute(&db.migration)
        .await
        .unwrap();
        assert!(store.ready().await.is_err(), "{table}");
        sqlx::query(AssertSqlSafe(format!(
            "GRANT DELETE ON {table} TO {}",
            db.role
        )))
        .execute(&db.migration)
        .await
        .unwrap();
        assert!(store.ready().await.is_ok(), "{table}");
    }
    db.drop().await;
}
