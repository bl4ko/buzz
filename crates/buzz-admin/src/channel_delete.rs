//! `delete-channel`: the relay-admin path for a kind:9008 DELETE_GROUP.
//!
//! The relay accepts kind:9008 only from a channel owner. This command makes
//! the same soft delete and side effects from inside the relay container,
//! signed with the relay key, and writes a `channel_deleted` audit entry.

use std::sync::Arc;

use anyhow::Result;
use buzz_core::filter::NOTICE_CHANNEL_TYPE_TAG;
use buzz_core::kind::{KIND_MEMBER_REMOVED_NOTIFICATION, KIND_SYSTEM_MESSAGE};
use buzz_core::tenant::TenantContext;
use buzz_db::Db;
use buzz_pubsub::cache_invalidation::CacheInvalidation;
use buzz_pubsub::{EventTopic, PubSubManager};
use nostr::{Event, EventBuilder, Keys, Kind, Tag};
use uuid::Uuid;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum Refusal {
    DirectMessage,
    GitRepository,
}

pub(crate) fn refusal(channel_type: &str, git_bound: bool) -> Option<Refusal> {
    if channel_type == "dm" {
        Some(Refusal::DirectMessage)
    } else if git_bound {
        Some(Refusal::GitRepository)
    } else {
        None
    }
}

pub(crate) fn refusal_result(refusal: Refusal) -> (i32, &'static str) {
    match refusal {
        Refusal::DirectMessage => (3, "direct_message"),
        Refusal::GitRepository => (4, "git_repository"),
    }
}

pub(crate) fn member_removed(
    keys: &Keys,
    channel_id: Uuid,
    channel_type: &str,
    member: &[u8],
) -> Result<Event> {
    let content = serde_json::json!({
        "type": "member_removed",
        "channel_id": channel_id.to_string(),
        "actor": keys.public_key().to_hex(),
    });
    Ok(EventBuilder::new(
        Kind::Custom(KIND_MEMBER_REMOVED_NOTIFICATION as u16),
        content.to_string(),
    )
    .tags([
        Tag::parse(["p", &hex::encode(member)])?,
        Tag::parse(["h", &channel_id.to_string()])?,
        Tag::parse([NOTICE_CHANNEL_TYPE_TAG, channel_type])?,
    ])
    .sign_with_keys(keys)?)
}

pub(crate) fn channel_deleted(keys: &Keys, channel_id: Uuid) -> Result<Event> {
    let content = serde_json::json!({
        "type": "channel_deleted",
        "actor": keys.public_key().to_hex(),
    });
    Ok(EventBuilder::new(
        Kind::Custom(KIND_SYSTEM_MESSAGE as u16),
        content.to_string(),
    )
    .tags([Tag::parse(["h", &channel_id.to_string()])?])
    .sign_with_keys(keys)?)
}

pub(crate) async fn run(
    db: &Db,
    pubsub: &Arc<PubSubManager>,
    keys: &Keys,
    tenant: &TenantContext,
    channel_id: Uuid,
    operator_id: String,
    reason: String,
) -> Result<i32> {
    let mut evidence = serde_json::json!({
        "event": "channel_delete",
        "community": tenant.host(),
        "channel": channel_id.to_string(),
        "operator_id": operator_id,
        "reason": reason,
    });
    let done = |mut evidence: serde_json::Value, status: &str, code: i32| {
        evidence["status"] = status.into();
        println!("{evidence}");
        Ok(code)
    };
    let channel = match db.get_channel(tenant.community(), channel_id).await {
        Ok(channel) if channel.deleted_at.is_none() => channel,
        _ => return done(evidence, "not_found", 2),
    };
    evidence["name"] = channel.name.clone().into();
    evidence["channel_type"] = channel.channel_type.clone().into();
    let git_bound = db
        .channel_has_git_repo(tenant.community(), channel_id)
        .await?;
    if let Some(refused) = refusal(&channel.channel_type, git_bound) {
        let (code, status) = refusal_result(refused);
        return done(evidence, status, code);
    }
    let Some(deleted) = db
        .soft_delete_channel_capturing_members(tenant.community(), channel_id)
        .await?
    else {
        return done(evidence, "not_found", 2);
    };
    evidence["members"] = deleted
        .members
        .iter()
        .map(hex::encode)
        .collect::<Vec<_>>()
        .into();
    let mut failures = Vec::new();
    if let Err(e) = db
        .soft_delete_discovery_events(
            tenant.community(),
            channel_id,
            &keys.public_key().to_bytes(),
        )
        .await
    {
        failures.push(format!("discovery: {e}"));
    }
    if let Err(e) = pubsub
        .publish_cache_invalidation(tenant, &CacheInvalidation::ChannelDeleted)
        .await
    {
        failures.push(format!("cache: {e}"));
    }
    for member in &deleted.members {
        let event = member_removed(keys, channel_id, &deleted.channel_type, member)?;
        if let Err(e) = publish(db, pubsub, tenant, &event, None, EventTopic::Global).await {
            failures.push(format!("notice {}: {e}", hex::encode(member)));
        }
    }
    let system = channel_deleted(keys, channel_id)?;
    let topic = EventTopic::Channel(channel_id);
    if let Err(e) = publish(db, pubsub, tenant, &system, Some(channel_id), topic).await {
        failures.push(format!("system message: {e}"));
    }
    let entry = buzz_audit::NewAuditEntry {
        community_id: tenant.community(),
        action: buzz_audit::AuditAction::ChannelDeleted,
        actor_pubkey: None,
        object_id: Some(channel_id.to_string()),
        detail: serde_json::json!({
            "name": channel.name,
            "channel_type": deleted.channel_type,
            "members": evidence["members"],
            "operator_id": operator_id,
            "reason": reason,
        }),
    };
    match buzz_audit::AuditService::new(db.pool().clone())
        .log(entry)
        .await
    {
        Ok(stored) => {
            evidence["audit_seq"] = stored.seq.into();
            evidence["deleted_at"] = stored.created_at.to_rfc3339().into();
        }
        Err(e) => {
            evidence["audit_error"] = e.to_string().into();
            return done(evidence, "deleted", 6);
        }
    }
    if !failures.is_empty() {
        evidence["side_effect_errors"] = failures.into();
        return done(evidence, "deleted", 7);
    }
    done(evidence, "deleted", 0)
}

async fn publish(
    db: &Db,
    pubsub: &Arc<PubSubManager>,
    tenant: &TenantContext,
    event: &Event,
    channel_id: Option<Uuid>,
    topic: EventTopic,
) -> Result<()> {
    let (stored, inserted) = db
        .insert_event(tenant.community(), event, channel_id)
        .await?;
    if inserted {
        pubsub.publish_event(tenant, topic, &stored.event).await?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_direct_message_and_a_git_channel_are_refused() {
        assert_eq!(refusal("stream", false), None);
        assert_eq!(refusal("forum", false), None);
        assert_eq!(refusal("dm", false), Some(Refusal::DirectMessage));
        assert_eq!(refusal("dm", true), Some(Refusal::DirectMessage));
        assert_eq!(refusal("stream", true), Some(Refusal::GitRepository));
        assert_eq!(
            refusal_result(Refusal::DirectMessage),
            (3, "direct_message")
        );
        assert_eq!(
            refusal_result(Refusal::GitRepository),
            (4, "git_repository")
        );
    }

    #[test]
    fn the_notices_match_the_relay_delete_group_side_effects() {
        let keys = Keys::generate();
        let channel = Uuid::new_v4();
        let member = Keys::generate().public_key().to_bytes();
        let notice = member_removed(&keys, channel, "stream", &member).unwrap();
        assert_eq!(notice.kind.as_u16(), 44101);
        assert_eq!(notice.pubkey, keys.public_key());
        let tags: Vec<Vec<String>> = notice.tags.iter().map(|t| t.as_slice().to_vec()).collect();
        assert_eq!(
            tags,
            [
                vec!["p".to_string(), hex::encode(member)],
                vec!["h".to_string(), channel.to_string()],
                vec!["t".to_string(), "stream".to_string()],
            ]
        );
        let content: serde_json::Value = serde_json::from_str(&notice.content).unwrap();
        assert_eq!(
            content,
            serde_json::json!({"type": "member_removed", "channel_id": channel.to_string(), "actor": keys.public_key().to_hex()})
        );
        let system = channel_deleted(&keys, channel).unwrap();
        assert_eq!(system.kind.as_u16(), 40099);
        let content: serde_json::Value = serde_json::from_str(&system.content).unwrap();
        assert_eq!(content["type"], "channel_deleted");
        assert_eq!(
            system.tags.iter().next().unwrap().as_slice(),
            ["h", &channel.to_string()]
        );
    }
}
