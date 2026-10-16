use axum::{http::StatusCode, Json};
use buzz_core::{kind::KIND_THREAD_STATUS, TenantContext};
use nostr::{Filter, Kind};
use serde_json::Value;
use uuid::Uuid;

use super::{api_error, extract_channel_from_filter, internal_error};
use crate::state::AppState;

type QueryError = (StatusCode, Json<Value>);

const DONE_LIMIT: i64 = 20;

fn request_channel(filter: &Filter) -> Result<Uuid, QueryError> {
    let channel = extract_channel_from_filter(filter).ok_or_else(|| {
        api_error(
            StatusCode::BAD_REQUEST,
            "open_tasks requires exactly one #h channel",
        )
    })?;
    if !filter.kinds.as_ref().is_some_and(|kinds| {
        kinds.len() == 1 && kinds.contains(&Kind::Custom(KIND_THREAD_STATUS as u16))
    }) {
        return Err(api_error(
            StatusCode::BAD_REQUEST,
            "open_tasks requires kinds [30320]",
        ));
    }
    Ok(channel)
}

pub(super) async fn query(
    state: &AppState,
    tenant: &TenantContext,
    filter: &Filter,
    accessible_channels: &[Uuid],
) -> Result<Vec<Value>, QueryError> {
    let channel = request_channel(filter)?;
    if !accessible_channels.contains(&channel) {
        return Ok(Vec::new());
    }
    let statuses = state
        .db
        .channel_task_statuses(tenant.community(), channel, DONE_LIMIT)
        .await
        .map_err(|e| internal_error(&format!("open tasks: {e}")))?;
    statuses
        .iter()
        .map(|stored| {
            serde_json::to_value(&stored.event)
                .map_err(|e| internal_error(&format!("open tasks serialization: {e}")))
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
    fn open_tasks_needs_one_channel_and_the_status_kind() {
        let ch = "11111111-1111-4111-8111-111111111111";
        assert!(request_channel(&filter(serde_json::json!({"kinds":[30320],"#h":[ch]}))).is_ok());
        assert!(
            request_channel(&filter(serde_json::json!({"kinds":[30320,9],"#h":[ch]}))).is_err()
        );
        assert!(request_channel(&filter(serde_json::json!({"kinds":[30320]}))).is_err());
    }
}
