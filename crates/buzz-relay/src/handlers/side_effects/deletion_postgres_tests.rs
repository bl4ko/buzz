use super::*;
use buzz_db::channel::{ChannelType, ChannelVisibility};
use nostr::Keys;

struct Fixture {
    state: Arc<AppState>,
    tenant: TenantContext,
    other_tenant: TenantContext,
    channel: Uuid,
    other_channel: Uuid,
    owner: Keys,
    admin: Keys,
    member: Keys,
    target: Event,
    other_target: Event,
}

impl Fixture {
    async fn new() -> Self {
        let database_url = std::env::var("BUZZ_TEST_DATABASE_URL")
            .expect("isolated BUZZ_TEST_DATABASE_URL required");
        let pool = sqlx::PgPool::connect(&database_url)
            .await
            .expect("Postgres");
        let state = crate::state::tests::test_state_with_database_pool(pool).await;
        state.db.migrate().await.expect("migrations");
        state
            .db
            .ensure_future_partitions(1, true)
            .await
            .expect("event partitions");
        let host = format!("delete-admin-{}.local", Uuid::new_v4());
        let other_host = format!("delete-other-{}.local", Uuid::new_v4());
        let community = state.db.ensure_configured_community(&host).await.unwrap();
        let other = state
            .db
            .ensure_configured_community(&other_host)
            .await
            .unwrap();
        let tenant = TenantContext::resolved(community.id, &host);
        let other_tenant = TenantContext::resolved(other.id, &other_host);
        let owner = Keys::generate();
        let admin = Keys::generate();
        let member = Keys::generate();
        let channel = Uuid::new_v4();
        let other_channel = Uuid::new_v4();
        for (community, id) in [
            (tenant.community(), channel),
            (tenant.community(), other_channel),
            (other_tenant.community(), channel),
        ] {
            state
                .db
                .create_channel_with_id(
                    community,
                    id,
                    &format!("delete-{id}"),
                    ChannelType::Stream,
                    ChannelVisibility::Private,
                    None,
                    owner.public_key().as_bytes(),
                    None,
                )
                .await
                .unwrap();
        }
        state
            .db
            .add_relay_member(
                tenant.community(),
                &admin.public_key().to_hex(),
                "admin",
                None,
            )
            .await
            .unwrap();
        state
            .db
            .add_relay_member(
                tenant.community(),
                &member.public_key().to_hex(),
                "member",
                None,
            )
            .await
            .unwrap();
        state
            .db
            .add_member(
                tenant.community(),
                channel,
                member.public_key().as_bytes(),
                MemberRole::Member,
                Some(owner.public_key().as_bytes()),
            )
            .await
            .unwrap();
        let target = EventBuilder::new(Kind::Custom(45000), "message")
            .tags([Tag::parse(["h", &channel.to_string()]).unwrap()])
            .sign_with_keys(&owner)
            .unwrap();
        let other_target = EventBuilder::new(Kind::Custom(45000), "other message")
            .tags([Tag::parse(["h", &channel.to_string()]).unwrap()])
            .sign_with_keys(&owner)
            .unwrap();
        state
            .db
            .insert_event(tenant.community(), &target, Some(channel))
            .await
            .unwrap();
        state
            .db
            .insert_event(other_tenant.community(), &other_target, Some(channel))
            .await
            .unwrap();
        Self {
            state,
            tenant,
            other_tenant,
            channel,
            other_channel,
            owner,
            admin,
            member,
            target,
            other_target,
        }
    }

    fn command(&self, kind: u16, actor: &Keys, channel: Uuid, target: &Event) -> Event {
        EventBuilder::new(Kind::Custom(kind), "")
            .tags([
                Tag::parse(["h", &channel.to_string()]).unwrap(),
                Tag::parse(["e", &target.id.to_hex()]).unwrap(),
            ])
            .sign_with_keys(actor)
            .unwrap()
    }
}

#[tokio::test]
#[ignore = "requires isolated Postgres"]
async fn community_admin_can_delete_another_authors_private_channel_message() {
    let f = Fixture::new().await;
    assert!(!f
        .state
        .db
        .is_member(
            f.tenant.community(),
            f.channel,
            f.admin.public_key().as_bytes()
        )
        .await
        .unwrap());
    let command = f.command(9005, &f.admin, f.channel, &f.target);
    validate_admin_event(&f.tenant, 9005, &command, &f.state)
        .await
        .expect("community admin deletion");
}

#[tokio::test]
#[ignore = "requires isolated Postgres"]
async fn demoted_community_admin_loses_message_deletion_authority() {
    let f = Fixture::new().await;
    let command = f.command(9005, &f.admin, f.channel, &f.target);
    validate_admin_event(&f.tenant, 9005, &command, &f.state)
        .await
        .unwrap();
    assert!(f
        .state
        .db
        .update_relay_member_role(
            f.tenant.community(),
            &f.admin.public_key().to_hex(),
            "member"
        )
        .await
        .unwrap());
    assert!(validate_admin_event(&f.tenant, 9005, &command, &f.state)
        .await
        .is_err());
}

#[tokio::test]
#[ignore = "requires isolated Postgres"]
async fn community_member_cannot_delete_another_authors_message() {
    let f = Fixture::new().await;
    let command = f.command(9005, &f.member, f.channel, &f.target);
    let error = validate_admin_event(&f.tenant, 9005, &command, &f.state)
        .await
        .unwrap_err();
    assert_eq!(
        error.to_string(),
        "must be event author or community/channel owner/admin"
    );
}

#[tokio::test]
#[ignore = "requires isolated Postgres"]
async fn community_admin_cannot_delete_a_target_in_another_channel() {
    let f = Fixture::new().await;
    let command = f.command(9005, &f.admin, f.other_channel, &f.target);
    let error = validate_admin_event(&f.tenant, 9005, &command, &f.state)
        .await
        .unwrap_err();
    assert_eq!(
        error.to_string(),
        "target event belongs to a different channel"
    );
}

#[tokio::test]
#[ignore = "requires isolated Postgres"]
async fn community_admin_cannot_resolve_a_target_from_another_tenant() {
    let f = Fixture::new().await;
    f.state
        .db
        .add_relay_member(
            f.other_tenant.community(),
            &f.admin.public_key().to_hex(),
            "admin",
            None,
        )
        .await
        .unwrap();
    let command = f.command(9005, &f.admin, f.channel, &f.target);
    let error = validate_admin_event(&f.other_tenant, 9005, &command, &f.state)
        .await
        .unwrap_err();
    assert_eq!(error.to_string(), "target event not found");
}

#[tokio::test]
#[ignore = "requires isolated Postgres"]
async fn community_admin_role_does_not_cross_tenant_boundaries() {
    let f = Fixture::new().await;
    let command = f.command(9005, &f.admin, f.channel, &f.other_target);
    let error = validate_admin_event(&f.other_tenant, 9005, &command, &f.state)
        .await
        .unwrap_err();
    assert_eq!(
        error.to_string(),
        "must be event author or community/channel owner/admin"
    );
}

#[tokio::test]
#[ignore = "requires isolated Postgres"]
async fn channel_admin_keeps_message_deletion_authority() {
    let f = Fixture::new().await;
    f.state
        .db
        .add_member(
            f.tenant.community(),
            f.channel,
            f.member.public_key().as_bytes(),
            MemberRole::Admin,
            Some(f.owner.public_key().as_bytes()),
        )
        .await
        .unwrap();
    let command = f.command(9005, &f.member, f.channel, &f.target);
    validate_admin_event(&f.tenant, 9005, &command, &f.state)
        .await
        .expect("channel admin deletion");
}

#[tokio::test]
#[ignore = "requires isolated Postgres"]
async fn community_admin_does_not_gain_group_deletion_authority() {
    let f = Fixture::new().await;
    let command = f.command(9008, &f.admin, f.channel, &f.target);
    let error = validate_admin_event(&f.tenant, 9008, &command, &f.state)
        .await
        .unwrap_err();
    assert_eq!(error.to_string(), "only owner can delete group");
}

#[tokio::test]
#[ignore = "requires isolated Postgres"]
async fn standard_deletion_keeps_author_only_authority() {
    let f = Fixture::new().await;
    let admin_command = f.command(5, &f.admin, f.channel, &f.target);
    let error = validate_standard_deletion_event(&f.tenant, &admin_command, &f.state)
        .await
        .unwrap_err();
    assert_eq!(error.to_string(), "must be event author");
    let author_command = f.command(5, &f.owner, f.channel, &f.target);
    validate_standard_deletion_event(&f.tenant, &author_command, &f.state)
        .await
        .expect("author deletion");
}

#[tokio::test]
#[ignore = "requires isolated Postgres"]
async fn author_keeps_message_deletion_authority() {
    let f = Fixture::new().await;
    let command = f.command(9005, &f.owner, f.channel, &f.target);
    validate_admin_event(&f.tenant, 9005, &command, &f.state)
        .await
        .expect("author deletion");
}

#[tokio::test]
#[ignore = "requires isolated Postgres"]
async fn owning_human_keeps_agent_message_deletion_authority() {
    let f = Fixture::new().await;
    let agent = Keys::generate();
    f.state
        .db
        .ensure_user(f.tenant.community(), agent.public_key().as_bytes())
        .await
        .unwrap();
    f.state
        .db
        .ensure_user(f.tenant.community(), f.member.public_key().as_bytes())
        .await
        .unwrap();
    assert!(f
        .state
        .db
        .set_agent_owner(
            f.tenant.community(),
            agent.public_key().as_bytes(),
            f.member.public_key().as_bytes(),
        )
        .await
        .unwrap());
    let target = EventBuilder::new(Kind::Custom(45000), "agent message")
        .tags([Tag::parse(["h", &f.channel.to_string()]).unwrap()])
        .sign_with_keys(&agent)
        .unwrap();
    f.state
        .db
        .insert_event(f.tenant.community(), &target, Some(f.channel))
        .await
        .unwrap();
    let command = f.command(9005, &f.member, f.channel, &target);
    validate_admin_event(&f.tenant, 9005, &command, &f.state)
        .await
        .expect("owned agent deletion");
}
