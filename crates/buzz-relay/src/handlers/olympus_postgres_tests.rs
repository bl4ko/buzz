//! Postgres and Redis tests for the NIP-OL write and read rules, through the real ingest, REQ,
//! COUNT, HTTP bridge and fan-out handlers.

use std::sync::Arc;

use buzz_core::kind::{
    KIND_OLYMPUS_AGENT, KIND_OLYMPUS_CHANGE_REQUEST, KIND_OLYMPUS_CHANGE_RESULT,
    KIND_OLYMPUS_WORKSPACE,
};
use buzz_core::TenantContext;
use nostr::{Event, EventBuilder, Keys, Kind, Tag};
use serde_json::{json, Value};
use tokio::sync::mpsc::Receiver;
use uuid::Uuid;

use super::group_state_postgres_tests::test_conn;
use crate::handlers::ingest::{ingest_event, HttpAuthMethod, IngestAuth, IngestError};
use crate::state::AppState;

const ALL: [u32; 4] = [
    KIND_OLYMPUS_AGENT,
    KIND_OLYMPUS_WORKSPACE,
    KIND_OLYMPUS_CHANGE_REQUEST,
    KIND_OLYMPUS_CHANGE_RESULT,
];

struct Fixture {
    state: Arc<AppState>,
    tenant: TenantContext,
    host: String,
    owner: Keys,
    operator: Keys,
    member: Keys,
}

async fn fixture() -> Fixture {
    let state = crate::api::bridge::postgres_tests::bridge_handler_test_state()
        .await
        .expect("local Postgres and Redis");
    let host = format!("olympus-{}.local", Uuid::new_v4().simple());
    let community = state
        .db
        .ensure_configured_community(&host)
        .await
        .expect("ensure community")
        .id;
    let (owner, operator, member) = (Keys::generate(), Keys::generate(), Keys::generate());
    for (keys, role) in [(&owner, "owner"), (&operator, "admin"), (&member, "member")] {
        let _ = state
            .db
            .add_relay_member(
                community,
                &keys.public_key().to_hex(),
                role,
                None,
                &state.relay_keypair,
            )
            .await
            .expect("add relay member");
    }
    Fixture {
        tenant: TenantContext::resolved(community, &host),
        state,
        host,
        owner,
        operator,
        member,
    }
}

fn hex(keys: &Keys) -> String {
    keys.public_key().to_hex()
}

fn sign(keys: &Keys, kind: u32, content: &str, tags: &[[&str; 2]]) -> Event {
    EventBuilder::new(Kind::Custom(kind as u16), content)
        .tags(
            tags.iter()
                .map(|tag| Tag::parse(tag.iter().copied()).unwrap()),
        )
        .allow_self_tagging()
        .sign_with_keys(keys)
        .expect("sign")
}

async fn ingest(f: &Fixture, event: Event) -> Result<String, IngestError> {
    let auth = IngestAuth::Http {
        pubkey: event.pubkey,
        scopes: buzz_auth::Scope::all_known(),
        auth_method: HttpAuthMethod::Nip98,
    };
    let id = event.id.to_hex();
    let result = ingest_event(&f.state, &f.tenant, event, auth).await?;
    assert!(result.accepted, "not accepted: {}", result.message);
    Ok(id)
}

async fn accepted(f: &Fixture, event: Event) -> String {
    let kind = event.kind.as_u16();
    ingest(f, event)
        .await
        .unwrap_or_else(|error| panic!("kind:{kind} refused: {error:?}"))
}

fn rejected(result: Result<String, IngestError>) -> String {
    match result {
        Err(IngestError::Rejected(reason)) => reason,
        other => panic!("expected an invalid refusal, got {other:?}"),
    }
}

fn agent(f: &Fixture, author: &Keys, d: &str) -> Event {
    let (owner, operator) = (hex(&f.owner), hex(&f.operator));
    sign(
        author,
        KIND_OLYMPUS_AGENT,
        r#"{"v":1}"#,
        &[
            ["d", d],
            ["p", &owner],
            ["p", &operator],
            ["workspace", "dev"],
            ["status", "active"],
        ],
    )
}

fn workspace(f: &Fixture, author: &Keys, d: &str) -> Event {
    let (owner, operator) = (hex(&f.owner), hex(&f.operator));
    sign(
        author,
        KIND_OLYMPUS_WORKSPACE,
        r#"{"v":1}"#,
        &[
            ["d", d],
            ["p", &owner],
            ["p", &operator],
            ["status", "active"],
        ],
    )
}

fn request(f: &Fixture, author: &Keys) -> Event {
    sign(
        author,
        KIND_OLYMPUS_CHANGE_REQUEST,
        r#"{"v":1,"action":"suspend","workspace":"dev","agent":"proof"}"#,
        &[
            ["p", &hex(&f.operator)],
            ["workspace", "dev"],
            ["agent", "proof"],
            ["action", "suspend"],
        ],
    )
}

fn result(f: &Fixture, author: &Keys, request_id: &str) -> Event {
    let (owner, operator) = (hex(&f.owner), hex(&f.operator));
    sign(
        author,
        KIND_OLYMPUS_CHANGE_RESULT,
        r#"{"v":1,"status":"accepted"}"#,
        &[
            ["e", request_id],
            ["p", &owner],
            ["p", &operator],
            ["status", "accepted"],
            ["action", "suspend"],
        ],
    )
}

fn sample(f: &Fixture, author: &Keys, kind: u32) -> Event {
    let d = Uuid::new_v4().to_string();
    match kind {
        KIND_OLYMPUS_AGENT => agent(f, author, &d),
        KIND_OLYMPUS_WORKSPACE => workspace(f, author, &d),
        KIND_OLYMPUS_CHANGE_REQUEST => request(f, author),
        _ => result(f, author, &"ab".repeat(32)),
    }
}

/// Mutation: drop `olympus::authorize_author` from ingest → RED (member and stranger accepted).
#[tokio::test]
#[ignore = "requires Postgres and Redis"]
async fn olympus_writes_need_a_relay_owner_or_admin() {
    let f = fixture().await;
    let stranger = Keys::generate();
    for kind in ALL {
        for author in [&f.member, &stranger] {
            match ingest(&f, sample(&f, author, kind)).await {
                Err(IngestError::AuthFailed(reason)) => {
                    assert!(reason.contains("relay owner or admin"), "{reason}")
                }
                other => panic!("kind:{kind} by a non-admin: {other:?}"),
            }
        }
        for author in [&f.owner, &f.operator] {
            accepted(&f, sample(&f, author, kind)).await;
        }
    }
}

/// Mutation: drop `olympus::validate_envelope` from ingest → RED.
#[tokio::test]
#[ignore = "requires Postgres and Redis"]
async fn olympus_bad_shapes_are_refused_at_ingest() {
    let f = fixture().await;
    let (owner, operator) = (hex(&f.owner), hex(&f.operator));
    let h = Uuid::new_v4().to_string();
    let upper = owner.to_uppercase();
    let cases: [(u32, Vec<[&str; 2]>); 7] = [
        (KIND_OLYMPUS_AGENT, vec![["d", "a/b"], ["status", "active"]]),
        (
            KIND_OLYMPUS_AGENT,
            vec![["d", "a/b"], ["p", &upper], ["status", "active"]],
        ),
        (
            KIND_OLYMPUS_AGENT,
            vec![
                ["d", "a/b"],
                ["d", "a/c"],
                ["p", &owner],
                ["status", "active"],
            ],
        ),
        (KIND_OLYMPUS_WORKSPACE, vec![["d", "dev"], ["p", &owner]]),
        (
            KIND_OLYMPUS_WORKSPACE,
            vec![["d", "dev"], ["p", &owner], ["status", "active"], ["h", &h]],
        ),
        (
            KIND_OLYMPUS_CHANGE_REQUEST,
            vec![["p", &operator], ["p", &owner], ["action", "suspend"]],
        ),
        (
            KIND_OLYMPUS_CHANGE_RESULT,
            vec![["p", &owner], ["status", "accepted"]],
        ),
    ];
    for (kind, tags) in cases {
        let reason = rejected(ingest(&f, sign(&f.operator, kind, "", &tags)).await);
        assert!(
            reason.starts_with("invalid:"),
            "kind:{kind} {tags:?}: {reason}"
        );
    }
}

/// Mutation: drop the `k` tag check → RED on the first case; drop the target-kind check in
/// `validate_standard_deletion_event` → RED on the other two.
#[tokio::test]
#[ignore = "requires Postgres and Redis"]
async fn olympus_events_cannot_be_deleted_with_kind_5() {
    let f = fixture().await;
    let note = accepted(&f, sign(&f.operator, 1, "note", &[])).await;
    let agent_event = agent(&f, &f.operator, "olympus-dev/proof");
    let address = format!(
        "{KIND_OLYMPUS_AGENT}:{}:olympus-dev/proof",
        hex(&f.operator)
    );
    accepted(&f, agent_event).await;
    let result_id = accepted(&f, result(&f, &f.operator, &"cd".repeat(32))).await;

    let k = KIND_OLYMPUS_AGENT.to_string();
    for tags in [
        vec![["e", note.as_str()], ["k", &k]],
        vec![["e", result_id.as_str()]],
        vec![["a", address.as_str()]],
    ] {
        let reason = rejected(ingest(&f, sign(&f.operator, 5, "", &tags)).await);
        assert!(reason.contains("Olympus"), "{tags:?}: {reason}");
    }
    accepted(&f, sign(&f.operator, 5, "", &[["e", &note]])).await;
}

fn register_live(
    f: &Fixture,
    reader: &Keys,
    filter: Value,
) -> Receiver<axum::extract::ws::Message> {
    let conn_id = Uuid::new_v4();
    let (tx, rx) = tokio::sync::mpsc::channel(64);
    f.state.conn_manager.register(
        conn_id,
        tx,
        tokio::sync::mpsc::channel(4).0,
        tokio::sync::mpsc::channel(1).0,
        None,
        tokio_util::sync::CancellationToken::new(),
        f.tenant.community(),
        Arc::new(std::sync::atomic::AtomicU8::new(0)),
        Arc::new(tokio::sync::Mutex::new(Default::default())),
        3,
        crate::state::CommunityConnectionControl::new(tokio_util::sync::CancellationToken::new()),
    );
    f.state
        .conn_manager
        .set_authenticated_pubkey(conn_id, reader.public_key().to_bytes().to_vec());
    f.state.sub_registry.register_scoped(
        f.tenant.community(),
        conn_id,
        "live".into(),
        vec![serde_json::from_value(filter).expect("filter")],
        None,
    );
    rx
}

async fn live_ids(rx: &mut Receiver<axum::extract::ws::Message>) -> Vec<String> {
    tokio::time::sleep(std::time::Duration::from_millis(300)).await;
    let mut ids = Vec::new();
    while let Ok(frame) = rx.try_recv() {
        let axum::extract::ws::Message::Text(text) = frame else {
            continue;
        };
        let message: Value = serde_json::from_str(&text).expect("relay frame");
        if message[0] == "EVENT" {
            ids.push(message[2]["id"].as_str().expect("id").to_owned());
        }
    }
    sorted(ids)
}

async fn req(f: &Fixture, reader: &Keys, filter: Value) -> Vec<String> {
    req_reply(f, reader, filter).await.unwrap_or_default()
}

/// The event IDs of one historical REQ, or `None` when the relay closes it.
async fn req_reply(f: &Fixture, reader: &Keys, filter: Value) -> Option<Vec<String>> {
    let (conn, mut rx) = test_conn(&f.tenant, reader);
    let filters: Vec<nostr::Filter> = serde_json::from_value(json!([filter])).expect("filters");
    crate::handlers::req::handle_req("s".into(), filters, vec![None], conn, f.state.clone()).await;
    let mut ids = Vec::new();
    while let Ok(frame) = rx.try_recv() {
        let axum::extract::ws::Message::Text(text) = frame else {
            continue;
        };
        let message: Value = serde_json::from_str(&text).expect("relay frame");
        match message[0].as_str() {
            Some("EVENT") => ids.push(message[2]["id"].as_str().expect("id").to_owned()),
            Some("EOSE") => return Some(sorted(ids)),
            Some("CLOSED") => return None,
            other => panic!("unexpected frame {other:?}: {text}"),
        }
    }
    panic!("no EOSE; events so far: {ids:?}");
}

async fn count(f: &Fixture, reader: &Keys, filter: Value) -> u64 {
    let (conn, mut rx) = test_conn(&f.tenant, reader);
    let filters: Vec<nostr::Filter> = serde_json::from_value(json!([filter])).expect("filters");
    crate::handlers::count::handle_count("c".into(), filters, conn, f.state.clone()).await;
    while let Ok(frame) = rx.try_recv() {
        let axum::extract::ws::Message::Text(text) = frame else {
            continue;
        };
        let message: Value = serde_json::from_str(&text).expect("relay frame");
        match message[0].as_str() {
            Some("COUNT") => return message[2]["count"].as_u64().expect("count"),
            Some("CLOSED") => return 0,
            other => panic!("unexpected frame {other:?}: {text}"),
        }
    }
    panic!("no COUNT reply");
}

async fn bridge(f: &Fixture, reader: &Keys, path: &str, filter: Value) -> Option<Value> {
    use axum::body::Body;
    use axum::http::{header, Request};
    use tower::ServiceExt;

    let response = crate::router::build_router(f.state.clone())
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(path)
                .header(header::HOST, &f.host)
                .header("x-pubkey", hex(reader))
                .header("content-type", "application/json")
                .body(Body::from(serde_json::to_vec(&json!([filter])).unwrap()))
                .expect("request"),
        )
        .await
        .expect("router");
    let status = response.status();
    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .expect("body");
    if status.is_success() {
        return Some(serde_json::from_slice(&body).expect("json body"));
    }
    assert!(status.is_client_error(), "{path}: {status}");
    None
}

async fn query(f: &Fixture, reader: &Keys, filter: Value) -> Vec<String> {
    let Some(body) = bridge(f, reader, "/query", filter).await else {
        return Vec::new();
    };
    let events = body
        .as_array()
        .or_else(|| body["events"].as_array())
        .unwrap_or_else(|| panic!("query body: {body}"));
    sorted(
        events
            .iter()
            .map(|event| event["id"].as_str().expect("id").to_owned())
            .collect(),
    )
}

async fn http_count(f: &Fixture, reader: &Keys, filter: Value) -> u64 {
    bridge(f, reader, "/count", filter)
        .await
        .map_or(0, |body| body["count"].as_u64().expect("count"))
}

fn sorted(mut ids: Vec<String>) -> Vec<String> {
    ids.sort();
    ids
}

/// Every read path gives NIP-OL events only to a reader named in a `p` tag.
/// Mutation: drop the kinds from `P_GATED_KINDS` → RED (REQ without `#p`); from
/// `RESULT_GATED_KINDS` → RED (kindless `ids`, live fan-out).
#[tokio::test]
#[ignore = "requires Postgres and Redis"]
async fn olympus_reads_reach_only_p_tagged_readers() {
    let f = fixture().await;
    let outsider = &f.member;
    let kinds = json!(ALL);
    let mut owner_live = register_live(&f, &f.owner, json!({"kinds": ALL, "#p": [hex(&f.owner)]}));
    let mut operator_live = register_live(
        &f,
        &f.operator,
        json!({"kinds": ALL, "#p": [hex(&f.operator)]}),
    );
    let mut outsider_live = register_live(&f, outsider, json!({"kinds": ALL}));

    let request = request(&f, &f.owner);
    let request_id = request.id.to_hex();
    let mut events = vec![
        agent(&f, &f.operator, "olympus-dev/proof"),
        workspace(&f, &f.operator, "dev"),
        request,
    ];
    events.push(result(&f, &f.operator, &request_id));
    let mut ids = Vec::new();
    for event in events.clone() {
        ids.push(accepted(&f, event).await);
    }
    let all_ids = sorted(ids.clone());
    let owner_ids = sorted(vec![ids[0].clone(), ids[1].clone(), ids[3].clone()]);

    assert_eq!(live_ids(&mut owner_live).await, owner_ids);
    assert_eq!(live_ids(&mut operator_live).await, all_ids);
    assert!(
        live_ids(&mut outsider_live).await.is_empty(),
        "same-pod fan-out"
    );

    for event in events {
        f.state
            .local_event_ids
            .invalidate(&(f.tenant.community(), event.id.to_bytes()));
        crate::handlers::event::fan_out_pubsub_event(
            &f.state,
            buzz_pubsub::ChannelEvent {
                community_id: f.tenant.community(),
                topic: buzz_pubsub::EventTopic::Global,
                event,
            },
        )
        .await;
    }
    assert_eq!(live_ids(&mut owner_live).await, owner_ids);
    assert!(
        live_ids(&mut outsider_live).await.is_empty(),
        "Redis fan-out"
    );

    let foreign = [
        json!({"kinds": kinds, "#p": [hex(&f.owner)]}),
        json!({"kinds": kinds, "#p": [hex(outsider)]}),
        json!({"kinds": kinds}),
        json!({"ids": all_ids}),
        json!({"ids": all_ids, "kinds": kinds}),
        json!({"kinds": kinds, "search": "proof"}),
    ];
    for filter in &foreign {
        assert!(
            req(&f, outsider, filter.clone()).await.is_empty(),
            "REQ {filter}"
        );
        assert_eq!(
            count(&f, outsider, filter.clone()).await,
            0,
            "COUNT {filter}"
        );
        assert!(
            query(&f, outsider, filter.clone()).await.is_empty(),
            "/query {filter}"
        );
        assert_eq!(
            http_count(&f, outsider, filter.clone()).await,
            0,
            "/count {filter}"
        );
    }
    for filter in [&foreign[0], &foreign[2], &foreign[4], &foreign[5]] {
        assert!(
            req_reply(&f, outsider, filter.clone()).await.is_none(),
            "REQ not closed: {filter}"
        );
        assert!(
            bridge(&f, outsider, "/query", filter.clone())
                .await
                .is_none(),
            "/query not refused: {filter}"
        );
    }

    let own = json!({"kinds": kinds, "#p": [hex(&f.owner)]});
    assert_eq!(req(&f, &f.owner, own.clone()).await, owner_ids);
    assert_eq!(count(&f, &f.owner, own.clone()).await, 3);
    assert_eq!(query(&f, &f.owner, own.clone()).await, owner_ids);
    assert_eq!(http_count(&f, &f.owner, own).await, 3);
    assert_eq!(req(&f, &f.owner, json!({"ids": all_ids})).await, owner_ids);

    let operator = json!({"kinds": kinds, "#p": [hex(&f.operator)]});
    assert_eq!(req(&f, &f.operator, operator.clone()).await, all_ids);
    assert_eq!(count(&f, &f.operator, operator.clone()).await, 4);
    assert_eq!(query(&f, &f.operator, operator).await, all_ids);
    assert_eq!(
        query(&f, &f.operator, json!({"ids": all_ids})).await,
        all_ids
    );
}
