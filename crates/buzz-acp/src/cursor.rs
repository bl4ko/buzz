//! Durable per-channel cursor of handled events. A restarted harness resumes
//! each channel from its cursor instead of the startup watermark.

use std::collections::{HashMap, VecDeque};
use std::io::Write;
use std::path::PathBuf;
use std::time::Duration;

use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use uuid::Uuid;

use crate::queue::EventQueue;
use crate::relay::BuzzEvent;
use crate::scope::SessionScope;

const MAX_FILE_BYTES: u64 = 1024 * 1024;
const MAX_CHANNELS: usize = 512;
const MAX_IDS_PER_CHANNEL: usize = 256;
const MAX_OPEN_PER_SCOPE: usize = 512;
const MAX_BACKLOG_EVENTS: usize = 2_000;
const MISSED_PER_CHANNEL_LIMIT: usize = 20;
const ID_RETAIN_SECS: u64 = crate::REPLAY_FLOOR_MAX_AGE_SECS + 60;
const BACKLOG_SETTLE: Duration = Duration::from_secs(2);

#[derive(Clone, Default, Serialize, Deserialize)]
struct ChannelCursor {
    ts: u64,
    #[serde(default)]
    ids: VecDeque<(u64, String)>,
}

#[derive(Default, Serialize, Deserialize)]
struct CursorFile {
    channels: HashMap<Uuid, ChannelCursor>,
}

/// Handled-event cursor for every subscribed channel.
///
/// `ts` is the newest event seen in a channel; the saved value stops one
/// second before the oldest event that is still queued or in flight, so an
/// interrupted turn is replayed. `ids` are the handled events at or after the
/// saved value, which a replay must skip.
pub(crate) struct Cursor {
    path: Option<PathBuf>,
    started_at: u64,
    max_age_secs: u64,
    channels: HashMap<Uuid, ChannelCursor>,
    open: HashMap<SessionScope, Vec<(u64, String)>>,
    missed: HashMap<Uuid, usize>,
    backlog: VecDeque<BuzzEvent>,
    collect_until: Option<tokio::time::Instant>,
    dirty: bool,
}

/// Default cursor file: one per relay and agent key under the agent's home.
pub(crate) fn default_path(relay_url: &str, pubkey_hex: &str) -> Option<PathBuf> {
    let home = std::env::var_os("HOME").or_else(|| std::env::var_os("USERPROFILE"))?;
    let digest = Sha256::digest(format!("{relay_url}\n{pubkey_hex}"));
    let name = format!("cursor-{}.json", hex::encode(&digest[..8]));
    Some(PathBuf::from(home).join(".buzz-acp").join(name))
}

impl Cursor {
    pub(crate) fn load(path: Option<PathBuf>, started_at: u64, max_age_secs: u64) -> Self {
        let mut cursor = Self {
            path: path.filter(|_| max_age_secs > 0),
            started_at,
            max_age_secs,
            channels: HashMap::new(),
            open: HashMap::new(),
            missed: HashMap::new(),
            backlog: VecDeque::new(),
            collect_until: None,
            dirty: false,
        };
        let Some(path) = cursor.path.clone() else {
            return cursor;
        };
        match read_file(&path) {
            Ok(Some(file)) => cursor.channels = file.channels,
            Ok(None) => {}
            Err(error) => {
                tracing::warn!(path = %path.display(), %error, "cursor unreadable — starting without it");
            }
        }
        tracing::info!(path = %path.display(), channels = cursor.channels.len(), "cursor loaded");
        if !cursor.save() {
            tracing::warn!(path = %path.display(), "cursor not writable — missed-message replay disabled");
            cursor.path = None;
            cursor.channels.clear();
        }
        cursor
    }

    fn enabled(&self) -> bool {
        self.path.is_some()
    }

    /// Replay start for a channel subscribed at startup; `None` keeps the
    /// startup watermark. The channel is tracked from now on either way.
    pub(crate) fn resume(&mut self, channel: Uuid, startup_watermark: u64) -> Option<u64> {
        if !self.enabled() {
            return None;
        }
        let oldest = self.started_at.saturating_sub(self.max_age_secs);
        if let Some(cursor) = self.channels.get(&channel) {
            return Some(cursor.ts.max(oldest).min(startup_watermark));
        }
        self.track(channel, startup_watermark);
        None
    }

    pub(crate) fn track(&mut self, channel: Uuid, ts: u64) {
        if !self.enabled() || self.channels.contains_key(&channel) {
            return;
        }
        while self.channels.len() >= MAX_CHANNELS {
            let Some(stale) = self
                .channels
                .iter()
                .min_by_key(|(_, c)| c.ts)
                .map(|(id, _)| *id)
            else {
                break;
            };
            self.channels.remove(&stale);
        }
        let ts = ts.min(unix_now());
        self.channels.insert(
            channel,
            ChannelCursor {
                ts,
                ids: VecDeque::new(),
            },
        );
        self.dirty = true;
    }

    pub(crate) fn forget(&mut self, channel: Uuid) {
        self.dirty |= self.channels.remove(&channel).is_some();
        self.open.retain(|scope, _| scope.channel_id() != channel);
        self.missed.remove(&channel);
    }

    /// Hold startup events for a short time so the replay is handled oldest first.
    pub(crate) fn collect_backlog(&mut self) {
        self.collect_until = Some(tokio::time::Instant::now() + BACKLOG_SETTLE);
    }

    pub(crate) async fn next_event(
        &mut self,
        mut recv: impl AsyncFnMut() -> Option<BuzzEvent>,
    ) -> Option<BuzzEvent> {
        loop {
            let Some(deadline) = self.collect_until else {
                return match self.backlog.pop_front() {
                    Some(event) => Some(event),
                    None => recv().await,
                };
            };
            match tokio::time::timeout_at(deadline, recv()).await {
                Ok(Some(event)) => {
                    self.backlog.push_back(event);
                    if self.backlog.len() >= MAX_BACKLOG_EVENTS {
                        self.release_backlog();
                    }
                }
                Ok(None) => return None,
                Err(_) => self.release_backlog(),
            }
        }
    }

    fn release_backlog(&mut self) {
        self.collect_until = None;
        self.backlog
            .make_contiguous()
            .sort_by_key(|event| event.event.created_at);
    }

    pub(crate) fn is_missed(&self, event: &nostr::Event) -> bool {
        self.enabled() && event.created_at.as_secs() < self.started_at
    }

    /// Record that an event was seen. Returns `false` for an event that was
    /// already handled, which the caller must drop.
    pub(crate) fn observe(&mut self, event: &BuzzEvent) -> bool {
        if !self.enabled() {
            return true;
        }
        let ts = event.event.created_at.as_secs();
        self.track(event.channel_id, ts);
        let Some(cursor) = self.channels.get_mut(&event.channel_id) else {
            return true;
        };
        let id = event.event.id.to_hex();
        if cursor.ids.iter().any(|(_, handled)| *handled == id) {
            return false;
        }
        let ts = ts.min(unix_now());
        if ts > cursor.ts {
            cursor.ts = ts;
            self.dirty = true;
        }
        true
    }

    /// Age and count limits for an answerable event from before startup.
    pub(crate) fn admit_missed(&mut self, event: &BuzzEvent) -> bool {
        if !self.is_missed(&event.event) {
            return true;
        }
        let age = self.started_at - event.event.created_at.as_secs();
        if age > self.max_age_secs {
            return false;
        }
        let count = self.missed.entry(event.channel_id).or_default();
        *count += 1;
        if *count == MISSED_PER_CHANNEL_LIMIT + 1 {
            tracing::warn!(
                channel_id = %event.channel_id,
                limit = MISSED_PER_CHANNEL_LIMIT,
                "missed-message limit reached — dropping the newer missed messages"
            );
        }
        *count <= MISSED_PER_CHANNEL_LIMIT
    }

    /// Track an admitted event until the queue no longer holds it.
    pub(crate) fn admit(&mut self, scope: &SessionScope, event: &nostr::Event, queued: bool) {
        if !self.enabled() {
            return;
        }
        let entry = (event.created_at.as_secs(), event.id.to_hex());
        if !queued {
            self.handled(scope.channel_id(), entry);
            return;
        }
        let open = self.open.entry(scope.clone()).or_default();
        open.push(entry);
        if open.len() > MAX_OPEN_PER_SCOPE {
            let dropped = open.remove(0);
            self.handled(scope.channel_id(), dropped);
        }
    }

    fn handled(&mut self, channel: Uuid, entry: (u64, String)) {
        let Some(cursor) = self.channels.get_mut(&channel) else {
            return;
        };
        cursor.ids.push_back(entry);
        while cursor.ids.len() > MAX_IDS_PER_CHANNEL {
            cursor.ids.pop_front();
        }
        self.dirty = true;
    }

    /// Mark every tracked event that left the queue as handled, then save.
    pub(crate) fn reconcile(&mut self, queue: &EventQueue) {
        let mut settled = Vec::new();
        self.open.retain(|scope, events| {
            if queue.is_scope_in_flight(scope) {
                return true;
            }
            events.retain(|(ts, id)| {
                let held = queue.holds(scope, id);
                if !held {
                    settled.push((scope.channel_id(), (*ts, id.clone())));
                }
                held
            });
            !events.is_empty()
        });
        for (channel, entry) in settled {
            self.handled(channel, entry);
        }
        self.flush();
    }

    pub(crate) fn flush(&mut self) {
        if self.dirty {
            self.save();
        }
    }

    fn save(&mut self) -> bool {
        let Some(path) = self.path.clone() else {
            return false;
        };
        let mut file = CursorFile {
            channels: self.channels.clone(),
        };
        for (scope, events) in &self.open {
            let Some(cursor) = file.channels.get_mut(&scope.channel_id()) else {
                continue;
            };
            for (ts, _) in events {
                cursor.ts = cursor.ts.min(ts.saturating_sub(1));
            }
        }
        for cursor in file.channels.values_mut() {
            let floor = cursor.ts;
            cursor
                .ids
                .retain(|(ts, _)| ts.saturating_add(ID_RETAIN_SECS) >= floor);
        }
        let tmp = path.with_extension("tmp");
        let written = serde_json::to_vec(&file)
            .map_err(std::io::Error::other)
            .and_then(|bytes| {
                if let Some(dir) = path.parent() {
                    std::fs::create_dir_all(dir)?;
                }
                let mut out = std::fs::File::create(&tmp)?;
                out.write_all(&bytes)?;
                out.sync_all()?;
                std::fs::rename(&tmp, &path)
            });
        match written {
            Ok(()) => {
                self.dirty = false;
                tracing::info!(path = %path.display(), channels = file.channels.len(), "cursor saved");
                true
            }
            Err(error) => {
                self.dirty = true;
                tracing::warn!(path = %path.display(), %error, "cursor save failed — retrying on the next change");
                false
            }
        }
    }
}

fn read_file(path: &std::path::Path) -> std::io::Result<Option<CursorFile>> {
    let size = match std::fs::metadata(path) {
        Ok(meta) => meta.len(),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(None),
        Err(error) => return Err(error),
    };
    if size > MAX_FILE_BYTES {
        return Err(std::io::Error::other(format!(
            "{size} bytes exceeds the cursor size limit"
        )));
    }
    let file = serde_json::from_slice(&std::fs::read(path)?).map_err(std::io::Error::other)?;
    Ok(Some(file))
}

fn unix_now() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::DedupMode;
    use crate::queue::QueuedEvent;
    use nostr::{EventBuilder, Keys, Kind, Timestamp};

    const DAY: u64 = 86_400;
    const START: u64 = 2_000_000;

    fn event_at(channel_id: Uuid, ts: u64) -> BuzzEvent {
        let event = EventBuilder::new(Kind::Custom(9), format!("m{ts}"))
            .custom_created_at(Timestamp::from(ts))
            .sign_with_keys(&Keys::generate())
            .expect("sign test event");
        BuzzEvent {
            connection_generation: 0,
            channel_id,
            event,
        }
    }

    fn conversation(channel_id: Uuid) -> SessionScope {
        SessionScope::Conversation { channel_id }
    }

    fn thread(channel_id: Uuid, root: &str) -> SessionScope {
        SessionScope::Thread {
            channel_id,
            root_event_id: root.into(),
        }
    }

    fn file(dir: &tempfile::TempDir) -> Option<PathBuf> {
        Some(dir.path().join("state").join("cursor.json"))
    }

    fn admit(cursor: &mut Cursor, queue: &mut EventQueue, scope: &SessionScope, event: &BuzzEvent) {
        assert!(cursor.observe(event));
        let queued = queue.push(QueuedEvent {
            channel_id: event.channel_id,
            scope: scope.clone(),
            event: event.event.clone(),
            received_at: std::time::Instant::now(),
            prompt_tag: "test".into(),
            edit: None,
        });
        cursor.admit(scope, &event.event, queued);
    }

    #[test]
    fn first_start_keeps_the_startup_watermark_then_tracks_the_channel() {
        let dir = tempfile::tempdir().expect("tempdir");
        let channel = Uuid::new_v4();
        let mut cursor = Cursor::load(file(&dir), START, DAY);
        assert_eq!(cursor.resume(channel, START), None);
        cursor.flush();

        let mut restarted = Cursor::load(file(&dir), START + 600, DAY);
        assert_eq!(restarted.resume(channel, START + 600), Some(START));
    }

    #[test]
    fn restart_resumes_from_the_cursor_and_skips_handled_events() {
        let dir = tempfile::tempdir().expect("tempdir");
        let channel = Uuid::new_v4();
        let scope = conversation(channel);
        let handled = event_at(channel, START + 10);
        let same_second = event_at(channel, START + 10);
        let mut queue = EventQueue::new(DedupMode::Queue);
        let mut cursor = Cursor::load(file(&dir), START, DAY);
        cursor.resume(channel, START);

        admit(&mut cursor, &mut queue, &scope, &handled);
        let batch = queue.flush_next().expect("batch");
        assert_eq!(batch.events.len(), 1);
        cursor.reconcile(&queue);
        queue.mark_complete(&scope);
        cursor.reconcile(&queue);

        let mut restarted = Cursor::load(file(&dir), START + 600, DAY);
        assert_eq!(restarted.resume(channel, START + 600), Some(START + 10));
        assert!(
            !restarted.observe(&handled),
            "a handled event must not be answered again"
        );
        assert!(
            restarted.observe(&same_second),
            "an unseen event of the same second is new"
        );
    }

    #[test]
    fn unfinished_event_holds_the_saved_cursor_back() {
        let dir = tempfile::tempdir().expect("tempdir");
        let channel = Uuid::new_v4();
        let slow = thread(channel, "slow");
        let fast = thread(channel, "fast");
        let interrupted = event_at(channel, START + 10);
        let answered = event_at(channel, START + 20);
        let mut queue = EventQueue::new(DedupMode::Queue);
        let mut cursor = Cursor::load(file(&dir), START, DAY);
        cursor.resume(channel, START);

        admit(&mut cursor, &mut queue, &slow, &interrupted);
        admit(&mut cursor, &mut queue, &fast, &answered);
        queue.flush_next().expect("first batch");
        queue.flush_next().expect("second batch");
        queue.mark_complete(&fast);
        cursor.reconcile(&queue);

        let mut restarted = Cursor::load(file(&dir), START + 600, DAY);
        assert_eq!(restarted.resume(channel, START + 600), Some(START + 9));
        assert!(
            restarted.observe(&interrupted),
            "the interrupted turn is replayed"
        );
        assert!(!restarted.observe(&answered));
    }

    #[test]
    fn requeued_and_queued_events_stay_open() {
        let dir = tempfile::tempdir().expect("tempdir");
        let channel = Uuid::new_v4();
        let scope = conversation(channel);
        let retried = event_at(channel, START + 10);
        let mut queue = EventQueue::new(DedupMode::Queue);
        let mut cursor = Cursor::load(file(&dir), START, DAY);
        cursor.resume(channel, START);

        admit(&mut cursor, &mut queue, &scope, &retried);
        let batch = queue.flush_next().expect("batch");
        assert!(queue.requeue(batch).is_none());
        queue.mark_complete(&scope);
        cursor.reconcile(&queue);

        let mut restarted = Cursor::load(file(&dir), START + 600, DAY);
        assert_eq!(restarted.resume(channel, START + 600), Some(START + 9));
        assert!(restarted.observe(&retried));
    }

    #[test]
    fn missed_events_have_an_age_limit_and_a_count_limit() {
        let dir = tempfile::tempdir().expect("tempdir");
        let channel = Uuid::new_v4();
        let mut cursor = Cursor::load(file(&dir), START, DAY);
        cursor.resume(channel, START);
        cursor.flush();

        let now = START + 3 * DAY;
        let mut restarted = Cursor::load(file(&dir), now, DAY);
        assert_eq!(restarted.resume(channel, now), Some(now - DAY));
        assert!(!restarted.admit_missed(&event_at(channel, now - DAY - 1)));
        for n in 0..MISSED_PER_CHANNEL_LIMIT as u64 {
            assert!(restarted.admit_missed(&event_at(channel, now - 100 + n)));
        }
        assert!(!restarted.admit_missed(&event_at(channel, now - 1)));
        assert!(
            restarted.admit_missed(&event_at(channel, now)),
            "a live event has no limit"
        );
        assert!(restarted.admit_missed(&event_at(Uuid::new_v4(), now - 1)));
    }

    #[test]
    fn unwritable_or_disabled_cursor_changes_nothing() {
        let dir = tempfile::tempdir().expect("tempdir");
        let blocker = dir.path().join("not-a-dir");
        std::fs::write(&blocker, b"x").expect("write blocker");
        let channel = Uuid::new_v4();
        let old = event_at(channel, START - 10);
        for mut cursor in [
            Cursor::load(Some(blocker.join("cursor.json")), START, DAY),
            Cursor::load(file(&dir), START, 0),
            Cursor::load(None, START, DAY),
        ] {
            assert_eq!(cursor.resume(channel, START), None);
            assert!(cursor.observe(&old));
            assert!(!cursor.is_missed(&old.event));
            assert!(cursor.admit_missed(&old));
            cursor.flush();
        }
        assert!(!dir.path().join("state").exists());
    }

    #[test]
    fn corrupt_or_oversized_file_is_replaced() {
        let dir = tempfile::tempdir().expect("tempdir");
        let path = dir.path().join("cursor.json");
        let channel = Uuid::new_v4();
        for bytes in [
            b"{not json".to_vec(),
            vec![b' '; MAX_FILE_BYTES as usize + 1],
        ] {
            std::fs::write(&path, bytes).expect("write file");
            let mut cursor = Cursor::load(Some(path.clone()), START, DAY);
            assert_eq!(cursor.resume(channel, START), None);
            cursor.flush();
            let saved = std::fs::read(&path).expect("read saved cursor");
            assert!(serde_json::from_slice::<CursorFile>(&saved).is_ok());
            assert!(!path.with_extension("tmp").exists());
        }
    }

    #[test]
    fn removed_channel_and_future_timestamps_do_not_move_the_cursor() {
        let dir = tempfile::tempdir().expect("tempdir");
        let kept = Uuid::new_v4();
        let removed = Uuid::new_v4();
        let mut cursor = Cursor::load(file(&dir), START, DAY);
        cursor.resume(kept, START);
        cursor.resume(removed, START);
        assert!(cursor.observe(&event_at(kept, unix_now() + DAY)));
        cursor.forget(removed);
        cursor.flush();

        let now = unix_now() + 60;
        let mut restarted = Cursor::load(file(&dir), now, DAY);
        assert_eq!(restarted.resume(removed, now), None);
        let since = restarted
            .resume(kept, now)
            .expect("kept channel has a cursor");
        assert!(
            since < now,
            "a future created_at must not move the cursor past the time it was seen"
        );
    }

    #[tokio::test(start_paused = true)]
    async fn startup_backlog_is_released_oldest_first() {
        let channel = Uuid::new_v4();
        let (tx, mut rx) = tokio::sync::mpsc::channel(8);
        for ts in [START - 1, START - 30, START - 20] {
            tx.send(event_at(channel, ts)).await.expect("send");
        }
        let mut cursor = Cursor::load(None, START, DAY);
        cursor.collect_backlog();
        let mut order = Vec::new();
        for _ in 0..3 {
            let event = cursor
                .next_event(async || rx.recv().await)
                .await
                .expect("event");
            order.push(event.event.created_at.as_secs());
        }
        assert_eq!(order, [START - 30, START - 20, START - 1]);

        tx.send(event_at(channel, START - 40)).await.expect("send");
        let live = cursor
            .next_event(async || rx.recv().await)
            .await
            .expect("event");
        assert_eq!(
            live.event.created_at.as_secs(),
            START - 40,
            "no hold after the release"
        );
    }
}
