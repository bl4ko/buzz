use super::postgres_tests::make_community;
use super::*;

async fn pool() -> PgPool {
    let pool = PgPool::connect(&crate::test_support::database_url())
        .await
        .expect("isolated database");
    if std::env::var("BUZZ_TEST_SCHEMA_MODE").as_deref() != Ok("desired") {
        crate::migration::run_migrations(&pool)
            .await
            .expect("run migrations");
    }
    pool
}

fn signed(keys: &nostr::Keys, installation: &str, created_at: u64) -> nostr::Event {
    nostr::EventBuilder::new(nostr::Kind::Custom(30_350), "ciphertext")
        .tag(nostr::Tag::parse(["d", installation]).expect("d tag"))
        .custom_created_at(nostr::Timestamp::from(created_at))
        .sign_with_keys(keys)
        .expect("sign lease event")
}

async fn publish(
    pool: &PgPool,
    community: CommunityId,
    event: &nostr::Event,
    generation: i64,
    endpoint: Option<&[u8]>,
) -> AcceptLeaseOutcome {
    let installation = event
        .tags
        .identifier()
        .expect("lease has a d tag")
        .to_owned();
    let subscriptions = serde_json::json!([]);
    accept_lease_event(
        pool,
        community,
        event,
        &installation,
        LeaseVersion {
            source_event_id: event.id.as_bytes(),
            source_created_at: event.created_at.as_secs() as i64,
            generation,
            expires_at: i64::MAX / 2,
        },
        endpoint.map(|endpoint_hash| ActiveLease {
            endpoint_hash,
            endpoint_grant: "same-device-grant",
            max_class: "default",
            subscriptions: &subscriptions,
        }),
        16,
    )
    .await
    .expect("lease acceptance")
}

async fn lease(
    pool: &PgPool,
    community: CommunityId,
    author: &nostr::Keys,
    installation: &str,
) -> (bool, Option<Vec<u8>>) {
    sqlx::query_as(
        "SELECT active, endpoint_hash FROM push_leases \
         WHERE community_id=$1 AND author=$2 AND installation_id=$3",
    )
    .bind(community.as_uuid())
    .bind(author.public_key().as_bytes().as_slice())
    .bind(installation)
    .fetch_one(pool)
    .await
    .expect("lease row")
}

async fn card_installations(
    pool: &PgPool,
    community: CommunityId,
    author: &nostr::Keys,
) -> Vec<(String, String)> {
    sqlx::query_as(
        "SELECT installation_id, result FROM push_live_activity_state \
         WHERE community_id=$1 AND author=$2 ORDER BY installation_id",
    )
    .bind(community.as_uuid())
    .bind(author.public_key().as_bytes().as_slice())
    .fetch_all(pool)
    .await
    .expect("card state")
}

#[tokio::test]
#[ignore = "requires Postgres"]
async fn repaired_installation_takes_over_its_authors_endpoint() {
    let pool = pool().await;
    let community = make_community(&pool).await;
    let owner = nostr::Keys::generate();
    let endpoint = [7; 32];

    let old = signed(&owner, "old", 1_000);
    assert_eq!(
        publish(&pool, community, &old, 3, Some(&endpoint)).await,
        AcceptLeaseOutcome::Accepted
    );
    sqlx::query(
        "INSERT INTO push_live_activity_state (community_id, author, installation_id, \
             lease_generation, open_count, content_hash, result, started_at, last_sent_at) \
         VALUES ($1, $2, 'old', 3, 1, $3, 'started', 1000, 1000)",
    )
    .bind(community.as_uuid())
    .bind(owner.public_key().as_bytes().as_slice())
    .bind([9_u8; 32].as_slice())
    .execute(&pool)
    .await
    .expect("open card");

    let older_repair = signed(&owner, "new", 999);
    assert_eq!(
        publish(&pool, community, &older_repair, 1, Some(&endpoint)).await,
        AcceptLeaseOutcome::EndpointAlreadyLeased,
        "a lease older than the endpoint's holder must not take it over"
    );
    assert!(lease(&pool, community, &owner, "old").await.0);

    let repair = signed(&owner, "new", 1_010);
    assert_eq!(
        publish(&pool, community, &repair, 1, Some(&endpoint)).await,
        AcceptLeaseOutcome::Accepted
    );
    assert_eq!(
        lease(&pool, community, &owner, "old").await,
        (false, None),
        "the replaced lease is retired and releases the endpoint"
    );
    assert_eq!(
        lease(&pool, community, &owner, "new").await,
        (true, Some(endpoint.to_vec()))
    );
    assert_eq!(
        card_installations(&pool, community, &owner).await,
        vec![("new".to_owned(), "started".to_owned())],
        "the open card follows the endpoint so the relay can still update or end it"
    );

    let other = nostr::Keys::generate();
    publish(
        &pool,
        community,
        &signed(&other, "other", 1_020),
        1,
        Some(&endpoint),
    )
    .await;
    assert_eq!(
        lease(&pool, community, &owner, "new").await,
        (true, Some(endpoint.to_vec())),
        "another author never retires this author's lease"
    );

    assert_eq!(
        publish(&pool, community, &old, 3, Some(&endpoint)).await,
        AcceptLeaseOutcome::StaleEvent,
        "a replayed old lease stays stale"
    );
    let delayed = signed(&owner, "old", 1_005);
    assert_eq!(
        publish(&pool, community, &delayed, 4, Some(&endpoint)).await,
        AcceptLeaseOutcome::StaleEvent,
        "an old-installation lease signed before the replacement stays stale"
    );
    assert_eq!(
        publish(&pool, community, &signed(&owner, "new", 1_030), 2, None).await,
        AcceptLeaseOutcome::Accepted
    );
    assert_eq!(
        publish(&pool, community, &delayed, 4, Some(&endpoint)).await,
        AcceptLeaseOutcome::StaleEvent,
        "revoking the replacement does not revive a lease it replaced"
    );
    assert_eq!(lease(&pool, community, &owner, "old").await, (false, None));
}
