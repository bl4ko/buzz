use std::collections::HashSet;

use serde::{Deserialize, Serialize};

/// Maximum title length in characters.
pub const THREAD_STATUS_TITLE_MAX_CHARS: usize = 80;
/// Maximum ask question length in characters.
pub const THREAD_STATUS_ASK_MAX_CHARS: usize = 400;
/// Maximum number of custom tabs in one channel.
pub const CHANNEL_TABS_MAX: usize = 50;
/// Maximum size of a tab list event content.
pub const CHANNEL_TABS_MAX_BYTES: usize = 16_384;
/// Maximum size of a canvas document.
pub const CANVAS_DOC_MAX_BYTES: usize = 65_536;

/// Task status of a thread root.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TaskStatus {
    /// Reported, not yet taken.
    Open,
    /// Work in progress.
    InProgress,
    /// Waiting for an owner decision.
    AwaitingOwner,
    /// Blocked on evidence or access.
    Blocked,
    /// Closed.
    Done,
}

impl TaskStatus {
    /// Parse the wire value.
    pub fn parse(value: &str) -> Option<Self> {
        match value {
            "open" => Some(Self::Open),
            "in_progress" => Some(Self::InProgress),
            "awaiting_owner" => Some(Self::AwaitingOwner),
            "blocked" => Some(Self::Blocked),
            "done" => Some(Self::Done),
            _ => None,
        }
    }

    /// Wire value.
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Open => "open",
            Self::InProgress => "in_progress",
            Self::AwaitingOwner => "awaiting_owner",
            Self::Blocked => "blocked",
            Self::Done => "done",
        }
    }
}

/// Owner question attached to an awaiting_owner status.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ThreadStatusAsk {
    /// Yes/no question text.
    pub text: String,
    /// Event ID of the message that carries the question.
    pub event_id: String,
}

/// Validated kind 30320 tags.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ThreadStatusTags {
    /// Thread root event ID.
    pub root_id: String,
    /// Channel ID from the h tag.
    pub channel_id: String,
    /// Task status.
    pub status: TaskStatus,
    /// Task title.
    pub title: String,
    /// Owner question, only for awaiting_owner.
    pub ask: Option<ThreadStatusAsk>,
}

/// One entry of a kind 30321 tab list.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ChannelTab {
    /// Stable tab ID.
    pub id: String,
    /// Tab type such as link, search, thread, or canvas.
    #[serde(rename = "type")]
    pub kind: String,
    /// Tab label.
    pub title: String,
    /// Type-specific value.
    pub value: String,
}

fn is_hex64(value: &str) -> bool {
    value.len() == 64
        && value
            .bytes()
            .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
}

fn is_slug(value: &str) -> bool {
    !value.is_empty()
        && value.len() <= 64
        && value
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b == b'-' || b == b'_')
}

fn named<'a>(rows: &'a [Vec<String>], name: &str) -> Vec<&'a Vec<String>> {
    rows.iter()
        .filter(|row| row.first().map(String::as_str) == Some(name))
        .collect()
}

fn one_value(rows: &[Vec<String>], name: &str) -> Result<String, String> {
    match named(rows, name).as_slice() {
        [row] => row
            .get(1)
            .cloned()
            .ok_or_else(|| format!("thread status {name} tag needs a value")),
        [] => Err(format!("thread status requires a {name} tag")),
        _ => Err(format!("thread status must have one {name} tag")),
    }
}

/// Validate kind 30320 tags and content.
pub fn parse_thread_status(
    rows: &[Vec<String>],
    content: &str,
) -> Result<ThreadStatusTags, String> {
    if !content.is_empty() {
        return Err("thread status content must be empty".into());
    }
    let d = one_value(rows, "d")?;
    let channel_id = one_value(rows, "h")?;
    let e_rows = named(rows, "e");
    let [e] = e_rows.as_slice() else {
        return Err(format!(
            "thread status must have exactly one e tag (got {})",
            e_rows.len()
        ));
    };
    if e.get(3).is_some_and(|marker| !marker.is_empty()) {
        return Err("thread status e tag must not carry a thread marker".into());
    }
    let root_id = e.get(1).cloned().unwrap_or_default();
    if !is_hex64(&root_id) || root_id != d {
        return Err("thread status d and e tags must name the same root event".into());
    }
    let status = TaskStatus::parse(&one_value(rows, "status")?)
        .ok_or("thread status must be open, in_progress, awaiting_owner, blocked, or done")?;
    let title = one_value(rows, "title")?;
    if title.trim().is_empty() || title.chars().count() > THREAD_STATUS_TITLE_MAX_CHARS {
        return Err("thread status title must have 1 to 80 characters".into());
    }
    let ask = match named(rows, "ask").as_slice() {
        [] => None,
        [row] => {
            let text = row.get(1).cloned().unwrap_or_default();
            let event_id = row.get(2).cloned().unwrap_or_default();
            if text.trim().is_empty()
                || text.chars().count() > THREAD_STATUS_ASK_MAX_CHARS
                || !is_hex64(&event_id)
            {
                return Err(
                    "thread status ask needs a question of 1 to 400 characters and an event ID"
                        .into(),
                );
            }
            Some(ThreadStatusAsk { text, event_id })
        }
        _ => return Err("thread status must have one ask tag".into()),
    };
    match (status, ask.is_some()) {
        (TaskStatus::AwaitingOwner, false) => {
            Err("awaiting_owner thread status requires an ask tag".into())
        }
        (TaskStatus::AwaitingOwner, true) | (_, false) => Ok(ThreadStatusTags {
            root_id,
            channel_id,
            status,
            title,
            ask,
        }),
        (_, true) => Err("only awaiting_owner thread status may carry an ask tag".into()),
    }
}

impl ThreadStatusTags {
    /// Canonical tag order for publishing.
    pub fn to_tags(&self) -> Vec<Vec<String>> {
        let mut rows = vec![
            vec!["d".to_string(), self.root_id.clone()],
            vec!["h".to_string(), self.channel_id.clone()],
            vec!["e".to_string(), self.root_id.clone()],
            vec!["status".to_string(), self.status.as_str().to_string()],
            vec!["title".to_string(), self.title.clone()],
        ];
        if let Some(ask) = &self.ask {
            rows.push(vec![
                "ask".to_string(),
                ask.text.clone(),
                ask.event_id.clone(),
            ]);
        }
        rows
    }
}

/// Validate kind 30321 content.
pub fn parse_channel_tabs(content: &str) -> Result<Vec<ChannelTab>, String> {
    if content.len() > CHANNEL_TABS_MAX_BYTES {
        return Err(format!(
            "channel tabs content exceeds {CHANNEL_TABS_MAX_BYTES} bytes"
        ));
    }
    let tabs: Vec<ChannelTab> = serde_json::from_str(content)
        .map_err(|e| format!("channel tabs content must be a JSON tab list: {e}"))?;
    if tabs.len() > CHANNEL_TABS_MAX {
        return Err(format!(
            "channel tabs allow at most {CHANNEL_TABS_MAX} tabs"
        ));
    }
    let mut ids = HashSet::new();
    for tab in &tabs {
        if !is_slug(&tab.id) {
            return Err("channel tab id must be 1 to 64 letters, digits, - or _".into());
        }
        if !ids.insert(tab.id.as_str()) {
            return Err("channel tab ids must be unique".into());
        }
        if tab.kind.is_empty() || tab.kind.len() > 32 {
            return Err("channel tab type must have 1 to 32 characters".into());
        }
        if tab.title.trim().is_empty() || tab.title.chars().count() > 40 {
            return Err("channel tab title must have 1 to 40 characters".into());
        }
        if tab.value.len() > 2048 {
            return Err("channel tab value must be at most 2048 bytes".into());
        }
    }
    Ok(tabs)
}

/// Validate a kind 30322 d tag and return the canvas ID.
pub fn parse_canvas_d_tag(d: &str, channel_id: &str) -> Result<String, String> {
    match d.split_once(':') {
        Some((channel, canvas)) if channel == channel_id && is_slug(canvas) => {
            Ok(canvas.to_string())
        }
        _ => Err("canvas d tag must be <channel-id>:<canvas-id>".into()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn root() -> String {
        "a".repeat(64)
    }

    fn ask_id() -> String {
        "b".repeat(64)
    }

    fn tags(status: &str, title: &str, ask: Option<(&str, &str)>) -> Vec<Vec<String>> {
        let mut rows = vec![
            vec!["d".to_string(), root()],
            vec![
                "h".to_string(),
                "11111111-1111-4111-8111-111111111111".to_string(),
            ],
            vec!["e".to_string(), root()],
            vec!["status".to_string(), status.to_string()],
            vec!["title".to_string(), title.to_string()],
        ];
        if let Some((text, id)) = ask {
            rows.push(vec!["ask".to_string(), text.to_string(), id.to_string()]);
        }
        rows
    }

    #[test]
    fn parses_and_round_trips_each_status() {
        for status in ["open", "in_progress", "blocked", "done"] {
            let rows = tags(status, "Rotate keys", None);
            let parsed = parse_thread_status(&rows, "").unwrap();
            assert_eq!(parsed.status.as_str(), status);
            assert_eq!(parsed.to_tags(), rows);
        }
        let ask = ask_id();
        let rows = tags("awaiting_owner", "Rotate keys", Some(("Merge PR 7?", &ask)));
        let parsed = parse_thread_status(&rows, "").unwrap();
        assert_eq!(parsed.ask.as_ref().unwrap().event_id, ask);
        assert_eq!(parsed.to_tags(), rows);
    }

    #[test]
    fn ask_belongs_only_to_awaiting_owner() {
        let ask = ask_id();
        assert_eq!(
            parse_thread_status(&tags("awaiting_owner", "T", None), "").unwrap_err(),
            "awaiting_owner thread status requires an ask tag"
        );
        assert_eq!(
            parse_thread_status(&tags("blocked", "T", Some(("Q?", &ask))), "").unwrap_err(),
            "only awaiting_owner thread status may carry an ask tag"
        );
        assert!(parse_thread_status(&tags("awaiting_owner", "T", Some(("", &ask))), "").is_err());
        assert!(
            parse_thread_status(&tags("awaiting_owner", "T", Some(("Q?", "xyz"))), "").is_err()
        );
        let long = "q".repeat(401);
        assert!(
            parse_thread_status(&tags("awaiting_owner", "T", Some((&long, &ask))), "").is_err()
        );
    }

    #[test]
    fn title_limit_counts_characters() {
        assert!(parse_thread_status(&tags("open", &"é".repeat(80), None), "").is_ok());
        assert_eq!(
            parse_thread_status(&tags("open", &"é".repeat(81), None), "").unwrap_err(),
            "thread status title must have 1 to 80 characters"
        );
        assert!(parse_thread_status(&tags("open", "   ", None), "").is_err());
    }

    #[test]
    fn rejects_malformed_shapes() {
        let mut other_root = tags("open", "T", None);
        other_root[2][1] = "c".repeat(64);
        assert!(parse_thread_status(&other_root, "").is_err());
        let mut marked = tags("open", "T", None);
        marked[2] = vec!["e".into(), root(), "".into(), "root".into()];
        assert!(parse_thread_status(&marked, "").is_err());
        let mut two_e = tags("open", "T", None);
        two_e.push(vec!["e".into(), root()]);
        assert!(parse_thread_status(&two_e, "").is_err());
        let mut upper = tags("open", "T", None);
        upper[0][1] = "A".repeat(64);
        upper[2][1] = "A".repeat(64);
        assert!(parse_thread_status(&upper, "").is_err());
        assert!(parse_thread_status(&tags("finished", "T", None), "").is_err());
        assert_eq!(
            parse_thread_status(&tags("open", "T", None), "x").unwrap_err(),
            "thread status content must be empty"
        );
        let missing_h: Vec<Vec<String>> = tags("open", "T", None)
            .into_iter()
            .filter(|t| t[0] != "h")
            .collect();
        assert!(parse_thread_status(&missing_h, "").is_err());
    }

    #[test]
    fn channel_tabs_accept_unknown_types_and_reject_bad_lists() {
        let ok = r#"[{"id":"t1","type":"link","title":"Grafana","value":"https://grafana.xqx.uk"},{"id":"t2","type":"future","title":"X","value":""}]"#;
        assert_eq!(parse_channel_tabs(ok).unwrap().len(), 2);
        assert!(parse_channel_tabs("{}").is_err());
        assert!(parse_channel_tabs(r#"[{"id":"a","type":"link","title":"A","value":""},{"id":"a","type":"link","title":"B","value":""}]"#).is_err());
        assert!(
            parse_channel_tabs(r#"[{"id":"bad id","type":"link","title":"A","value":""}]"#)
                .is_err()
        );
        let long_title = format!(
            r#"[{{"id":"a","type":"link","title":"{}","value":""}}]"#,
            "t".repeat(41)
        );
        assert!(parse_channel_tabs(&long_title).is_err());
        let many = format!(
            "[{}]",
            (0..51)
                .map(|i| format!(r#"{{"id":"t{i}","type":"link","title":"T","value":""}}"#))
                .collect::<Vec<_>>()
                .join(",")
        );
        assert!(parse_channel_tabs(&many).is_err());
        assert!(parse_channel_tabs(&" ".repeat(16_385)).is_err());
    }

    #[test]
    fn canvas_d_tag_binds_channel_and_id() {
        let ch = "11111111-1111-4111-8111-111111111111";
        assert_eq!(
            parse_canvas_d_tag(&format!("{ch}:notes_1"), ch).unwrap(),
            "notes_1"
        );
        assert!(parse_canvas_d_tag("22222222-2222-4222-8222-222222222222:notes", ch).is_err());
        assert!(parse_canvas_d_tag(&format!("{ch}:"), ch).is_err());
        assert!(parse_canvas_d_tag(&format!("{ch}:bad id"), ch).is_err());
    }
}
