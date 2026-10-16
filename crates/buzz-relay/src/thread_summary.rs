use buzz_core::thread_status::parse_thread_status;
use buzz_core::StoredEvent;
use buzz_db::thread::ThreadSummary;

pub(crate) fn thread_summary_content(
    summary: &ThreadSummary,
    status: Option<&StoredEvent>,
) -> serde_json::Value {
    let mut content = serde_json::json!({
        "reply_count": summary.reply_count,
        "descendant_count": summary.descendant_count,
        "last_reply_at": summary.last_reply_at.map(|t| t.timestamp()),
        "participants": summary.participants.iter().map(hex::encode).collect::<Vec<_>>(),
    });
    let parsed = status.and_then(|stored| {
        let rows: Vec<Vec<String>> = stored
            .event
            .tags
            .iter()
            .map(|t| t.as_slice().to_vec())
            .collect();
        parse_thread_status(&rows, &stored.event.content).ok()
    });
    if let Some(parsed) = parsed {
        content["status"] = serde_json::json!(parsed.status.as_str());
        content["title"] = serde_json::json!(parsed.title);
        content["ask"] = parsed.ask.map_or(
            serde_json::Value::Null,
            |ask| serde_json::json!({"text": ask.text, "event_id": ask.event_id}),
        );
    }
    content
}

#[cfg(test)]
mod tests {
    use super::*;
    use buzz_core::kind::KIND_THREAD_STATUS;
    use nostr::{EventBuilder, Keys, Kind, Tag};

    fn summary() -> ThreadSummary {
        ThreadSummary {
            reply_count: 2,
            descendant_count: 3,
            last_reply_at: None,
            participants: vec![vec![1u8; 32]],
        }
    }

    fn status(tags: &[&[&str]]) -> StoredEvent {
        let event = EventBuilder::new(Kind::Custom(KIND_THREAD_STATUS as u16), "")
            .tags(
                tags.iter()
                    .map(|t| Tag::parse(t.iter().copied()).expect("tag")),
            )
            .sign_with_keys(&Keys::generate())
            .expect("sign");
        StoredEvent::new(event, None)
    }

    #[test]
    fn summary_without_status_keeps_the_original_shape() {
        let content = thread_summary_content(&summary(), None);
        assert_eq!(content.as_object().expect("object").len(), 4);
        assert_eq!(content["reply_count"], 2);
        assert_eq!(content["descendant_count"], 3);
    }

    #[test]
    fn summary_carries_status_title_and_ask() {
        let root = "a".repeat(64);
        let ask = "b".repeat(64);
        let stored = status(&[
            &["d", &root],
            &["h", "11111111-1111-4111-8111-111111111111"],
            &["e", &root],
            &["status", "awaiting_owner"],
            &["title", "Rotate keys"],
            &["ask", "Merge PR 7?", &ask],
        ]);
        let content = thread_summary_content(&summary(), Some(&stored));
        assert_eq!(content["status"], "awaiting_owner");
        assert_eq!(content["title"], "Rotate keys");
        assert_eq!(content["ask"]["text"], "Merge PR 7?");
        assert_eq!(content["ask"]["event_id"], ask.as_str());
    }

    #[test]
    fn invalid_status_is_ignored() {
        let stored = status(&[&["d", "x"]]);
        assert!(thread_summary_content(&summary(), Some(&stored))
            .get("status")
            .is_none());
    }
}
