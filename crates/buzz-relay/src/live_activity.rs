use std::{
    collections::{HashMap, HashSet},
    sync::Arc,
    time::Duration,
};

use buzz_core::CommunityId;
use buzz_db::live_activity::{LiveActivityLease, LiveActivityStateRow};
use chrono::{TimeDelta, Utc};
use serde::Deserialize;
use sha2::{Digest as _, Sha256};
use tracing::{error, info, warn};
use uuid::Uuid;

use crate::{nip98::nip98_header, state::AppState};

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct AskView {
    pub ask_event_id: String,
    pub case_id: Option<String>,
    pub ask: String,
    pub agent: String,
    pub channel: String,
    pub open_count: u16,
    pub asked_at: i64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum Action {
    None,
    Upsert { priority: u8 },
    End,
    Restart,
}

const HASH_DOMAIN: &[u8] = b"buzz.relay.la-state.v1\0";
const RESTART_AFTER_SECS: i64 = 7 * 60 * 60;
const NEW_ASK_RESTART_AFTER_SECS: i64 = 30 * 60;
const NOT_REGISTERED_RETRY_SECS: i64 = 6 * 60 * 60;
const MAX_CASE_ID_CHARS: usize = 96;

pub(crate) fn case_id_from_content(content: &str) -> Option<String> {
    let line = content.split('\n').next()?.trim();
    if let Some((id, status)) = line
        .strip_prefix("Case ")
        .and_then(|rest| rest.split_once(" | Status: "))
    {
        if valid_case_id(id) && !status.trim().is_empty() {
            return Some(id.to_owned());
        }
    }
    let (head, status) = line.split_once(" · ")?;
    if status.trim().is_empty() {
        return None;
    }
    let mut tokens: Vec<&str> = head.split(' ').collect();
    let id = tokens.pop()?;
    let mentions_ok = tokens
        .iter()
        .all(|token| token.len() > 1 && token.starts_with('@'));
    (mentions_ok && valid_case_id(id)).then(|| id.to_owned())
}

fn valid_case_id(id: &str) -> bool {
    let mut chars = id.chars();
    chars.next().is_some_and(|c| c.is_ascii_alphanumeric())
        && id.len() <= MAX_CASE_ID_CHARS
        && chars.all(|c| c.is_ascii_alphanumeric() || matches!(c, '.' | '_' | '-'))
}

pub(crate) fn cut_chars(text: &str, max: usize) -> String {
    if text.chars().count() <= max {
        return text.to_owned();
    }
    let mut cut: String = text.chars().take(max.saturating_sub(1)).collect();
    if max > 0 {
        cut.push('…');
    }
    cut
}

fn state_json(view: &AskView) -> serde_json::Value {
    serde_json::json!({
        "askEventID": view.ask_event_id,
        "caseID": view.case_id,
        "ask": view.ask,
        "agent": view.agent,
        "channel": view.channel,
        "openCount": view.open_count,
        "askedAt": view.asked_at,
    })
}

pub(crate) fn content_hash(view: &AskView) -> [u8; 32] {
    let mut hasher = Sha256::new();
    hasher.update(HASH_DOMAIN);
    hasher.update(state_json(view).to_string().as_bytes());
    hasher.finalize().into()
}

fn card_open(row: &LiveActivityStateRow) -> bool {
    matches!(row.result.as_str(), "started" | "updated" | "pending")
}

pub(crate) fn decide(
    previous: Option<&LiveActivityStateRow>,
    view: Option<&AskView>,
    refresh: bool,
    now: i64,
) -> Action {
    let Some(view) = view else {
        return if previous.is_some_and(card_open) {
            Action::End
        } else {
            Action::None
        };
    };
    let Some(previous) = previous else {
        return Action::Upsert { priority: 10 };
    };
    let open = card_open(previous);
    if open
        && previous
            .started_at
            .is_some_and(|started| now.saturating_sub(started) >= RESTART_AFTER_SECS)
    {
        return Action::Restart;
    }
    if previous.content_hash.as_slice() != content_hash(view).as_slice() {
        let shown = hex::decode(&view.ask_event_id).ok();
        if previous.ask_event_id == shown {
            return Action::Upsert { priority: 5 };
        }
        let new_ask = i32::from(view.open_count) > previous.open_count;
        let card_age = previous
            .started_at
            .map(|started| now.saturating_sub(started));
        if open && new_ask && card_age.is_some_and(|age| age >= NEW_ASK_RESTART_AFTER_SECS) {
            return Action::Restart;
        }
        return Action::Upsert { priority: 10 };
    }
    if refresh && open {
        Action::Upsert { priority: 5 }
    } else if refresh
        && previous.result == "not_registered"
        && now.saturating_sub(previous.last_sent_at) >= NOT_REGISTERED_RETRY_SECS
    {
        Action::Upsert { priority: 10 }
    } else {
        Action::None
    }
}

pub(crate) fn delivery_body(
    grant: &str,
    request_id: Uuid,
    expires_at: i64,
    origin: &str,
    action: &Action,
    view: Option<&AskView>,
) -> Option<serde_json::Value> {
    let (op, priority, state) = match action {
        Action::None => return None,
        Action::Upsert { priority } => ("upsert", *priority, view.map(state_json)?),
        Action::Restart => ("restart", 10, view.map(state_json)?),
        Action::End => ("end", 10, serde_json::Value::Null),
    };
    Some(serde_json::json!({
        "v": 1,
        "endpoint_grant": grant,
        "request_id": request_id,
        "expires_at": expires_at,
        "origin": origin,
        "op": op,
        "priority": priority,
        "state": state,
    }))
}

const CLAIM_SECS: i64 = 30;
const REQUEST_TTL_SECS: i64 = 300;
const SWEEP_INTERVAL: Duration = Duration::from_secs(600);
const IDLE_POLL_FLOOR: Duration = Duration::from_millis(250);
const IDLE_POLL_CEILING: Duration = Duration::from_secs(2);
const PENDING_RETRY: Duration = Duration::from_secs(15);
const MAX_PENDING_ATTEMPTS: i32 = 4;
const MAX_RETRY_ATTEMPTS: i32 = 8;
const RETRY_FLOOR_SECS: i64 = 5;
const RETRY_CEILING_SECS: i64 = 300;
const MAX_ASK_CHARS: usize = 120;
const MAX_LABEL_CHARS: usize = 64;
const MAX_OPEN_COUNT: i64 = 999;

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum GatewayReply {
    Started,
    Updated,
    Ended,
    Pending,
    NotRegistered,
    InvalidEndpoint { generation: i64 },
    Retry { after_seconds: Option<i64> },
    Failed,
}

#[async_trait::async_trait]
pub(crate) trait LiveActivityGateway: Send + Sync {
    async fn deliver(&self, body: Vec<u8>) -> GatewayReply;
}

#[derive(Deserialize)]
#[serde(rename_all = "snake_case", tag = "status")]
enum WireReply {
    Started,
    Updated,
    Ended,
    Pending,
    NotRegistered,
    InvalidEndpoint { generation: i64 },
    Retry { retry_after_seconds: Option<i64> },
}

impl From<WireReply> for GatewayReply {
    fn from(reply: WireReply) -> Self {
        match reply {
            WireReply::Started => Self::Started,
            WireReply::Updated => Self::Updated,
            WireReply::Ended => Self::Ended,
            WireReply::Pending => Self::Pending,
            WireReply::NotRegistered => Self::NotRegistered,
            WireReply::InvalidEndpoint { generation } => Self::InvalidEndpoint { generation },
            WireReply::Retry {
                retry_after_seconds,
            } => Self::Retry {
                after_seconds: retry_after_seconds,
            },
        }
    }
}

pub(crate) struct HttpLiveActivityGateway {
    http: reqwest::Client,
    url: url::Url,
    keys: nostr::Keys,
}

impl HttpLiveActivityGateway {
    pub(crate) fn new(http: reqwest::Client, url: url::Url, keys: nostr::Keys) -> Self {
        Self { http, url, keys }
    }
}

#[async_trait::async_trait]
impl LiveActivityGateway for HttpLiveActivityGateway {
    async fn deliver(&self, body: Vec<u8>) -> GatewayReply {
        let auth = match nip98_header(&self.keys, self.url.as_str(), &body) {
            Ok(auth) => auth,
            Err(error) => {
                warn!(%error, "live activity auth failed");
                return GatewayReply::Failed;
            }
        };
        let response = self
            .http
            .post(self.url.clone())
            .header("Authorization", auth)
            .header("Content-Type", "application/json")
            .body(body)
            .send()
            .await;
        let response = match response {
            Ok(response) => response,
            Err(error) if error.is_timeout() || error.is_connect() => {
                return GatewayReply::Retry {
                    after_seconds: None,
                }
            }
            Err(error) => {
                warn!(%error, "live activity gateway request failed");
                return GatewayReply::Failed;
            }
        };
        let status = response.status();
        match response.json::<WireReply>().await {
            Ok(reply) => reply.into(),
            Err(_)
                if status == reqwest::StatusCode::TOO_MANY_REQUESTS || status.is_server_error() =>
            {
                GatewayReply::Retry {
                    after_seconds: None,
                }
            }
            Err(_) => {
                warn!(%status, "live activity gateway rejected the request");
                GatewayReply::Failed
            }
        }
    }
}

#[derive(Debug, Clone, Default)]
pub(crate) struct CommunitySnapshot {
    pub origin: String,
    pub owners: HashSet<Vec<u8>>,
    pub leases: Vec<LiveActivityLease>,
    pub views: HashMap<Vec<u8>, AskView>,
    pub states: Vec<LiveActivityStateRow>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub(crate) struct JobOutcome {
    pub records: Vec<LiveActivityStateRow>,
    pub disable: Vec<(Vec<u8>, String, i64)>,
    pub retry_after: Option<Duration>,
}

fn retry_delay(after_seconds: Option<i64>, attempts: i32) -> Duration {
    let backoff = RETRY_FLOOR_SECS * (1_i64 << (attempts - 1).clamp(0, 6));
    let secs = after_seconds
        .filter(|secs| *secs > 0)
        .unwrap_or(backoff)
        .clamp(RETRY_FLOOR_SECS, RETRY_CEILING_SECS);
    Duration::from_secs(secs as u64)
}

fn reply_outcome(reply: &GatewayReply) -> &'static str {
    match reply {
        GatewayReply::Started => "started",
        GatewayReply::Updated => "updated",
        GatewayReply::Ended => "ended",
        GatewayReply::Pending => "pending",
        GatewayReply::NotRegistered => "not_registered",
        GatewayReply::InvalidEndpoint { .. } => "invalid_endpoint",
        GatewayReply::Retry { .. } => "retry",
        GatewayReply::Failed => "failed",
    }
}

fn record(
    lease: &LiveActivityLease,
    action: &Action,
    view: Option<&AskView>,
    result: &str,
    started_at: Option<i64>,
    now: i64,
) -> LiveActivityStateRow {
    let shown = match action {
        Action::End => None,
        _ => view,
    };
    LiveActivityStateRow {
        author: lease.author.clone(),
        installation_id: lease.installation_id.clone(),
        lease_generation: lease.generation,
        ask_event_id: shown.and_then(|view| hex::decode(&view.ask_event_id).ok()),
        open_count: shown.map_or(0, |view| i32::from(view.open_count)),
        content_hash: shown.map_or(vec![0; 32], |view| content_hash(view).to_vec()),
        result: result.to_owned(),
        started_at,
        last_sent_at: now,
    }
}

pub(crate) async fn run_job(
    snapshot: &CommunitySnapshot,
    refresh: bool,
    attempts: i32,
    now: i64,
    gateway: &dyn LiveActivityGateway,
) -> JobOutcome {
    let mut outcome = JobOutcome::default();
    for lease in snapshot
        .leases
        .iter()
        .filter(|lease| snapshot.owners.contains(&lease.author))
    {
        let previous = snapshot
            .states
            .iter()
            .find(|row| row.author == lease.author && row.installation_id == lease.installation_id);
        let view = snapshot.views.get(&lease.author);
        let action = decide(previous, view, refresh, now);
        let expires_at = lease.expires_at.min(now + REQUEST_TTL_SECS);
        let Some(body) = delivery_body(
            &lease.endpoint_grant,
            Uuid::new_v4(),
            expires_at,
            &snapshot.origin,
            &action,
            view,
        ) else {
            continue;
        };
        let reply = gateway.deliver(body.to_string().into_bytes()).await;
        metrics::counter!(
            "buzz_push_live_activity_deliveries_total",
            "outcome" => reply_outcome(&reply)
        )
        .increment(1);
        let kept_start = previous.and_then(|row| row.started_at).or(Some(now));
        match reply {
            GatewayReply::Started => {
                outcome
                    .records
                    .push(record(lease, &action, view, "started", Some(now), now))
            }
            GatewayReply::Updated => outcome
                .records
                .push(record(lease, &action, view, "updated", kept_start, now)),
            GatewayReply::Ended => {
                outcome
                    .records
                    .push(record(lease, &Action::End, view, "ended", None, now))
            }
            GatewayReply::NotRegistered => {
                outcome
                    .records
                    .push(record(lease, &action, view, "not_registered", None, now))
            }
            GatewayReply::Pending if attempts < MAX_PENDING_ATTEMPTS => {
                outcome.retry_after = outcome.retry_after.max(Some(PENDING_RETRY));
            }
            GatewayReply::Pending => outcome
                .records
                .push(record(lease, &action, view, "pending", kept_start, now)),
            GatewayReply::InvalidEndpoint { generation } => {
                if generation == lease.generation {
                    outcome.disable.push((
                        lease.author.clone(),
                        lease.installation_id.clone(),
                        generation,
                    ));
                }
            }
            GatewayReply::Retry { after_seconds } if attempts < MAX_RETRY_ATTEMPTS => {
                outcome.retry_after = outcome
                    .retry_after
                    .max(Some(retry_delay(after_seconds, attempts)));
            }
            GatewayReply::Retry { .. } | GatewayReply::Failed => {}
        }
    }
    outcome
}

pub(crate) fn origin_for(relay_url: &str, host: &str) -> Option<String> {
    let scheme = if relay_url.starts_with("wss://") {
        "https"
    } else if relay_url.starts_with("ws://") {
        "http"
    } else {
        return None;
    };
    (!host.is_empty()).then(|| format!("{scheme}://{}", host.to_ascii_lowercase()))
}

async fn ask_view(
    state: &AppState,
    community: CommunityId,
    summary: &buzz_db::live_activity::OwnerAskSummary,
) -> anyhow::Result<AskView> {
    let author_hex = hex::encode(&summary.status_author);
    let agent = state
        .db
        .get_user(community, &summary.status_author)
        .await?
        .and_then(|user| user.display_name)
        .map(|name| name.trim().to_owned())
        .filter(|name| !name.is_empty())
        .unwrap_or_else(|| author_hex[..8].to_owned());
    let channel = state
        .db
        .get_channel(community, summary.channel_id)
        .await
        .map(|channel| channel.name)
        .unwrap_or_default();
    Ok(AskView {
        ask_event_id: hex::encode(&summary.ask_event_id),
        case_id: case_id_from_content(&summary.ask_content),
        ask: cut_chars(&summary.ask_text, MAX_ASK_CHARS),
        agent: cut_chars(&agent, MAX_LABEL_CHARS),
        channel: cut_chars(&channel, MAX_LABEL_CHARS),
        open_count: summary.open_count.clamp(0, MAX_OPEN_COUNT) as u16,
        asked_at: summary.status_created_at,
    })
}

async fn load_snapshot(
    state: &AppState,
    community: CommunityId,
) -> anyhow::Result<Option<CommunitySnapshot>> {
    let Some(host) = state.db.lookup_community_host(community).await? else {
        return Ok(None);
    };
    let Some(origin) = origin_for(&state.config.relay_url, &host) else {
        return Ok(None);
    };
    let owners: HashSet<Vec<u8>> = state
        .db
        .list_relay_members(community)
        .await?
        .into_iter()
        .filter(|member| member.role == "owner")
        .filter_map(|member| hex::decode(&member.pubkey).ok())
        .collect();
    let owner_list: Vec<Vec<u8>> = owners.iter().cloned().collect();
    let leases = state
        .db
        .live_activity_leases(community, &owner_list)
        .await?;
    if leases.is_empty() {
        return Ok(Some(CommunitySnapshot {
            origin,
            owners,
            ..CommunitySnapshot::default()
        }));
    }
    let mut views = HashMap::new();
    for summary in state.db.owner_ask_summaries(community, &owner_list).await? {
        let view = ask_view(state, community, &summary).await?;
        views.insert(summary.owner, view);
    }
    let states = state.db.live_activity_states(community).await?;
    Ok(Some(CommunitySnapshot {
        origin,
        owners,
        leases,
        views,
        states,
    }))
}

fn record_job(result: &'static str) {
    metrics::counter!("buzz_push_live_activity_jobs_total", "result" => result).increment(1);
}

async fn process_job(
    state: &AppState,
    gateway: &dyn LiveActivityGateway,
    job: buzz_db::live_activity::ClaimedLiveActivityJob,
) {
    let community = job.community;
    let snapshot = match load_snapshot(state, community).await {
        Ok(Some(snapshot)) => snapshot,
        Ok(None) => {
            record_job("skipped");
            if let Err(e) = state
                .db
                .complete_live_activity_job(community, job.claim_id)
                .await
            {
                warn!(%community, "live activity job completion failed: {e}");
            }
            return;
        }
        Err(e) => {
            warn!(%community, "live activity snapshot failed: {e}");
            record_job("error");
            let result = if job.attempts >= MAX_RETRY_ATTEMPTS {
                state
                    .db
                    .complete_live_activity_job(community, job.claim_id)
                    .await
            } else {
                state
                    .db
                    .retry_live_activity_job(
                        community,
                        job.claim_id,
                        retry_delay(None, job.attempts),
                        job.refresh,
                    )
                    .await
            };
            if let Err(e) = result {
                warn!(%community, "live activity job release failed: {e}");
            }
            return;
        }
    };
    let outcome = run_job(
        &snapshot,
        job.refresh,
        job.attempts,
        Utc::now().timestamp(),
        gateway,
    )
    .await;
    for row in &outcome.records {
        if let Err(e) = state.db.record_live_activity_result(community, row).await {
            warn!(%community, "live activity result store failed: {e}");
        }
    }
    for (author, installation_id, generation) in &outcome.disable {
        if let Err(e) = state
            .db
            .disable_push_endpoint(community, author, installation_id, *generation)
            .await
        {
            warn!(%community, "live activity endpoint disable failed: {e}");
        }
    }
    let released = match outcome.retry_after {
        Some(delay) => {
            record_job("retried");
            state
                .db
                .retry_live_activity_job(community, job.claim_id, delay, job.refresh)
                .await
        }
        None => {
            record_job("completed");
            state
                .db
                .complete_live_activity_job(community, job.claim_id)
                .await
        }
    };
    if let Err(e) = released {
        warn!(%community, "live activity job release failed: {e}");
    }
}

/// Recompute owner approval cards and deliver changes through the push gateway.
pub async fn run_live_activity_worker(state: Arc<AppState>) {
    let Some(url) = state.config.push_live_activity_url() else {
        error!("live activity worker needs BUZZ_PUSH_GATEWAY_DELIVERY_URL");
        record_job("configuration_error");
        return;
    };
    let http = match reqwest::Client::builder()
        .timeout(state.config.push_gateway_timeout)
        .build()
    {
        Ok(http) => http,
        Err(e) => {
            error!("live activity HTTP client initialization failed: {e}");
            record_job("configuration_error");
            return;
        }
    };
    let gateway = HttpLiveActivityGateway::new(http, url, state.relay_keypair.clone());
    info!("approval live activity worker started");
    let mut last_sweep: Option<tokio::time::Instant> = None;
    let mut idle_delay = IDLE_POLL_FLOOR;
    loop {
        if last_sweep.is_none_or(|at| at.elapsed() >= SWEEP_INTERVAL) {
            match state
                .db
                .mark_live_activity_refresh_due(Utc::now().timestamp())
                .await
            {
                Ok(_) => last_sweep = Some(tokio::time::Instant::now()),
                Err(e) => warn!("live activity refresh sweep failed: {e}"),
            }
        }
        match state
            .db
            .claim_due_live_activity_job(Utc::now() + TimeDelta::seconds(CLAIM_SECS))
            .await
        {
            Ok(Some(job)) => {
                idle_delay = IDLE_POLL_FLOOR;
                process_job(&state, &gateway, job).await;
            }
            Ok(None) => {
                tokio::time::sleep(idle_delay).await;
                idle_delay = (idle_delay * 2).min(IDLE_POLL_CEILING);
            }
            Err(e) => {
                error!("live activity claim failed: {e}");
                tokio::time::sleep(IDLE_POLL_CEILING).await;
            }
        }
    }
}

#[cfg(test)]
#[path = "live_activity_e2e_postgres_tests.rs"]
mod live_activity_e2e_postgres_tests;

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    const NOW: i64 = 1_800_000_000;

    fn view(ask_event: char, open_count: u16) -> AskView {
        AskView {
            ask_event_id: ask_event.to_string().repeat(64),
            case_id: Some("BUZZ-1".to_owned()),
            ask: "Ship it?".to_owned(),
            agent: "Zeus".to_owned(),
            channel: "ops".to_owned(),
            open_count,
            asked_at: NOW - 30,
        }
    }

    fn row(view: Option<&AskView>, result: &str, started_at: Option<i64>) -> LiveActivityStateRow {
        LiveActivityStateRow {
            author: vec![1; 32],
            installation_id: "phone".to_owned(),
            lease_generation: 1,
            ask_event_id: view.map(|v| hex::decode(&v.ask_event_id).unwrap()),
            open_count: view.map_or(0, |v| i32::from(v.open_count)),
            content_hash: view.map_or(vec![0; 32], |v| content_hash(v).to_vec()),
            result: result.to_owned(),
            started_at,
            last_sent_at: NOW - 60,
        }
    }

    struct FakeGateway {
        replies: std::sync::Mutex<Vec<GatewayReply>>,
        bodies: std::sync::Mutex<Vec<serde_json::Value>>,
    }

    impl FakeGateway {
        fn new(replies: Vec<GatewayReply>) -> Self {
            Self {
                replies: std::sync::Mutex::new(replies),
                bodies: std::sync::Mutex::new(Vec::new()),
            }
        }

        fn bodies(&self) -> Vec<serde_json::Value> {
            self.bodies.lock().unwrap().clone()
        }
    }

    #[async_trait::async_trait]
    impl LiveActivityGateway for FakeGateway {
        async fn deliver(&self, body: Vec<u8>) -> GatewayReply {
            self.bodies
                .lock()
                .unwrap()
                .push(serde_json::from_slice(&body).unwrap());
            let mut replies = self.replies.lock().unwrap();
            if replies.is_empty() {
                GatewayReply::Failed
            } else {
                replies.remove(0)
            }
        }
    }

    fn lease(author: u8, grant: &str) -> LiveActivityLease {
        LiveActivityLease {
            author: vec![author; 32],
            installation_id: "phone".to_owned(),
            generation: 3,
            endpoint_grant: grant.to_owned(),
            expires_at: NOW + 86_400,
        }
    }

    fn snapshot(states: Vec<LiveActivityStateRow>) -> CommunitySnapshot {
        let mut views = HashMap::new();
        views.insert(vec![1; 32], view('a', 2));
        views.insert(vec![2; 32], view('b', 1));
        CommunitySnapshot {
            origin: "https://buzz.bl4ko.com".to_owned(),
            owners: HashSet::from([vec![1; 32]]),
            leases: vec![lease(1, "owner-grant"), lease(2, "member-grant")],
            views,
            states,
        }
    }

    fn stored(view: &AskView, result: &str) -> LiveActivityStateRow {
        LiveActivityStateRow {
            lease_generation: 3,
            ..row(Some(view), result, Some(NOW - 600))
        }
    }

    #[tokio::test]
    async fn worker_sends_upsert_for_owner_lease_only() {
        let gateway = FakeGateway::new(vec![GatewayReply::Started]);
        let outcome = run_job(&snapshot(Vec::new()), false, 1, NOW, &gateway).await;
        let bodies = gateway.bodies();
        assert_eq!(bodies.len(), 1);
        assert_eq!(bodies[0]["endpoint_grant"], "owner-grant");
        assert_eq!(bodies[0]["op"], "upsert");
        assert_eq!(bodies[0]["priority"], 10);
        assert_eq!(bodies[0]["origin"], "https://buzz.bl4ko.com");
        assert_eq!(bodies[0]["expires_at"], NOW + REQUEST_TTL_SECS);
        assert_eq!(bodies[0]["state"]["openCount"], 2);
        assert_eq!(bodies[0]["state"]["askEventID"], "a".repeat(64));
        let current = view('a', 2);
        assert_eq!(
            outcome,
            JobOutcome {
                records: vec![LiveActivityStateRow {
                    author: vec![1; 32],
                    installation_id: "phone".to_owned(),
                    lease_generation: 3,
                    ask_event_id: Some(vec![0xaa; 32]),
                    open_count: 2,
                    content_hash: content_hash(&current).to_vec(),
                    result: "started".to_owned(),
                    started_at: Some(NOW),
                    last_sent_at: NOW,
                }],
                disable: Vec::new(),
                retry_after: None,
            }
        );
    }

    #[tokio::test]
    async fn worker_skips_unchanged_state() {
        let gateway = FakeGateway::new(Vec::new());
        let states = vec![stored(&view('a', 2), "updated")];
        let outcome = run_job(&snapshot(states), false, 1, NOW, &gateway).await;
        assert!(gateway.bodies().is_empty());
        assert_eq!(outcome, JobOutcome::default());
    }

    #[tokio::test]
    async fn worker_requeues_pending() {
        let gateway = FakeGateway::new(vec![GatewayReply::Pending]);
        let outcome = run_job(&snapshot(Vec::new()), false, 1, NOW, &gateway).await;
        assert_eq!(gateway.bodies().len(), 1);
        assert!(outcome.records.is_empty());
        assert_eq!(outcome.retry_after, Some(PENDING_RETRY));

        let gateway = FakeGateway::new(vec![GatewayReply::Pending]);
        let outcome = run_job(
            &snapshot(Vec::new()),
            false,
            MAX_PENDING_ATTEMPTS,
            NOW,
            &gateway,
        )
        .await;
        assert_eq!(outcome.retry_after, None);
        assert_eq!(outcome.records.len(), 1);
        assert_eq!(outcome.records[0].result, "pending");
        assert_eq!(outcome.records[0].started_at, Some(NOW));
    }

    #[tokio::test]
    async fn worker_ends_card_when_no_ask_is_left() {
        let gateway = FakeGateway::new(vec![GatewayReply::Ended]);
        let mut input = snapshot(vec![stored(&view('a', 2), "updated")]);
        input.views.clear();
        let outcome = run_job(&input, false, 1, NOW, &gateway).await;
        let bodies = gateway.bodies();
        assert_eq!(bodies.len(), 1);
        assert_eq!(bodies[0]["op"], "end");
        assert_eq!(bodies[0]["state"], serde_json::Value::Null);
        assert_eq!(outcome.records.len(), 1);
        let ended = &outcome.records[0];
        assert_eq!(ended.result, "ended");
        assert_eq!(ended.open_count, 0);
        assert_eq!(ended.ask_event_id, None);
        assert_eq!(ended.started_at, None);
        assert_eq!(ended.content_hash, vec![0; 32]);
    }

    #[tokio::test]
    async fn worker_retries_with_backoff_and_disables_invalid_endpoint() {
        let gateway = FakeGateway::new(vec![GatewayReply::Retry {
            after_seconds: None,
        }]);
        let outcome = run_job(&snapshot(Vec::new()), false, 3, NOW, &gateway).await;
        assert_eq!(outcome.retry_after, Some(Duration::from_secs(20)));
        assert!(outcome.records.is_empty());
        let gateway = FakeGateway::new(vec![GatewayReply::Retry {
            after_seconds: Some(9_999),
        }]);
        let outcome = run_job(&snapshot(Vec::new()), false, 1, NOW, &gateway).await;
        assert_eq!(outcome.retry_after, Some(Duration::from_secs(300)));
        let gateway = FakeGateway::new(vec![GatewayReply::Retry {
            after_seconds: None,
        }]);
        let outcome = run_job(
            &snapshot(Vec::new()),
            false,
            MAX_RETRY_ATTEMPTS,
            NOW,
            &gateway,
        )
        .await;
        assert_eq!(outcome, JobOutcome::default());

        let gateway = FakeGateway::new(vec![GatewayReply::InvalidEndpoint { generation: 3 }]);
        let outcome = run_job(&snapshot(Vec::new()), false, 1, NOW, &gateway).await;
        assert_eq!(outcome.disable, vec![(vec![1; 32], "phone".to_owned(), 3)]);
        let gateway = FakeGateway::new(vec![GatewayReply::InvalidEndpoint { generation: 2 }]);
        let outcome = run_job(&snapshot(Vec::new()), false, 1, NOW, &gateway).await;
        assert!(outcome.disable.is_empty());
    }

    fn renewed(view: &AskView, result: &str) -> LiveActivityStateRow {
        LiveActivityStateRow {
            lease_generation: 2,
            ..stored(view, result)
        }
    }

    #[tokio::test]
    async fn worker_keeps_state_across_lease_generations() {
        let old = renewed(&view('a', 2), "updated");
        let gateway = FakeGateway::new(Vec::new());
        let outcome = run_job(&snapshot(vec![old.clone()]), false, 1, NOW, &gateway).await;
        assert!(gateway.bodies().is_empty());
        assert_eq!(outcome, JobOutcome::default());

        let gateway = FakeGateway::new(vec![GatewayReply::Updated]);
        let mut input = snapshot(vec![old.clone()]);
        input.views.insert(vec![1; 32], view('a', 3));
        let outcome = run_job(&input, false, 1, NOW, &gateway).await;
        assert_eq!(gateway.bodies()[0]["op"], "upsert");
        assert_eq!(gateway.bodies()[0]["priority"], 5);
        assert_eq!(outcome.records[0].result, "updated");
        assert_eq!(outcome.records[0].started_at, old.started_at);
        assert_eq!(outcome.records[0].lease_generation, 3);

        let aged = LiveActivityStateRow {
            started_at: Some(NOW - RESTART_AFTER_SECS),
            ..old
        };
        let gateway = FakeGateway::new(vec![GatewayReply::Started]);
        run_job(&snapshot(vec![aged]), false, 1, NOW, &gateway).await;
        assert_eq!(gateway.bodies()[0]["op"], "restart");
    }

    #[tokio::test]
    async fn worker_ends_card_after_lease_renewal() {
        let mut input = snapshot(vec![renewed(&view('a', 2), "updated")]);
        input.views.clear();
        let gateway = FakeGateway::new(vec![GatewayReply::Ended]);
        let outcome = run_job(&input, false, 1, NOW, &gateway).await;
        let bodies = gateway.bodies();
        assert_eq!(bodies.len(), 1);
        assert_eq!(bodies[0]["op"], "end");
        assert_eq!(bodies[0]["endpoint_grant"], "owner-grant");
        assert_eq!(outcome.records.len(), 1);
        assert_eq!(outcome.records[0].result, "ended");
        assert_eq!(outcome.records[0].lease_generation, 3);
    }

    #[test]
    fn origin_maps_relay_scheme_to_web_origin() {
        assert_eq!(
            origin_for("wss://relay.example", "Buzz.Bl4ko.com"),
            Some("https://buzz.bl4ko.com".to_owned())
        );
        assert_eq!(
            origin_for("ws://relay.example", "localhost:3000"),
            Some("http://localhost:3000".to_owned())
        );
        assert_eq!(origin_for("https://relay.example", "buzz.bl4ko.com"), None);
        assert_eq!(origin_for("wss://relay.example", ""), None);
    }

    async fn capture(
        axum::extract::State(seen): axum::extract::State<Arc<tokio::sync::Mutex<Vec<String>>>>,
        axum::extract::OriginalUri(uri): axum::extract::OriginalUri,
        headers: axum::http::HeaderMap,
        body: axum::body::Bytes,
    ) -> (axum::http::StatusCode, axum::Json<serde_json::Value>) {
        let url: url::Url = format!("http://{}{}", headers["host"].to_str().unwrap(), uri)
            .parse()
            .unwrap();
        let auth = headers["authorization"].to_str().unwrap().to_owned();
        nostr::nips::nip98::verify_auth_header(
            &auth,
            &url,
            nostr::nips::nip98::HttpMethod::POST,
            nostr::Timestamp::now(),
            Some(&body),
        )
        .unwrap();
        let mut seen = seen.lock().await;
        seen.push(auth);
        let (status, reply) = match seen.len() {
            1 => (200, json!({"status": "started"})),
            2 => (200, json!({"status": "not_registered"})),
            3 => (503, json!({"status": "retry", "retry_after_seconds": 7})),
            4 => (503, json!({"status": "retry", "retry_after_seconds": null})),
            5 => (503, json!({"error": "configuration_fault"})),
            6 => (503, json!({"error": "temporarily_unavailable"})),
            7 => (429, json!({"error": "rate_limited"})),
            8 => (404, json!({"error": "invalid_grant"})),
            9 => (401, json!({"error": "invalid_auth"})),
            _ => (400, json!({"error": "invalid_request"})),
        };
        (
            axum::http::StatusCode::from_u16(status).unwrap(),
            axum::Json(reply),
        )
    }

    #[tokio::test]
    async fn http_gateway_signs_requests_and_maps_replies() {
        let seen = Arc::new(tokio::sync::Mutex::new(Vec::new()));
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let address = listener.local_addr().unwrap();
        let server = tokio::spawn(std::future::IntoFuture::into_future(axum::serve(
            listener,
            axum::Router::new()
                .route("/v1/deliveries/live-activity", axum::routing::post(capture))
                .with_state(seen.clone()),
        )));
        let url: url::Url = format!("http://{address}/v1/deliveries/live-activity")
            .parse()
            .unwrap();
        let gateway =
            HttpLiveActivityGateway::new(reqwest::Client::new(), url, nostr::Keys::generate());
        let mut replies = Vec::new();
        for _ in 0..10 {
            replies.push(gateway.deliver(br#"{"v":1}"#.to_vec()).await);
        }
        server.abort();
        let retry = |after_seconds| GatewayReply::Retry { after_seconds };
        assert_eq!(
            replies,
            vec![
                GatewayReply::Started,
                GatewayReply::NotRegistered,
                retry(Some(7)),
                retry(None),
                retry(None),
                retry(None),
                retry(None),
                GatewayReply::Failed,
                GatewayReply::Failed,
                GatewayReply::Failed,
            ]
        );
        let auths = seen.lock().await;
        assert_eq!(auths.len(), 10);
        let distinct: HashSet<&String> = auths.iter().collect();
        assert_eq!(
            distinct.len(),
            10,
            "identical bodies must get distinct NIP-98 events"
        );
    }

    #[test]
    fn case_id_from_zeus_compact_header() {
        assert_eq!(
            case_id_from_content("@Zeus @Hermes BUZZ-42 · awaiting owner\nDetails"),
            Some("BUZZ-42".to_owned())
        );
        assert_eq!(
            case_id_from_content("infra.cert_renew-7 · blocked"),
            Some("infra.cert_renew-7".to_owned())
        );
    }

    #[test]
    fn case_id_from_explicit_header() {
        assert_eq!(
            case_id_from_content("Case OPS-9 | Status: awaiting_owner\nMore"),
            Some("OPS-9".to_owned())
        );
    }

    #[test]
    fn case_id_absent_for_plain_text() {
        for content in [
            "Please approve the deploy",
            "",
            "@Zeus · status",
            "-BAD · status",
            "BUZZ-1 ·",
            "BUZZ-1 · ",
            "Case OPS-9 | Status:",
            "Case  | Status: open",
            "first line\nBUZZ-1 · open",
            &format!("{} · open", "A".repeat(97)),
            "BUZ Z · open",
        ] {
            assert_eq!(case_id_from_content(content), None, "{content:?}");
        }
        assert_eq!(
            case_id_from_content(&format!("{} · open", "A".repeat(96))),
            Some("A".repeat(96))
        );
    }

    #[test]
    fn cut_keeps_120_multibyte_chars() {
        let text = "ž".repeat(120);
        assert_eq!(cut_chars(&text, 120), text);
        assert_eq!(cut_chars("short", 120), "short");
    }

    #[test]
    fn cut_121_chars_ends_with_ellipsis() {
        let text = format!("{}✅", "é".repeat(120));
        let cut = cut_chars(&text, 120);
        assert_eq!(cut.chars().count(), 120);
        assert_eq!(cut, format!("{}…", "é".repeat(119)));
    }

    #[test]
    fn decide_first_ask_upserts_priority_10() {
        let current = view('a', 1);
        assert_eq!(
            decide(None, Some(&current), false, NOW),
            Action::Upsert { priority: 10 }
        );
        let ended = row(None, "ended", None);
        assert_eq!(
            decide(Some(&ended), Some(&current), false, NOW),
            Action::Upsert { priority: 10 }
        );
    }

    #[test]
    fn decide_count_change_upserts_priority_5() {
        let before = view('a', 1);
        let previous = row(Some(&before), "updated", Some(NOW - 600));
        assert_eq!(
            decide(Some(&previous), Some(&view('a', 2)), false, NOW),
            Action::Upsert { priority: 5 }
        );
    }

    #[test]
    fn decide_new_shown_ask_upserts_priority_10() {
        let before = view('a', 2);
        let previous = row(Some(&before), "started", Some(NOW - 600));
        assert_eq!(
            decide(Some(&previous), Some(&view('b', 2)), false, NOW),
            Action::Upsert { priority: 10 }
        );
    }

    #[test]
    fn decide_unchanged_is_none() {
        let current = view('a', 1);
        for result in ["started", "updated", "pending", "not_registered"] {
            let previous = row(Some(&current), result, Some(NOW - 600));
            assert_eq!(
                decide(Some(&previous), Some(&current), false, NOW),
                Action::None,
                "{result}"
            );
        }
        let previous = row(Some(&current), "not_registered", None);
        assert_eq!(
            decide(Some(&previous), Some(&current), true, NOW),
            Action::None
        );
    }

    #[test]
    fn decide_retries_not_registered_after_6h_on_refresh() {
        let current = view('a', 1);
        let at = |last_sent_at| LiveActivityStateRow {
            last_sent_at,
            ..row(Some(&current), "not_registered", None)
        };
        let due = at(NOW - NOT_REGISTERED_RETRY_SECS);
        assert_eq!(
            decide(Some(&due), Some(&current), true, NOW),
            Action::Upsert { priority: 10 }
        );
        assert_eq!(decide(Some(&due), Some(&current), false, NOW), Action::None);
        let early = at(NOW - NOT_REGISTERED_RETRY_SECS + 1);
        assert_eq!(
            decide(Some(&early), Some(&current), true, NOW),
            Action::None
        );
        assert_eq!(decide(Some(&due), None, true, NOW), Action::None);
    }

    #[test]
    fn decide_zero_after_started_ends() {
        let before = view('a', 1);
        for result in ["started", "updated", "pending"] {
            let previous = row(Some(&before), result, Some(NOW - 600));
            assert_eq!(decide(Some(&previous), None, false, NOW), Action::End);
        }
    }

    #[test]
    fn decide_zero_without_card_is_none() {
        assert_eq!(decide(None, None, false, NOW), Action::None);
        assert_eq!(decide(None, None, true, NOW), Action::None);
        let before = view('a', 1);
        for result in ["ended", "not_registered"] {
            let previous = row(Some(&before), result, None);
            assert_eq!(decide(Some(&previous), None, true, NOW), Action::None);
        }
    }

    #[test]
    fn decide_refresh_resends_priority_5() {
        let current = view('a', 1);
        for result in ["started", "updated", "pending"] {
            let previous = row(Some(&current), result, Some(NOW - 600));
            assert_eq!(
                decide(Some(&previous), Some(&current), true, NOW),
                Action::Upsert { priority: 5 }
            );
        }
    }

    #[test]
    fn decide_new_ask_after_start_bound_restarts() {
        let before = view('a', 1);
        for result in ["started", "updated", "pending"] {
            let previous = row(
                Some(&before),
                result,
                Some(NOW - NEW_ASK_RESTART_AFTER_SECS),
            );
            assert_eq!(
                decide(Some(&previous), Some(&view('b', 2)), false, NOW),
                Action::Restart,
                "{result}"
            );
        }
    }

    #[test]
    fn decide_new_ask_inside_start_bound_updates() {
        let before = view('a', 1);
        let previous = row(
            Some(&before),
            "updated",
            Some(NOW - NEW_ASK_RESTART_AFTER_SECS + 1),
        );
        assert_eq!(
            decide(Some(&previous), Some(&view('b', 2)), false, NOW),
            Action::Upsert { priority: 10 }
        );
    }

    #[test]
    fn decide_old_card_without_a_new_ask_is_updated() {
        let before = view('b', 2);
        let previous = row(Some(&before), "updated", Some(NOW - 3600));
        assert_eq!(
            decide(Some(&previous), Some(&view('a', 1)), false, NOW),
            Action::Upsert { priority: 10 }
        );
        assert_eq!(
            decide(Some(&previous), Some(&view('b', 3)), false, NOW),
            Action::Upsert { priority: 5 }
        );
        assert_eq!(
            decide(Some(&previous), Some(&view('c', 2)), false, NOW),
            Action::Upsert { priority: 10 }
        );
        let ended = row(Some(&before), "ended", Some(NOW - 3600));
        assert_eq!(
            decide(Some(&ended), Some(&view('c', 3)), false, NOW),
            Action::Upsert { priority: 10 }
        );
    }

    #[test]
    fn decide_aged_7h_restarts() {
        let current = view('a', 1);
        let aged = row(Some(&current), "updated", Some(NOW - 7 * 3600));
        assert_eq!(
            decide(Some(&aged), Some(&current), true, NOW),
            Action::Restart
        );
        assert_eq!(
            decide(Some(&aged), Some(&view('b', 2)), false, NOW),
            Action::Restart
        );
        let young = row(Some(&current), "updated", Some(NOW - 7 * 3600 + 1));
        assert_eq!(
            decide(Some(&young), Some(&current), false, NOW),
            Action::None
        );
        let ended = row(None, "ended", Some(NOW - 9 * 3600));
        assert_eq!(
            decide(Some(&ended), Some(&current), false, NOW),
            Action::Upsert { priority: 10 }
        );
    }

    #[test]
    fn content_hash_tracks_every_field() {
        let base = view('a', 1);
        let mut variants = vec![view('b', 1), view('a', 2)];
        for change in 0..5 {
            let mut changed = base.clone();
            match change {
                0 => changed.case_id = None,
                1 => changed.ask.push('!'),
                2 => changed.agent.push('!'),
                3 => changed.channel.push('!'),
                _ => changed.asked_at += 1,
            }
            variants.push(changed);
        }
        for variant in variants {
            assert_ne!(content_hash(&base), content_hash(&variant), "{variant:?}");
        }
        assert_eq!(content_hash(&base), content_hash(&base.clone()));
    }

    #[test]
    fn delivery_body_matches_contract() {
        let request_id = Uuid::parse_str("6f9619ff-8b86-4011-b42d-00c04fc964ff").unwrap();
        let current = AskView {
            ask_event_id: "ab".repeat(32),
            case_id: Some("BUZZ-7".to_owned()),
            ask: "Deploy relay?".to_owned(),
            agent: "Zeus".to_owned(),
            channel: "ops".to_owned(),
            open_count: 3,
            asked_at: 1_760_000_000,
        };
        let state = json!({
            "askEventID": "ab".repeat(32),
            "caseID": "BUZZ-7",
            "ask": "Deploy relay?",
            "agent": "Zeus",
            "channel": "ops",
            "openCount": 3,
            "askedAt": 1_760_000_000,
        });
        let body = |action: Action, view: Option<&AskView>| {
            delivery_body(
                "grant",
                request_id,
                1_760_000_300,
                "https://buzz.bl4ko.com",
                &action,
                view,
            )
            .expect("delivery body")
        };
        let expected = |op: &str, priority: u8, state: serde_json::Value| {
            json!({
                "v": 1,
                "endpoint_grant": "grant",
                "request_id": "6f9619ff-8b86-4011-b42d-00c04fc964ff",
                "expires_at": 1_760_000_300,
                "origin": "https://buzz.bl4ko.com",
                "op": op,
                "priority": priority,
                "state": state,
            })
        };
        assert_eq!(
            body(Action::Upsert { priority: 10 }, Some(&current)),
            expected("upsert", 10, state.clone())
        );
        assert_eq!(
            body(Action::Upsert { priority: 5 }, Some(&current)),
            expected("upsert", 5, state.clone())
        );
        assert_eq!(
            body(Action::Restart, Some(&current)),
            expected("restart", 10, state.clone())
        );
        assert_eq!(
            body(Action::End, None),
            expected("end", 10, serde_json::Value::Null)
        );
        let mut no_case = current.clone();
        no_case.case_id = None;
        assert_eq!(
            body(Action::Upsert { priority: 10 }, Some(&no_case))["state"]["caseID"],
            serde_json::Value::Null
        );
        assert!(
            delivery_body("grant", request_id, 1, "o", &Action::None, Some(&current)).is_none()
        );
        assert!(delivery_body("grant", request_id, 1, "o", &Action::Restart, None).is_none());
    }
}
