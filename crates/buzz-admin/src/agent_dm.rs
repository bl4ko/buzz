use anyhow::Result;
use buzz_core::kind::KIND_DM_VISIBILITY;
use buzz_db::Db;
use nostr::{EventBuilder, Keys, Kind, Tag};

use super::{connect_member_services, parse_pubkey_hex, resolve_admin_tenant};

pub async fn run(agent: String) -> Result<i32> {
    let agent = match parse_pubkey_hex(&agent) {
        Ok(hex) => hex,
        Err(e) => {
            eprintln!("error: {e}");
            return Ok(1);
        }
    };
    let (db, _pubsub, keys) = connect_member_services().await?;
    let tenant = resolve_admin_tenant(&db).await?;
    let community = tenant.community();
    let Some((channel, owner)) = db
        .hide_agent_owner_dm(community, &hex::decode(&agent)?)
        .await?
    else {
        println!("{}", serde_json::json!({"agent": agent, "status": "no_dm"}));
        return Ok(2);
    };
    let snapshot = publish_snapshot(&db, community, &owner, &keys).await?;
    println!(
        "{}",
        serde_json::json!({
            "agent": agent,
            "owner": hex::encode(&owner),
            "channel": channel.to_string(),
            "status": "hidden",
            "snapshot": snapshot,
        })
    );
    Ok(0)
}

async fn publish_snapshot(
    db: &Db,
    community: buzz_core::CommunityId,
    viewer: &[u8],
    keys: &Keys,
) -> Result<String> {
    let viewer_hex = hex::encode(viewer);
    let mut tags = vec![
        Tag::parse(["d", &viewer_hex])?,
        Tag::parse(["p", &viewer_hex])?,
    ];
    for channel in db.list_hidden_dms(community, viewer).await? {
        tags.push(Tag::parse(["h", &channel.to_string()])?);
    }
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)?
        .as_secs();
    let previous = db
        .query_events_for_event_write(&buzz_db::event::EventQuery {
            kinds: Some(vec![KIND_DM_VISIBILITY as i32]),
            pubkey: Some(keys.public_key().to_bytes().to_vec()),
            d_tag: Some(viewer_hex.clone()),
            limit: Some(1),
            ..buzz_db::event::EventQuery::for_community(community)
        })
        .await?;
    let created_at = previous
        .first()
        .map(|e| (e.event.created_at.as_secs() + 1).max(now))
        .unwrap_or(now);
    let event = EventBuilder::new(Kind::Custom(KIND_DM_VISIBILITY as u16), "")
        .tags(tags)
        .custom_created_at(nostr::Timestamp::from(created_at))
        .sign_with_keys(keys)?;
    db.replace_parameterized_event(community, &event, &viewer_hex, None)
        .await?;
    Ok(event.id.to_hex())
}
