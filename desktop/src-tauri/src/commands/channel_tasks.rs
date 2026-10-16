use tauri::State;

use crate::{app_state::AppState, relay::query_relay};

pub(crate) fn build_channel_tasks_filter(channel_id: &str) -> serde_json::Value {
    serde_json::json!({"kinds": [30320], "#h": [channel_id], "limit": 500, "open_tasks": true})
}

pub(crate) fn build_files_and_links_filter(
    channel_id: &str,
    until: Option<u64>,
) -> serde_json::Value {
    let mut filter = serde_json::json!({
        "kinds": [9, 40002, 45001, 45003],
        "#h": [channel_id],
        "limit": 100,
        "files_and_links": true
    });
    if let Some(until) = until {
        filter["until"] = serde_json::json!(until);
    }
    filter
}

async fn query_values(
    state: &AppState,
    filter: serde_json::Value,
) -> Result<Vec<serde_json::Value>, String> {
    Ok(query_relay(state, &[filter])
        .await?
        .iter()
        .filter_map(|event| serde_json::to_value(event).ok())
        .collect())
}

#[tauri::command]
pub async fn get_channel_tasks(
    channel_id: String,
    state: State<'_, AppState>,
) -> Result<Vec<serde_json::Value>, String> {
    query_values(&state, build_channel_tasks_filter(&channel_id)).await
}

#[tauri::command]
pub async fn get_channel_files_and_links(
    channel_id: String,
    until: Option<u64>,
    state: State<'_, AppState>,
) -> Result<Vec<serde_json::Value>, String> {
    query_values(&state, build_files_and_links_filter(&channel_id, until)).await
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn tasks_filter_requests_open_tasks_for_one_channel() {
        assert_eq!(
            build_channel_tasks_filter("c1"),
            serde_json::json!({"kinds": [30320], "#h": ["c1"], "limit": 500, "open_tasks": true})
        );
    }

    #[test]
    fn files_filter_pages_with_until() {
        assert_eq!(
            build_files_and_links_filter("c1", Some(99)),
            serde_json::json!({"kinds": [9, 40002, 45001, 45003], "#h": ["c1"], "limit": 100, "files_and_links": true, "until": 99})
        );
        assert!(build_files_and_links_filter("c1", None)
            .get("until")
            .is_none());
    }
}
