//! The relay-signed `message_deleted` deletion notice (kind 40099).
//!
//! Both deletion emitters — NIP-29 `DELETE_EVENT` (kind 9005) and the admin
//! outbox tombstone — build their notice here so the wire contract has one
//! implementation.
//!
//! The notice's `created_at` is always the deletion-notice time, never the
//! original's time: subscribers filter live fan-out by `since`, so a backdated
//! notice would never reach them. The original's position travels in the
//! optional, versioned `original` object instead. Tags are exactly one `h`
//! plus unmarked `e` references (target, root, parent; deduplicated) for
//! indexed lookup — no `reply`/`root` markers, so no client treats the notice
//! as a conversational reply, and no `p` tags, so nobody is notified.

use buzz_core::kind::KIND_SYSTEM_MESSAGE;
use buzz_db::event::OriginalSlot;
use buzz_db::thread::ThreadMetadataRecord;
use chrono::{DateTime, Utc};
use nostr::{Event, EventBuilder, Keys, Kind, Tag, Timestamp};
use uuid::Uuid;

/// Version of the `original` slot object emitted by this relay.
pub const ORIGINAL_SLOT_VERSION: u32 = 1;

/// Inputs for one deletion notice.
pub struct DeleteTombstone<'a> {
    /// Channel the deleted event belonged to (already authorized by the caller).
    pub channel_id: Uuid,
    /// Deleted event ID (64-char hex).
    pub target_event_id: &'a str,
    /// Acting principal pubkey (hex).
    pub actor: &'a str,
    /// Admin action ID, when the deletion came from moderation.
    pub action_id: Option<&'a str>,
    /// Moderation reason code.
    pub reason_code: Option<&'a str>,
    /// Room-facing moderation reason.
    pub public_reason: Option<&'a str>,
    /// The deleted event's slot, when known. An invalid slot is dropped and the
    /// notice degrades to the legacy form rather than inventing structure.
    pub original: Option<&'a OriginalSlot>,
}

/// Sign the deletion notice at `created_at` with the relay keys.
pub fn build_delete_tombstone(
    tombstone: &DeleteTombstone<'_>,
    created_at: DateTime<Utc>,
    relay_keys: &Keys,
) -> anyhow::Result<Event> {
    let original = tombstone
        .original
        .filter(|slot| valid_original_slot(slot, tombstone.target_event_id));

    let mut content = serde_json::json!({
        "type": "message_deleted",
        "actor": tombstone.actor,
        "target_event_id": tombstone.target_event_id,
    });
    for (field, value) in [
        ("action_id", tombstone.action_id),
        ("reason_code", tombstone.reason_code),
        ("public_reason", tombstone.public_reason),
    ] {
        if let Some(value) = value {
            content[field] = value.into();
        }
    }
    if let Some(slot) = original {
        content["original"] = serde_json::json!({
            "version": ORIGINAL_SLOT_VERSION,
            "created_at": slot.created_at,
            "parent_event_id": slot.parent_event_id,
            "root_event_id": slot.root_event_id,
            "depth": slot.depth,
            "broadcast": slot.broadcast,
        });
    }

    let mut references = vec![tombstone.target_event_id];
    if let Some(slot) = original {
        for id in [&slot.root_event_id, &slot.parent_event_id]
            .into_iter()
            .flatten()
        {
            if !references.contains(&id.as_str()) {
                references.push(id);
            }
        }
    }
    let mut tags = vec![Tag::parse(["h", &tombstone.channel_id.to_string()])?];
    for id in references {
        tags.push(Tag::parse(["e", id])?);
    }

    EventBuilder::new(
        Kind::Custom(KIND_SYSTEM_MESSAGE as u16),
        content.to_string(),
    )
    .tags(tags)
    .custom_created_at(Timestamp::from(created_at.timestamp().max(0) as u64))
    .sign_with_keys(relay_keys)
    .map_err(|e| anyhow::anyhow!("failed to sign deletion notice: {e}"))
}

/// The slot of a still-stored event: its `created_at` plus canonical thread
/// metadata. No metadata row means a top-level message.
pub fn original_slot(target_created_at: i64, meta: Option<&ThreadMetadataRecord>) -> OriginalSlot {
    OriginalSlot {
        created_at: target_created_at,
        parent_event_id: meta.and_then(|m| m.parent_event_id.as_deref().map(hex::encode)),
        root_event_id: meta.and_then(|m| m.root_event_id.as_deref().map(hex::encode)),
        depth: meta.map_or(0, |m| m.depth),
        broadcast: meta.is_some_and(|m| m.broadcast),
    }
}

/// All-or-nothing v1 shape check: top-level has neither ID at depth 0; a direct
/// reply has parent == root at depth 1; a nested reply has distinct parent and
/// root at depth > 1. IDs are full hex and never the target itself.
fn valid_original_slot(slot: &OriginalSlot, target_event_id: &str) -> bool {
    let is_id = |id: &str| {
        id.len() == 64
            && id
                .bytes()
                .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
    };
    let shape = match (
        slot.parent_event_id.as_deref(),
        slot.root_event_id.as_deref(),
    ) {
        (None, None) => slot.depth == 0,
        (Some(parent), Some(root)) => {
            is_id(parent)
                && is_id(root)
                && parent != target_event_id
                && root != target_event_id
                && match slot.depth {
                    1 => parent == root,
                    d => d > 1 && parent != root,
                }
        }
        _ => false,
    };
    shape && slot.created_at >= 0
}

#[cfg(test)]
mod tests {
    use super::*;

    const TARGET: &str = "1111111111111111111111111111111111111111111111111111111111111111";
    const ROOT: &str = "2222222222222222222222222222222222222222222222222222222222222222";
    const PARENT: &str = "3333333333333333333333333333333333333333333333333333333333333333";

    fn slot(parent: Option<&str>, root: Option<&str>, depth: i32) -> OriginalSlot {
        OriginalSlot {
            created_at: 100,
            parent_event_id: parent.map(str::to_owned),
            root_event_id: root.map(str::to_owned),
            depth,
            broadcast: false,
        }
    }

    fn notice(original: Option<&OriginalSlot>) -> Event {
        build_delete_tombstone(
            &DeleteTombstone {
                channel_id: Uuid::nil(),
                target_event_id: TARGET,
                actor: "actor",
                action_id: None,
                reason_code: None,
                public_reason: None,
                original,
            },
            DateTime::from_timestamp(300, 0).expect("ts"),
            &Keys::generate(),
        )
        .expect("build")
    }

    fn tags(event: &Event) -> Vec<Vec<String>> {
        event.tags.iter().map(|t| t.as_slice().to_vec()).collect()
    }

    fn content(event: &Event) -> serde_json::Value {
        serde_json::from_str(&event.content).expect("json")
    }

    #[test]
    fn nested_reply_notice_carries_slot_and_unmarked_references() {
        let event = notice(Some(&slot(Some(PARENT), Some(ROOT), 2)));
        assert_eq!(event.created_at.as_secs(), 300, "notice time, not original");
        assert_eq!(
            tags(&event),
            vec![
                vec!["h".to_owned(), Uuid::nil().to_string()],
                vec!["e".to_owned(), TARGET.to_owned()],
                vec!["e".to_owned(), ROOT.to_owned()],
                vec!["e".to_owned(), PARENT.to_owned()],
            ]
        );
        assert_eq!(
            content(&event)["original"],
            serde_json::json!({
                "version": 1, "created_at": 100, "parent_event_id": PARENT,
                "root_event_id": ROOT, "depth": 2, "broadcast": false,
            })
        );
    }

    #[test]
    fn direct_reply_references_are_deduplicated() {
        let event = notice(Some(&slot(Some(ROOT), Some(ROOT), 1)));
        assert_eq!(tags(&event).len(), 3, "h + target + root once");
    }

    #[test]
    fn malformed_slots_degrade_to_legacy_notice() {
        for bad in [
            slot(Some(ROOT), None, 1),
            slot(None, None, 1),
            slot(Some(PARENT), Some(ROOT), 1),
            slot(Some(ROOT), Some(ROOT), 2),
            slot(Some(TARGET), Some(TARGET), 1),
            slot(Some("ab"), Some("ab"), 1),
            slot(Some(&"A".repeat(64)), Some(&"A".repeat(64)), 1),
            OriginalSlot {
                created_at: -1,
                ..slot(None, None, 0)
            },
        ] {
            let event = notice(Some(&bad));
            assert!(content(&event).get("original").is_none(), "{bad:?}");
            assert_eq!(tags(&event).len(), 2, "{bad:?}");
        }
    }

    #[test]
    fn legacy_notice_omits_absent_moderation_metadata() {
        let event = notice(None);
        let content = content(&event);
        assert_eq!(content["type"], "message_deleted");
        assert_eq!(content["target_event_id"], TARGET);
        for field in ["action_id", "reason_code", "public_reason", "original"] {
            assert!(content.get(field).is_none(), "{field}");
        }
    }
}
