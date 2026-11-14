use std::collections::{HashMap, HashSet};

use serde::Serialize;

use crate::scope::SessionScope;

const COMPACTION_TITLE: &str = "Compact conversation";

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SessionContext {
    pub started_at: u64,
    pub last_turn_at: u64,
    pub turns: u32,
    pub used: Option<u64>,
    pub size: Option<u64>,
    pub compactions: u32,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub last_compaction: Option<Compaction>,
    #[serde(skip)]
    pub(crate) open_compactions: HashSet<String>,
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Compaction {
    pub at: u64,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub pre_tokens: Option<u64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub post_tokens: Option<u64>,
}

impl SessionContext {
    pub fn usage(&self) -> buzz_core::agent_turn_metric::ContextUsage {
        buzz_core::agent_turn_metric::ContextUsage {
            used: self.used,
            size: self.size,
            turns: self.turns,
            started_at: self.started_at,
            compactions: self.compactions,
        }
    }

    pub fn percent(&self) -> Option<u64> {
        match (self.used, self.size) {
            (Some(used), Some(size)) if size > 0 => Some((used * 100 + size / 2) / size),
            _ => None,
        }
    }
}

#[derive(Debug, Default)]
pub struct ContextTracker {
    sessions: HashMap<String, SessionContext>,
}

pub fn now_secs() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

impl ContextTracker {
    pub fn open(&mut self, session_id: &str, now: u64) {
        self.sessions.insert(
            session_id.to_owned(),
            SessionContext {
                started_at: now,
                last_turn_at: now,
                ..SessionContext::default()
            },
        );
    }

    fn entry(&mut self, session_id: &str, now: u64) -> &mut SessionContext {
        self.sessions
            .entry(session_id.to_owned())
            .or_insert_with(|| SessionContext {
                started_at: now,
                last_turn_at: now,
                ..SessionContext::default()
            })
    }

    pub fn record_turn(&mut self, session_id: &str, now: u64) {
        let ctx = self.entry(session_id, now);
        ctx.turns += 1;
        ctx.last_turn_at = now;
    }

    pub fn record_update(&mut self, params: &serde_json::Value, now: u64) {
        let Some(session_id) = params["sessionId"].as_str() else {
            return;
        };
        let update = &params["update"];
        match update["sessionUpdate"].as_str() {
            Some("usage_update") => {
                let ctx = self.entry(session_id, now);
                if let Some(used) = update["used"].as_u64() {
                    ctx.used = Some(used);
                }
                if let Some(size) = update["size"].as_u64().filter(|size| *size > 0) {
                    ctx.size = Some(size);
                }
            }
            Some("tool_call") | Some("tool_call_update") => {
                let Some(id) = update["toolCallId"].as_str() else {
                    return;
                };
                let is_compaction = update["title"].as_str() == Some(COMPACTION_TITLE)
                    || update
                        .pointer("/_meta/claudeCode/toolName")
                        .and_then(|v| v.as_str())
                        == Some("compact");
                let tracked = self
                    .sessions
                    .get(session_id)
                    .is_some_and(|ctx| ctx.open_compactions.contains(id));
                if !is_compaction && !tracked {
                    return;
                }
                let ctx = self.entry(session_id, now);
                match update["status"].as_str() {
                    Some("completed") => {
                        if ctx.open_compactions.remove(id) || update["sessionUpdate"] == "tool_call"
                        {
                            ctx.compactions += 1;
                            ctx.last_compaction = Some(Compaction {
                                at: now,
                                pre_tokens: update
                                    .pointer("/rawOutput/preTokens")
                                    .and_then(|v| v.as_u64()),
                                post_tokens: update
                                    .pointer("/rawOutput/postTokens")
                                    .and_then(|v| v.as_u64()),
                            });
                        }
                    }
                    Some("failed") => {
                        ctx.open_compactions.remove(id);
                    }
                    _ => {
                        ctx.open_compactions.insert(id.to_owned());
                    }
                }
            }
            _ => {}
        }
    }

    pub fn get(&self, session_id: &str) -> Option<&SessionContext> {
        self.sessions.get(session_id)
    }

    pub fn forget(&mut self, session_id: &str) {
        self.sessions.remove(session_id);
    }
}

fn scope_label(scope: &SessionScope, is_dm: bool) -> String {
    match scope {
        SessionScope::Conversation { .. } if is_dm => "this DM".to_owned(),
        SessionScope::Conversation { .. } => "this channel".to_owned(),
        SessionScope::Thread { root_event_id, .. } => {
            format!(
                "thread {}",
                root_event_id.chars().take(8).collect::<String>()
            )
        }
    }
}

fn group(n: u64) -> String {
    let digits = n.to_string();
    let mut out = String::with_capacity(digits.len() + digits.len() / 3);
    for (i, c) in digits.chars().enumerate() {
        if i > 0 && (digits.len() - i).is_multiple_of(3) {
            out.push(',');
        }
        out.push(c);
    }
    out
}

fn age(secs: u64) -> String {
    let (d, h, m) = (secs / 86_400, secs % 86_400 / 3600, secs % 3600 / 60);
    match (d, h) {
        (0, 0) => format!("{m} min"),
        (0, _) => format!("{h} h {m} min"),
        _ => format!("{d} d {h} h"),
    }
}

pub fn usage_line(ctx: &SessionContext) -> String {
    match (ctx.used, ctx.size, ctx.percent()) {
        (Some(used), Some(size), Some(pct)) => {
            format!("{} of {} tokens ({pct} %)", group(used), group(size))
        }
        (Some(used), _, _) => format!("{} tokens (window size not reported)", group(used)),
        _ => "not reported yet (the adapter reports it after a model call)".to_owned(),
    }
}

pub struct Report<'a> {
    pub scope: &'a SessionScope,
    pub is_dm: bool,
    pub harness: &'a str,
    pub context: Option<&'a SessionContext>,
    pub turn_running: bool,
    pub now: u64,
}

pub fn render_report(r: &Report<'_>) -> String {
    let label = scope_label(r.scope, r.is_dm);
    let Some(ctx) = r.context else {
        let hint = if r.scope.is_thread() && !r.is_dm {
            " Send `!context` as a reply in the thread of the session."
        } else {
            ""
        };
        return format!("Context of {label}: no session.{hint}");
    };
    let mut lines = vec![
        format!("Context of {label} ({}):", r.harness),
        format!("- Used: {}", usage_line(ctx)),
        format!(
            "- Session: {} turns, age {}",
            ctx.turns,
            age(r.now.saturating_sub(ctx.started_at))
        ),
    ];
    let compactions = match ctx.last_compaction {
        Some(Compaction {
            pre_tokens: Some(pre),
            post_tokens: Some(post),
            at,
        }) => format!(
            "- Compactions: {} (last {} ago: {} → {} tokens)",
            ctx.compactions,
            age(r.now.saturating_sub(at)),
            group(pre),
            group(post)
        ),
        Some(Compaction { at, .. }) => format!(
            "- Compactions: {} (last {} ago)",
            ctx.compactions,
            age(r.now.saturating_sub(at))
        ),
        None => format!("- Compactions: {}", ctx.compactions),
    };
    lines.push(compactions);
    if r.turn_running {
        lines.push("A turn runs now. The values are from the end of the last turn.".to_owned());
    }
    lines.join("\n")
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;
    use uuid::Uuid;

    fn update(session: &str, update: serde_json::Value) -> serde_json::Value {
        json!({"sessionId": session, "update": update})
    }

    #[test]
    fn usage_update_sets_used_and_size() {
        let mut t = ContextTracker::default();
        t.open("s", 100);
        t.record_update(
            &update(
                "s",
                json!({"sessionUpdate": "usage_update", "used": 50_000, "size": 200_000}),
            ),
            110,
        );
        let ctx = t.get("s").unwrap();
        assert_eq!(
            (ctx.used, ctx.size, ctx.percent()),
            (Some(50_000), Some(200_000), Some(25))
        );
        t.record_update(
            &update(
                "s",
                json!({"sessionUpdate": "usage_update", "used": 1000, "size": 0}),
            ),
            120,
        );
        assert_eq!(t.get("s").unwrap().size, Some(200_000));
    }

    #[test]
    fn claude_compaction_counts_once_on_completion() {
        let mut t = ContextTracker::default();
        t.open("s", 0);
        t.record_update(
            &update("s", json!({"sessionUpdate": "tool_call", "toolCallId": "c1", "title": "Compact conversation", "kind": "think", "status": "in_progress", "_meta": {"claudeCode": {"toolName": "compact"}}})),
            1,
        );
        t.record_update(
            &update("s", json!({"sessionUpdate": "tool_call_update", "toolCallId": "c1", "status": "in_progress"})),
            2,
        );
        assert_eq!(t.get("s").unwrap().compactions, 0);
        let done = update(
            "s",
            json!({"sessionUpdate": "tool_call_update", "toolCallId": "c1", "status": "completed", "rawOutput": {"trigger": "manual", "preTokens": 150_000, "postTokens": 20_000}, "_meta": {"claudeCode": {"toolName": "compact"}}}),
        );
        t.record_update(&done, 3);
        t.record_update(&done, 4);
        let ctx = t.get("s").unwrap();
        assert_eq!(ctx.compactions, 1);
        assert_eq!(
            ctx.last_compaction,
            Some(Compaction {
                at: 3,
                pre_tokens: Some(150_000),
                post_tokens: Some(20_000)
            })
        );
    }

    #[test]
    fn codex_compaction_and_first_report_count() {
        let mut t = ContextTracker::default();
        t.record_update(
            &update("s", json!({"sessionUpdate": "tool_call", "toolCallId": "x", "title": "Compact conversation", "status": "in_progress"})),
            1,
        );
        t.record_update(
            &update("s", json!({"sessionUpdate": "tool_call_update", "toolCallId": "x", "title": "Compact conversation", "status": "completed"})),
            2,
        );
        t.record_update(
            &update("s", json!({"sessionUpdate": "tool_call", "toolCallId": "y", "title": "Compact conversation", "status": "completed"})),
            3,
        );
        t.record_update(
            &update("s", json!({"sessionUpdate": "tool_call_update", "toolCallId": "other", "status": "completed"})),
            4,
        );
        assert_eq!(t.get("s").unwrap().compactions, 2);
    }

    #[test]
    fn failed_compaction_does_not_count() {
        let mut t = ContextTracker::default();
        t.record_update(
            &update("s", json!({"sessionUpdate": "tool_call", "toolCallId": "c", "title": "Compact conversation", "status": "in_progress"})),
            1,
        );
        t.record_update(
            &update(
                "s",
                json!({"sessionUpdate": "tool_call_update", "toolCallId": "c", "status": "failed"}),
            ),
            2,
        );
        t.record_update(
            &update("s", json!({"sessionUpdate": "tool_call_update", "toolCallId": "c", "status": "completed"})),
            3,
        );
        assert_eq!(t.get("s").unwrap().compactions, 0);
    }

    #[test]
    fn report_shows_facts_and_no_session() {
        let ch = Uuid::new_v4();
        let dm = SessionScope::Conversation { channel_id: ch };
        let ctx = SessionContext {
            started_at: 1000,
            last_turn_at: 4000,
            turns: 7,
            used: Some(84_312),
            size: Some(200_000),
            compactions: 1,
            last_compaction: Some(Compaction {
                at: 4600,
                pre_tokens: Some(180_204),
                post_tokens: Some(21_330),
            }),
            ..SessionContext::default()
        };
        let text = render_report(&Report {
            scope: &dm,
            is_dm: true,
            harness: "claude-agent-acp",
            context: Some(&ctx),
            turn_running: true,
            now: 1000 + 3 * 3600 + 12 * 60,
        });
        assert_eq!(
            text,
            "Context of this DM (claude-agent-acp):\n- Used: 84,312 of 200,000 tokens (42 %)\n- Session: 7 turns, age 3 h 12 min\n- Compactions: 1 (last 2 h 12 min ago: 180,204 → 21,330 tokens)\nA turn runs now. The values are from the end of the last turn."
        );
        let thread = SessionScope::Thread {
            channel_id: ch,
            root_event_id: "ab".repeat(32),
        };
        let none = render_report(&Report {
            scope: &thread,
            is_dm: false,
            harness: "codex-acp",
            context: None,
            turn_running: false,
            now: 0,
        });
        assert_eq!(
            none,
            "Context of thread abababab: no session. Send `!context` as a reply in the thread of the session."
        );
    }

    #[test]
    fn report_without_usage_says_not_reported() {
        let ch = Uuid::new_v4();
        let scope = SessionScope::Conversation { channel_id: ch };
        let ctx = SessionContext {
            started_at: 0,
            ..SessionContext::default()
        };
        let text = render_report(&Report {
            scope: &scope,
            is_dm: false,
            harness: "codex-acp",
            context: Some(&ctx),
            turn_running: false,
            now: 30,
        });
        assert!(text.contains("- Used: not reported yet"), "{text}");
        assert!(text.contains("- Session: 0 turns, age 0 min"), "{text}");
    }
}
