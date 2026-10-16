use axum::{http::StatusCode, Json};
use buzz_core::TenantContext;
use nostr::Filter;
use serde_json::Value;
use uuid::Uuid;

use super::{api_error, extract_channel_from_filter, internal_error};
use crate::state::AppState;

type QueryError = (StatusCode, Json<Value>);

const MESSAGE_KINDS: [i32; 4] = [9, 40002, 45001, 45003];
const DEFAULT_LIMIT: usize = 100;
const MAX_LIMIT: usize = 200;

fn request(filter: &Filter) -> Result<(Uuid, Vec<i32>, usize), QueryError> {
    let channel = extract_channel_from_filter(filter).ok_or_else(|| {
        api_error(
            StatusCode::BAD_REQUEST,
            "files_and_links requires exactly one #h channel",
        )
    })?;
    let kinds: Vec<i32> = filter
        .kinds
        .iter()
        .flatten()
        .map(|kind| i32::from(kind.as_u16()))
        .collect();
    if kinds.is_empty() || kinds.iter().any(|kind| !MESSAGE_KINDS.contains(kind)) {
        return Err(api_error(
            StatusCode::BAD_REQUEST,
            "files_and_links requires message kinds 9, 40002, 45001, or 45003",
        ));
    }
    Ok((
        channel,
        kinds,
        filter.limit.unwrap_or(DEFAULT_LIMIT).clamp(1, MAX_LIMIT),
    ))
}

pub(super) async fn query(
    state: &AppState,
    tenant: &TenantContext,
    filter: &Filter,
    accessible_channels: &[Uuid],
) -> Result<Vec<Value>, QueryError> {
    let (channel, kinds, limit) = request(filter)?;
    if !accessible_channels.contains(&channel) {
        return Ok(Vec::new());
    }
    let until = filter
        .until
        .and_then(|ts| chrono::DateTime::from_timestamp(ts.as_secs() as i64, 0));
    let events = state
        .db
        .channel_files_and_links(tenant.community(), channel, &kinds, until, limit as i64)
        .await
        .map_err(|e| internal_error(&format!("files and links: {e}")))?;
    events
        .iter()
        .map(|stored| {
            serde_json::to_value(&stored.event)
                .map_err(|e| internal_error(&format!("files and links serialization: {e}")))
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn filter(value: serde_json::Value) -> Filter {
        serde_json::from_value(value).expect("filter")
    }

    #[test]
    fn files_and_links_bounds_kinds_and_limit() {
        let ch = "11111111-1111-4111-8111-111111111111";
        assert_eq!(
            request(&filter(
                serde_json::json!({"kinds":[9,40002],"#h":[ch],"limit":500})
            ))
            .unwrap()
            .2,
            200
        );
        assert_eq!(
            request(&filter(serde_json::json!({"kinds":[9],"#h":[ch]})))
                .unwrap()
                .2,
            100
        );
        assert!(request(&filter(serde_json::json!({"kinds":[7],"#h":[ch]}))).is_err());
        assert!(request(&filter(serde_json::json!({"kinds":[9]}))).is_err());
    }
}
