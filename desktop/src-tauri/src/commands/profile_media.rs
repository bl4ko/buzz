use crate::{app_state::AppState, models::ProfileInfo, relay::query_relay};
use serde_json::Value;
use std::collections::HashMap;

pub(super) async fn load_agent_icons(
    state: &AppState,
    targets: &[(String, Option<String>)],
) -> Result<HashMap<String, String>, String> {
    let owners = targets
        .iter()
        .filter_map(|(_, owner)| owner.as_ref())
        .collect::<std::collections::BTreeSet<_>>();
    let mut icons = HashMap::new();
    if owners.is_empty() {
        return Ok(icons);
    }
    let owners = owners.into_iter().collect::<Vec<_>>();
    let events = query_relay(
        state,
        &[serde_json::json!({"kinds": [0], "authors": owners, "limit": owners.len()})],
    )
    .await?;
    for event in events {
        let Ok(metadata) = serde_json::from_str::<Value>(&event.content) else {
            continue;
        };
        let owner = event.pubkey.to_hex();
        for (pk, expected) in targets {
            if expected.as_deref() != Some(&owner) {
                continue;
            }
            if let Some(icon) = metadata
                .get("buzz_agent_media")
                .and_then(|media| media.get(pk))
                .and_then(|media| media.get("picture"))
                .and_then(Value::as_str)
            {
                icons.insert(pk.clone(), icon.to_string());
            }
        }
    }
    Ok(icons)
}

pub(super) async fn apply_search_icons(
    state: &AppState,
    response: &mut crate::models::SearchUsersResponse,
) -> Result<(), String> {
    let targets = response
        .users
        .iter()
        .map(|user| (user.pubkey.clone(), user.owner_pubkey.clone()))
        .collect::<Vec<_>>();
    let icons = load_agent_icons(state, &targets).await?;
    for user in &mut response.users {
        if let Some(icon) = icons.get(&user.pubkey) {
            user.avatar_url = Some(icon.clone());
        }
    }
    Ok(())
}

pub(super) fn apply_agent_media(
    profile: &mut ProfileInfo,
    owner: &nostr::Event,
) -> Result<(), String> {
    if profile.owner_pubkey.as_deref() != Some(owner.pubkey.to_hex().as_str()) {
        return Err("agent profile owner does not match".to_string());
    }
    let metadata: Value =
        serde_json::from_str(&owner.content).map_err(|error| error.to_string())?;
    if let Some(media) = metadata
        .get("buzz_agent_media")
        .and_then(|agents| agents.get(&profile.pubkey))
    {
        if let Some(value) = media.get("picture").and_then(Value::as_str) {
            profile.avatar_url = Some(value.to_string());
        }
        if let Some(value) = media.get("banner").and_then(Value::as_str) {
            profile.banner_url = Some(value.to_string());
        }
        if let Some(value) = media.get("buzz_model").and_then(Value::as_str) {
            profile.model_url = Some(value.to_string());
        }
    }
    Ok(())
}

pub(super) fn validate_profile_media_url(value: &str) -> Result<(), String> {
    if value.is_empty() {
        return Ok(());
    }
    let url = url::Url::parse(value).map_err(|_| "invalid profile media URL".to_string())?;
    if url.scheme() != "https"
        && !(url.scheme() == "http"
            && matches!(url.host_str(), Some("localhost" | "127.0.0.1" | "[::1]")))
    {
        return Err("profile media must use HTTPS".to_string());
    }
    if !url.username().is_empty() || url.password().is_some() {
        return Err("profile media URL must not contain credentials".to_string());
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn icon_override_requires_matching_owner_and_preserves_other_media() {
        let owner = nostr::Keys::generate();
        let mut profile = ProfileInfo {
            pubkey: nostr::Keys::generate().public_key().to_hex(),
            owner_pubkey: Some(owner.public_key().to_hex()),
            avatar_url: Some("https://example.com/original.png".to_string()),
            banner_url: Some("https://example.com/banner.png".to_string()),
            model_url: Some("https://example.com/model.glb".to_string()),
            display_name: None,
            about: None,
            nip05_handle: None,
            has_profile_event: true,
        };
        let metadata = serde_json::json!({"picture": "https://example.com/owner.png", "buzz_agent_media": {&profile.pubkey: {"picture": "https://example.com/icon.png"}}});
        let event = nostr::EventBuilder::new(nostr::Kind::Metadata, metadata.to_string())
            .sign_with_keys(&owner)
            .expect("sign profile");
        apply_agent_media(&mut profile, &event).expect("apply icon");
        assert_eq!(
            profile.avatar_url.as_deref(),
            Some("https://example.com/icon.png")
        );
        assert_eq!(
            profile.banner_url.as_deref(),
            Some("https://example.com/banner.png")
        );
        assert_eq!(
            profile.model_url.as_deref(),
            Some("https://example.com/model.glb")
        );
        profile.owner_pubkey = Some(nostr::Keys::generate().public_key().to_hex());
        assert!(apply_agent_media(&mut profile, &event).is_err());
    }
}
