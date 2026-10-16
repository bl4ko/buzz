use buzz_core::kind::{KIND_FORUM_POST, KIND_STREAM_MESSAGE, KIND_STREAM_MESSAGE_V2};
use buzz_core::tenant::TenantContext;
use buzz_core::thread_status::{
    parse_canvas_d_tag, parse_channel_tabs, parse_thread_status, CANVAS_DOC_MAX_BYTES,
};
use nostr::Event;
use uuid::Uuid;

use crate::state::AppState;

fn rows(event: &Event) -> Vec<Vec<String>> {
    event
        .tags
        .iter()
        .map(|tag| tag.as_slice().to_vec())
        .collect()
}

fn first_value(rows: &[Vec<String>], name: &str) -> Option<String> {
    rows.iter()
        .find(|row| row.first().map(String::as_str) == Some(name))
        .and_then(|row| row.get(1).cloned())
}

fn db_error(error: impl std::fmt::Display) -> String {
    format!("error: database error: {error}")
}

fn channel_of(value: &str, label: &str) -> Result<Uuid, String> {
    Uuid::parse_str(value).map_err(|_| format!("invalid: {label} h tag must be a channel ID"))
}

async fn community_owner(
    tenant: &TenantContext,
    state: &AppState,
    pubkey: &[u8],
) -> Result<bool, String> {
    Ok(state
        .db
        .get_relay_member(tenant.community(), &hex::encode(pubkey))
        .await
        .map_err(db_error)?
        .is_some_and(|member| member.role == "owner"))
}

async fn channel_role(
    tenant: &TenantContext,
    state: &AppState,
    channel: Uuid,
    pubkey: &[u8],
) -> Result<Option<String>, String> {
    state
        .db
        .get_member_role(tenant.community(), channel, pubkey)
        .await
        .map_err(db_error)
}

async fn is_agent(tenant: &TenantContext, state: &AppState, pubkey: &[u8]) -> Result<bool, String> {
    Ok(state
        .db
        .get_agent_channel_policy(tenant.community(), pubkey)
        .await
        .map_err(db_error)?
        .is_some_and(|(_, owner)| owner.is_some()))
}

async fn channel_message(
    tenant: &TenantContext,
    state: &AppState,
    channel: Uuid,
    id_hex: &str,
    label: &str,
) -> Result<(Vec<u8>, [u8; 32]), String> {
    let id = hex::decode(id_hex).map_err(|_| format!("invalid: {label} not found"))?;
    let target = state
        .db
        .get_event_by_id_for_event_write(tenant.community(), &id)
        .await
        .map_err(db_error)?
        .ok_or_else(|| format!("invalid: {label} not found"))?;
    if !matches!(
        u32::from(target.event.kind.as_u16()),
        KIND_STREAM_MESSAGE | KIND_STREAM_MESSAGE_V2 | KIND_FORUM_POST
    ) {
        return Err(format!("invalid: {label} must be a channel message"));
    }
    if target.channel_id != Some(channel) {
        return Err(format!("invalid: {label} belongs to a different channel"));
    }
    Ok((id, target.event.pubkey.to_bytes()))
}

pub(crate) async fn validate_thread_status(
    tenant: &TenantContext,
    event: &Event,
    state: &AppState,
) -> Result<(), String> {
    let parsed =
        parse_thread_status(&rows(event), &event.content).map_err(|e| format!("invalid: {e}"))?;
    let channel = channel_of(&parsed.channel_id, "thread status")?;
    let author = event.pubkey.to_bytes();
    let allowed = community_owner(tenant, state, &author).await?
        || (channel_role(tenant, state, channel, &author)
            .await?
            .is_some()
            && is_agent(tenant, state, &author).await?);
    if !allowed {
        return Err("restricted: thread status author must be the owner or a channel agent".into());
    }
    let (root, _) = channel_message(
        tenant,
        state,
        channel,
        &parsed.root_id,
        "thread status root",
    )
    .await?;
    if state
        .db
        .get_thread_metadata_by_event(tenant.community(), &root)
        .await
        .map_err(db_error)?
        .is_some_and(|meta| meta.parent_event_id.is_some())
    {
        return Err("invalid: thread status root must be a top-level message".into());
    }
    if let Some(ask) = &parsed.ask {
        let (ask_id, ask_author) = channel_message(
            tenant,
            state,
            channel,
            &ask.event_id,
            "thread status ask event",
        )
        .await?;
        if ask_author != author {
            return Err(
                "invalid: thread status ask event must be authored by the status author".into(),
            );
        }
        let in_thread = ask_id == root
            || state
                .db
                .get_thread_metadata_by_event(tenant.community(), &ask_id)
                .await
                .map_err(db_error)?
                .and_then(|meta| meta.root_event_id.or(meta.parent_event_id))
                .is_some_and(|ask_root| ask_root == root);
        if !in_thread {
            return Err("invalid: thread status ask event must be in the root thread".into());
        }
    }
    Ok(())
}

pub(crate) async fn validate_channel_tabs(
    tenant: &TenantContext,
    event: &Event,
    state: &AppState,
) -> Result<(), String> {
    let rows = rows(event);
    let h = first_value(&rows, "h").unwrap_or_default();
    if first_value(&rows, "d").as_deref() != Some(h.as_str()) {
        return Err("invalid: channel tabs d tag must equal the h channel".into());
    }
    parse_channel_tabs(&event.content).map_err(|e| format!("invalid: {e}"))?;
    let channel = channel_of(&h, "channel tabs")?;
    let author = event.pubkey.to_bytes();
    let allowed = community_owner(tenant, state, &author).await?
        || matches!(
            channel_role(tenant, state, channel, &author)
                .await?
                .as_deref(),
            Some("owner" | "admin")
        );
    if !allowed {
        return Err("restricted: channel tabs need a channel owner or admin".into());
    }
    Ok(())
}

pub(crate) async fn validate_canvas_doc(
    tenant: &TenantContext,
    event: &Event,
    state: &AppState,
) -> Result<(), String> {
    if event.content.len() > CANVAS_DOC_MAX_BYTES {
        return Err(format!(
            "invalid: canvas content exceeds {CANVAS_DOC_MAX_BYTES} bytes"
        ));
    }
    let rows = rows(event);
    let h = first_value(&rows, "h").unwrap_or_default();
    let d = first_value(&rows, "d").unwrap_or_default();
    parse_canvas_d_tag(&d, &h).map_err(|e| format!("invalid: {e}"))?;
    let channel = channel_of(&h, "canvas")?;
    let author = event.pubkey.to_bytes();
    let allowed = community_owner(tenant, state, &author).await?
        || matches!(channel_role(tenant, state, channel, &author).await?, Some(role) if role != "guest");
    if !allowed {
        return Err("restricted: canvas author must be a channel member".into());
    }
    Ok(())
}
