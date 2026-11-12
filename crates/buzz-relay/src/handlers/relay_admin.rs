//! NIP-43 relay membership admin command handler (kinds 9030–9032).
//!
//! These events are processed directly — they mutate the `relay_members` table
//! and return without being stored as regular Nostr events.
//!
//! ## Permission matrix
//!
//! | Kind | Operation       | Required sender role |
//! |------|-----------------|----------------------|
//! | 9030 | Add member, optionally with the agent's owner (see [`consented_owner`]) | admin or owner |
//! | 9031 | Remove member   | admin or owner       |
//! | 9032 | Change role     | owner only           |
//! | 9033 | Set workspace profile (icon) | admin or owner; on an open relay whose community has no admin/owner row at all, any authenticated sender (see [`may_set_workspace_profile`]) |

use std::sync::Arc;

use nostr::Event;
use tracing::{info, warn};

use buzz_core::kind::{
    RELAY_ADMIN_ADD_MEMBER, RELAY_ADMIN_CHANGE_ROLE, RELAY_ADMIN_REMOVE_MEMBER,
    RELAY_ADMIN_SET_WORKSPACE_PROFILE,
};
use buzz_core::tenant::TenantContext;
use buzz_db::relay_members::RemoveResult;
use buzz_db::user::AgentOwnerAssignment;

use crate::handlers::side_effects::{
    auto_join_default_channels, fan_out_nip43_membership_list, publish_nip43_member_added,
    publish_nip43_member_removed,
};
use crate::state::AppState;

/// Extract the hex pubkey from the first `p` tag, returning it as a `String`.
fn extract_p_tag_hex(event: &Event) -> Option<String> {
    for tag in event.tags.iter() {
        let parts = tag.as_slice();
        if parts.first().map(|s| s.as_str()) == Some("p") {
            if let Some(val) = parts.get(1).map(|s| s.as_str()) {
                // Must be exactly 64 hex chars (uncompressed pubkey representation).
                if val.len() == 64 && val.chars().all(|c| c.is_ascii_hexdigit()) {
                    return Some(val.to_string());
                }
            }
        }
    }
    None
}

/// Extract the value of the first tag with the given name.
fn extract_tag_value(event: &Event, name: &str) -> Option<String> {
    for tag in event.tags.iter() {
        let parts = tag.as_slice();
        if parts.first().map(|s| s.as_str()) == Some(name) {
            return parts.get(1).map(|s| s.to_string());
        }
    }
    None
}

/// The target of a kind:9030 and the owner the event names for it in an
/// `["owner", <owner pubkey>, <consent>]` tag, or `None` without the tag. The
/// consent is the target's own signature
/// (`buzz_sdk::nip_oa::compute_owner_consent`), so no key can be made
/// someone's agent without holding it.
fn consented_owner(
    event: &Event,
    target_hex: &str,
) -> Result<Option<(nostr::PublicKey, nostr::PublicKey)>, String> {
    let mut owner_tags = event
        .tags
        .iter()
        .map(|tag| tag.as_slice())
        .filter(|parts| parts.first().map(String::as_str) == Some("owner"));
    let Some(parts) = owner_tags.next() else {
        return Ok(None);
    };
    if owner_tags.next().is_some() {
        return Err(format!("{OWNER_REFUSED}: more than one owner tag"));
    }
    let [_, owner_hex, consent] = parts else {
        return Err(format!(
            "{OWNER_REFUSED}: owner tag must hold the owner pubkey and the agent's consent signature"
        ));
    };
    let target = nostr::PublicKey::from_hex(target_hex)
        .map_err(|e| format!("{OWNER_REFUSED}: invalid target pubkey: {e}"))?;
    buzz_sdk::nip_oa::verify_owner_consent(&target, owner_hex, consent)
        .map(|owner| Some((target, owner)))
        .map_err(|e| format!("{OWNER_REFUSED}: {e}"))
}

/// Prefix of every refusal of a kind:9030 `owner` tag.
const OWNER_REFUSED: &str = "agent owner refused";

/// Why a kind:9030 `owner` tag was refused, or `None` when the agent has the
/// named owner.
fn owner_refusal(assignment: AgentOwnerAssignment) -> Option<&'static str> {
    match assignment {
        AgentOwnerAssignment::Assigned | AgentOwnerAssignment::Unchanged => None,
        AgentOwnerAssignment::OwnerConflict => Some("the agent has a different owner"),
        AgentOwnerAssignment::SelfOwner => Some("owner and agent pubkeys must differ"),
        AgentOwnerAssignment::AgentNotMember => {
            Some("the agent must be a relay member with the member role")
        }
        AgentOwnerAssignment::NotAddedBySender => {
            Some("an admin can set the owner only of a member it added")
        }
        AgentOwnerAssignment::OwnerNotMember => Some("the owner is not a relay member"),
        AgentOwnerAssignment::OwnerIsAgent => Some("the owner is itself an agent"),
        AgentOwnerAssignment::AgentOwnsAgents => Some("the agent is the owner of other agents"),
    }
}

/// Record that an admin gave `agent` its first owner: audit it, and do what a
/// first NIP-OA link does (`link_agent_owner`), so the agent's ownerless
/// sockets reconnect with the owner attached.
async fn first_owner_assigned(
    tenant: &TenantContext,
    state: &Arc<AppState>,
    sender: &nostr::PublicKey,
    agent: &[u8],
    owner: &nostr::PublicKey,
) {
    let community = tenant.community();
    state
        .author_type_cache
        .insert((community, agent.to_vec()), true);
    state
        .observer_owner_cache
        .insert((community, agent.to_vec(), owner.to_bytes().to_vec()), true);
    state.disconnect_unowned_agent_clusterwide(tenant, agent);
    if let Some(audit_tx) = &state.audit_tx {
        let entry = buzz_audit::NewAuditEntry {
            community_id: community,
            action: buzz_audit::AuditAction::AgentOwnerChanged,
            actor_pubkey: Some(sender.to_bytes().to_vec()),
            object_id: Some(hex::encode(agent)),
            detail: serde_json::json!({
                "previous_owner": null,
                "new_owner": owner.to_hex(),
                "source": "kind:9030",
            }),
        };
        if let Err(e) = audit_tx.send(entry).await {
            tracing::error!("agent owner audit channel closed, entry lost: {e}");
            metrics::counter!("buzz_audit_send_errors_total").increment(1);
        }
    }
}

/// Maximum accepted workspace icon https URL length.
const MAX_WORKSPACE_ICON_URL_LEN: usize = 2048;

/// Maximum accepted workspace icon data-URL length (~96 KB of base64 ≈ 72 KB
/// image — generous for a 128px icon).
const MAX_WORKSPACE_ICON_DATA_URL_LEN: usize = 98_304;

/// Validate a workspace icon: empty (clear), an http(s) URL, or an inline
/// `data:image/*` URL (what the desktop publishes — it renders across
/// workspaces without cross-relay media fetches).
fn validate_workspace_icon(icon: &str) -> Result<(), String> {
    if icon.is_empty() {
        return Ok(());
    }
    if icon.chars().any(|c| c.is_control() || c.is_whitespace()) {
        return Err("icon contains invalid characters".to_string());
    }
    if icon.starts_with("data:image/") {
        if icon.len() > MAX_WORKSPACE_ICON_DATA_URL_LEN {
            return Err(format!(
                "icon data URL too long: {} bytes (max {MAX_WORKSPACE_ICON_DATA_URL_LEN})",
                icon.len()
            ));
        }
        return Ok(());
    }
    if !icon.starts_with("https://") && !icon.starts_with("http://") {
        return Err("icon must be an http(s) URL or data:image/* URL".to_string());
    }
    if icon.len() > MAX_WORKSPACE_ICON_URL_LEN {
        return Err(format!(
            "icon URL too long: {} bytes (max {MAX_WORKSPACE_ICON_URL_LEN})",
            icon.len()
        ));
    }
    Ok(())
}

/// Whether `sender_role` may set the workspace profile (kind:9033).
///
/// Closed relays (`membership_enforced == true`) require an `admin`/`owner`
/// row in `relay_members` — the enforced roster is the authority. Open relays
/// don't *enforce* the roster, but the data can still exist: startup
/// bootstraps `RELAY_OWNER_PUBKEY` as `owner` regardless of the flag
/// (`main.rs`), as does operator provisioning. So the rule is steward-wins:
///
/// - a steward (any admin/owner row) exists → admin/owner only, exactly like
///   a closed relay. An open relay with a configured owner keeps its icon
///   owner-controlled instead of last-write-wins for every authenticated key.
/// - genuinely rosterless (e.g. a community created by
///   `ensure_configured_community`, which writes no owner row) → any
///   NIP-42-authenticated sender may set the icon, mirroring how open relays
///   gate every other write. Without this the icon is permanently unsettable:
///   the desktop deliberately shows the icon editor on open relays (see
///   `canEditIcon` in `EditCommunityDialog.tsx`, #2640) and defers to this
///   relay-side check, which used to always say no.
fn may_set_workspace_profile(
    sender_role: &str,
    membership_enforced: bool,
    community_has_steward: bool,
) -> bool {
    if !membership_enforced && !community_has_steward {
        return true;
    }
    sender_role == "admin" || sender_role == "owner"
}

/// A relay-admin command failure, carrying the *category* of the failure so
/// the ingest seam can map it to the right NIP-01 prefix and HTTP status.
///
/// The category is part of the security contract, not cosmetics: a ban must
/// surface as `blocked:` / HTTP 403 (like every other durable-restriction
/// refusal), and a restriction-lookup outage must surface as a 500 rather than
/// a client-side 400 that reads as "your request was malformed". Mirrors
/// [`super::push_lease::AcceptError`] and its `map_push_accept_error` seam.
#[derive(Debug, PartialEq, Eq)]
pub(super) enum RelayAdminError {
    /// Sender is under a durable community ban — `blocked:` / HTTP 403. The
    /// source says whether its own row or its owner's decided it.
    Banned(crate::handlers::auth::BanSource),
    /// Legacy command rejection — `invalid:` / HTTP 400. This is whatever
    /// [`execute_relay_admin_command`] returned as a `String`, which is mostly
    /// validation and authorization but also still includes that function's own
    /// DB failures. Categorizing those is deliberately out of scope for the ban
    /// fix, so this arm claims no stronger invariant than "the command body said
    /// no".
    Rejected(String),
    /// Admission could not be decided because the restriction lookup failed —
    /// `error:` / HTTP 500.
    Internal(String),
}

/// Decide whether a durable restriction state admits a relay-admin command.
///
/// Ban only, deliberately: a timeout is a write-block on *content*, and
/// `ingest_event` exempts relay-admin kinds from its durable write-path gate
/// precisely so restricted-but-not-banned admins retain their administrative
/// capability. Mirrors `moderation_commands::ensure_actor_not_banned`.
///
/// Split out as a pure function so the admission rule itself is unit-testable
/// without a live relay: the end-to-end HTTP test proves the transport, this
/// proves the decision.
fn admits_relay_admin_command(
    restriction: &buzz_db::moderation::RestrictionState,
) -> Result<(), RelayAdminError> {
    if restriction.banned {
        return Err(RelayAdminError::Banned(
            crate::handlers::auth::BanSource::of(restriction),
        ));
    }
    Ok(())
}

/// Validate and execute a relay admin command (kinds 9030–9033).
///
/// Admission: rejects a sender under a durable community ban before any
/// command runs. The command itself is executed by
/// [`execute_relay_admin_command`].
///
/// Returns `Ok(())` on success, or a categorized [`RelayAdminError`].
pub(super) async fn handle_relay_admin_event(
    tenant: &TenantContext,
    state: &Arc<AppState>,
    event: &Event,
) -> Result<(), RelayAdminError> {
    // A ban is an admission boundary, not only a WebSocket-auth check. HTTP
    // NIP-98 requests and already-authenticated sockets reach this handler
    // without passing through a fresh NIP-42 challenge, and `ingest_event`
    // exempts relay-admin kinds from its durable write-path gate so a *timed
    // out* admin can still administer the roster. That exemption is ban-blind,
    // so the ban must be enforced here or not at all: a banned admin otherwise
    // keeps mutating `relay_members` — the very table `moderation_authz`
    // derives moderator capability from — until someone manually deletes the
    // row. Mirrors `moderation_commands.rs`, which defends the same boundary
    // for 9040–9044, and holds that file's stated invariant that a direct
    // command handler rejects a banned actor on every transport.
    //
    // This gate wraps execution rather than opening it so no future early
    // return inside the command body can precede it.
    #[cfg(test)]
    crate::nip_fi_test_hooks::before_command_ban_check(tenant.community()).await;
    let restriction = state
        .db
        .moderation_restriction_state(tenant.community(), &event.pubkey.to_bytes())
        .await
        // Fail closed: a DB blip must never admit a banned admin.
        .map_err(|e| {
            RelayAdminError::Internal(format!("internal error checking restriction state: {e}"))
        })?;
    admits_relay_admin_command(&restriction)?;

    execute_relay_admin_command(tenant, state, event)
        .await
        .map_err(RelayAdminError::Rejected)
}

/// Execute an already-admitted relay admin command.
///
/// The handler:
/// 1. Extracts the target pubkey from the `["p", ...]` tag.
/// 2. Extracts the role from the `["role", ...]` tag (kinds 9030 and 9032).
/// 3. Looks up the sender's current role in `relay_members`.
/// 4. Enforces the permission matrix.
/// 5. Applies the change via the DB.
///
/// Returns `Ok(())` on success.  Returns `Err(msg)` — where `msg` is the
/// legacy rejection reason — on any failure. This body does not distinguish
/// validation failures from execution DB failures; both surface as `Err(msg)`
/// and are categorised by the caller as [`RelayAdminError::Rejected`].
async fn execute_relay_admin_command(
    tenant: &TenantContext,
    state: &Arc<AppState>,
    event: &Event,
) -> Result<(), String> {
    let kind = event.kind.as_u16() as u32;
    let sender_hex = event.pubkey.to_hex();

    // This mirrors the NIP-42 auth event freshness check and prevents replay
    // of captured admin commands. The window is intentionally tight — admin
    // events should be freshly signed.
    {
        let event_ts = event.created_at.as_secs() as i64;
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_secs() as i64)
            .unwrap_or(0);
        if (event_ts - now).abs() > 120 {
            return Err(format!(
                "event timestamp out of range: created_at={event_ts}, now={now}, delta={}s (max ±120s)",
                event_ts - now
            ));
        }
    }

    let sender_member = state
        .db
        .get_relay_member(tenant.community(), &sender_hex)
        .await
        .map_err(|e| format!("database error: {e}"))?;

    let sender_role = sender_member
        .as_ref()
        .map(|m| m.role.as_str())
        .unwrap_or("");

    // kind:9033 — Set workspace profile (icon). Handled before p-tag
    // extraction: it targets the relay itself, not a member pubkey.
    if kind == RELAY_ADMIN_SET_WORKSPACE_PROFILE {
        // Steward detection only matters on open relays (closed relays gate on
        // the sender's own role either way), so skip the extra query there.
        let community_has_steward = if state.config.require_relay_membership {
            true
        } else {
            state
                .db
                .has_admin_or_owner(tenant.community())
                .await
                .map_err(|e| format!("database error: {e}"))?
        };
        if !may_set_workspace_profile(
            sender_role,
            state.config.require_relay_membership,
            community_has_steward,
        ) {
            return Err("actor not authorized: must be admin or owner".to_string());
        }
        if sender_role != "admin" && sender_role != "owner" {
            // Rosterless-open-relay admit: 9033 writes no audit row and
            // publishes no announcement event (unlike 9030/9031), so this warn
            // is the only durable attribution of who changed the icon.
            warn!(
                sender = %sender_hex,
                "workspace profile change admitted without a roster role (open relay, no steward)"
            );
        }

        // Empty or missing icon tag clears the workspace icon.
        let icon = extract_tag_value(event, "icon").unwrap_or_default();
        validate_workspace_icon(&icon)?;

        state
            .db
            .set_community_icon(
                tenant.community(),
                (!icon.is_empty()).then_some(icon.as_str()),
            )
            .await
            .map_err(|e| format!("failed to store workspace icon: {e}"))?;

        info!(sender = %sender_hex, icon_len = icon.len(), "workspace profile updated");
        return Ok(());
    }

    let target_hex = extract_p_tag_hex(event)
        .ok_or_else(|| "missing or invalid p tag".to_string())?
        .to_ascii_lowercase();

    match kind {
        // kind:9030 — Add relay member
        k if k == RELAY_ADMIN_ADD_MEMBER => {
            // Sender must be admin or owner.
            if sender_role != "admin" && sender_role != "owner" {
                return Err("actor not authorized: must be admin or owner".to_string());
            }

            // Default role is "member" when no role tag is present.
            let role = extract_tag_value(event, "role").unwrap_or_else(|| "member".to_string());

            // Owners can add admins or members; admins can only add members.
            if role == "owner" {
                return Err("invalid role: use kind:9032 to promote to owner".to_string());
            }
            if role == "admin" && sender_role != "owner" {
                return Err("actor not authorized: only owner can grant admin role".to_string());
            }
            if role != "admin" && role != "member" {
                return Err(format!("invalid role: {role}"));
            }

            let owner = consented_owner(event, &target_hex)?;
            if owner.is_some() && role != "member" {
                return Err(format!(
                    "{OWNER_REFUSED}: the agent must be a relay member with the member role"
                ));
            }

            // Note: idempotent — if target already exists at any role, this is a
            // silent no-op. The existing role is NOT overwritten. Use kind:9032
            // to change an existing member's role.
            let (was_inserted, snapshot) = match owner {
                None => {
                    let write = state
                        .db
                        .add_relay_member(
                            tenant.community(),
                            &target_hex,
                            &role,
                            Some(&sender_hex),
                            &state.relay_keypair,
                        )
                        .await
                        .map_err(|e| format!("database error: {e}"))?;
                    (write.outcome, write.snapshot)
                }
                Some((agent, owner)) => {
                    let write = state
                        .db
                        .add_relay_member_with_owner(
                            tenant.community(),
                            &target_hex,
                            owner.as_bytes(),
                            &sender_hex,
                            sender_role != "owner",
                            &state.relay_keypair,
                        )
                        .await
                        .map_err(|e| format!("database error: {e}"))?;
                    let (was_inserted, assignment) = write.outcome;
                    if let Some(reason) = owner_refusal(assignment) {
                        return Err(format!("{OWNER_REFUSED}: {reason}"));
                    }
                    if assignment == AgentOwnerAssignment::Assigned {
                        info!(
                            sender = %sender_hex,
                            target = %target_hex,
                            owner = %owner.to_hex(),
                            "agent owner assigned by relay admin"
                        );
                        first_owner_assigned(
                            tenant,
                            state,
                            &event.pubkey,
                            agent.as_bytes(),
                            &owner,
                        )
                        .await;
                    }
                    (was_inserted, write.snapshot)
                }
            };

            info!(
                sender = %sender_hex,
                target = %target_hex,
                role = %role,
                was_inserted,
                "relay member add attempted"
            );

            // Only publish NIP-43 announcements when the row was actually inserted —
            // skip on no-op re-adds to avoid spurious kind:8000 events.
            if was_inserted {
                if let Err(e) = publish_nip43_member_added(tenant, state, &target_hex).await {
                    warn!(error = %e, "failed to publish NIP-43 member added event");
                }
                // The sender adds someone else, so the target's
                // `channel_add_policy` decides whether they are auto-joined.
                auto_join_default_channels(
                    tenant,
                    state,
                    &target_hex,
                    Some(&event.pubkey.to_bytes()),
                )
                .await;
            }
            fan_out_nip43_membership_list(tenant, state, snapshot).await;
        }

        // kind:9031 — Remove relay member
        k if k == RELAY_ADMIN_REMOVE_MEMBER => {
            // Sender must be admin or owner.
            if sender_role != "admin" && sender_role != "owner" {
                return Err("actor not authorized: must be admin or owner".to_string());
            }

            // Cannot remove yourself.
            if target_hex == sender_hex {
                return Err("cannot remove yourself".to_string());
            }

            // Dispatch removal by sender role:
            // - Admins: atomic conditional delete, only removes 'member' targets.
            //   This eliminates the TOCTOU race where the target could be promoted
            //   between a prior role read and the delete.
            // - Owners: can remove admins and members, not other owners.
            let write = if sender_role == "admin" {
                state
                    .db
                    .remove_relay_member_if_role(
                        tenant.community(),
                        &target_hex,
                        "member",
                        &state.relay_keypair,
                    )
                    .await
                    .map_err(|e| format!("database error: {e}"))?
            } else {
                // Owner path — atomic delete that refuses to remove other owners.
                state
                    .db
                    .remove_relay_member(tenant.community(), &target_hex, &state.relay_keypair)
                    .await
                    .map_err(|e| format!("database error: {e}"))?
            };

            match write.outcome {
                RemoveResult::Removed => {}
                RemoveResult::IsOwner => {
                    return Err("cannot remove the relay owner".to_string());
                }
                RemoveResult::NotFound => {
                    return Err(format!("member not found: {target_hex}"));
                }
                RemoveResult::RoleMismatch => {
                    return Err("actor not authorized: admins can only remove members".to_string());
                }
            }

            info!(
                sender = %sender_hex,
                target = %target_hex,
                "relay member removed"
            );

            // Removal ends access now: close the member's and their agents'
            // live sessions (agents hold membership through their owner).
            let revoked = match hex::decode(&target_hex) {
                Ok(target_bytes) => state
                    .revoke_live_access(
                        tenant,
                        &target_bytes,
                        &event.id.to_hex(),
                        "restricted: you were removed from this relay",
                    )
                    .await
                    .map(|_| ()),
                Err(e) => Err(format!("invalid target pubkey: {e}")),
            };

            if let Err(e) = publish_nip43_member_removed(tenant, state, &target_hex).await {
                warn!(error = %e, "failed to publish NIP-43 member removed event");
            }
            fan_out_nip43_membership_list(tenant, state, write.snapshot).await;
            revoked
                .map_err(|e| format!("error: member removed but live revoke incomplete: {e}"))?;
        }

        // kind:9032 — Change relay member role
        k if k == RELAY_ADMIN_CHANGE_ROLE => {
            // Only owners may change roles.
            if sender_role != "owner" {
                return Err("actor not authorized: must be owner".to_string());
            }

            // Cannot change your own role.
            if target_hex == sender_hex {
                return Err("cannot change your own role".to_string());
            }

            let new_role =
                extract_tag_value(event, "role").ok_or_else(|| "missing role tag".to_string())?;

            // DESIGN: Ownership transfer via kind:9032 is intentionally blocked.
            // Transferring ownership is a high-risk operation that could permanently
            // lock out the current owner. Use RELAY_OWNER_PUBKEY config to change ownership.
            if new_role == "owner" {
                return Err("cannot set role to owner".to_string());
            }
            if new_role != "admin" && new_role != "member" {
                return Err(format!("invalid role: {new_role}"));
            }

            let write = state
                .db
                .update_relay_member_role(
                    tenant.community(),
                    &target_hex,
                    &new_role,
                    &state.relay_keypair,
                )
                .await
                .map_err(|e| format!("database error: {e}"))?;

            if !write.outcome {
                // Distinguish "owner (protected)" from "doesn't exist"
                let exists = state
                    .db
                    .get_relay_member(tenant.community(), &target_hex)
                    .await
                    .map_err(|e| format!("database error: {e}"))?;
                return Err(if exists.is_some() {
                    "cannot change the relay owner's role".to_string()
                } else {
                    format!("member not found: {target_hex}")
                });
            }

            info!(
                sender = %sender_hex,
                target = %target_hex,
                new_role = %new_role,
                "relay member role changed"
            );

            fan_out_nip43_membership_list(tenant, state, write.snapshot).await;
        }

        other => {
            return Err(format!("unexpected relay admin kind: {other}"));
        }
    }

    Ok(())
}

#[cfg(test)]
mod postgres_tests {
    use super::*;
    use nostr::{EventBuilder, Keys, Kind, Tag};

    /// The vulnerability this file's ban gate closes: `ingest_event` exempts
    /// relay-admin kinds 9030–9033 from its durable write-path restriction
    /// gate, so a **banned** admin could add/remove relay members and change
    /// the workspace icon over signed NIP-98 `POST /events`. Deleting the
    /// admission check must fail here, in the default (non-ignored) suite.
    #[test]
    fn banned_actor_is_not_admitted_to_a_relay_admin_command() {
        let banned = buzz_db::moderation::RestrictionState {
            banned: true,
            own_banned: true,
            muted_until: None,
        };
        assert_eq!(
            admits_relay_admin_command(&banned),
            Err(RelayAdminError::Banned(
                crate::handlers::auth::BanSource::Own
            )),
            "a durably banned admin must never reach a relay-admin command"
        );
    }

    /// The counter-invariant, and the reason the ingest exemption exists at
    /// all: a timeout restricts *content* writes, not administrative
    /// capability. Widening this gate to timeouts would silently change policy.
    #[test]
    fn timed_out_actor_is_still_admitted() {
        let timed_out = buzz_db::moderation::RestrictionState {
            banned: false,
            own_banned: false,
            muted_until: Some(chrono::Utc::now() + chrono::Duration::minutes(5)),
        };
        assert!(
            admits_relay_admin_command(&timed_out).is_ok(),
            "a timed-out admin must still administer the roster"
        );
    }

    #[test]
    fn unrestricted_actor_is_admitted() {
        assert!(
            admits_relay_admin_command(&buzz_db::moderation::RestrictionState::default()).is_ok()
        );
    }

    /// Build a minimal signed Event with the given kind and tags.
    /// The pubkey will be randomly generated — sufficient for tag extraction tests.
    fn make_test_event(kind: u16, tags: Vec<Vec<&'static str>>) -> Event {
        let keys = Keys::generate();
        let nostr_tags: Vec<Tag> = tags
            .into_iter()
            .map(|parts| Tag::parse(parts).expect("valid tag"))
            .collect();
        EventBuilder::new(Kind::from(kind), "")
            .tags(nostr_tags)
            .sign_with_keys(&keys)
            .expect("signing failed")
    }

    #[test]
    fn extract_p_tag_valid_hex() {
        let hex = "a".repeat(64);
        let event = make_test_event(
            9030,
            vec![vec!["p", Box::leak(hex.clone().into_boxed_str())]],
        );
        assert_eq!(extract_p_tag_hex(&event), Some(hex));
    }

    #[test]
    fn extract_p_tag_rejects_short_hex() {
        let event = make_test_event(9030, vec![vec!["p", "abcd"]]);
        assert_eq!(extract_p_tag_hex(&event), None);
    }

    #[test]
    fn extract_p_tag_rejects_non_hex() {
        // 'g' is not a hex digit
        let event = make_test_event(
            9030,
            vec![vec![
                "p",
                "gggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggg",
            ]],
        );
        assert_eq!(extract_p_tag_hex(&event), None);
    }

    #[test]
    fn extract_p_tag_missing() {
        let event = make_test_event(9030, vec![]);
        assert_eq!(extract_p_tag_hex(&event), None);
    }

    #[test]
    fn extract_p_tag_ignores_non_p_tags() {
        let event = make_test_event(9030, vec![vec!["role", "admin"]]);
        assert_eq!(extract_p_tag_hex(&event), None);
    }

    #[test]
    fn extract_tag_value_found() {
        let event = make_test_event(9030, vec![vec!["role", "admin"]]);
        assert_eq!(extract_tag_value(&event, "role"), Some("admin".to_string()));
    }

    #[test]
    fn extract_tag_value_missing() {
        let event = make_test_event(9030, vec![]);
        assert_eq!(extract_tag_value(&event, "role"), None);
    }

    #[test]
    fn extract_tag_value_returns_first_match() {
        let event = make_test_event(9030, vec![vec!["role", "member"], vec!["role", "admin"]]);
        assert_eq!(
            extract_tag_value(&event, "role"),
            Some("member".to_string())
        );
    }

    #[test]
    fn extract_tag_value_wrong_name() {
        let event = make_test_event(9030, vec![vec!["role", "admin"]]);
        assert_eq!(extract_tag_value(&event, "p"), None);
    }

    #[test]
    fn workspace_icon_empty_ok() {
        assert!(validate_workspace_icon("").is_ok());
    }

    /// Closed relay (membership enforced): only an admin/owner row in
    /// `relay_members` may set the workspace profile — a plain member, or a
    /// pubkey with no row at all (empty role), must be refused. The steward
    /// flag is irrelevant when membership is enforced (call sites pass `true`,
    /// but the rule must not depend on it).
    #[test]
    fn closed_relay_requires_admin_or_owner_for_workspace_profile() {
        for steward in [true, false] {
            assert!(may_set_workspace_profile("owner", true, steward));
            assert!(may_set_workspace_profile("admin", true, steward));
            assert!(!may_set_workspace_profile("member", true, steward));
            assert!(!may_set_workspace_profile("", true, steward));
        }
    }

    /// Open relay with a steward: startup bootstraps `RELAY_OWNER_PUBKEY` as
    /// `owner` regardless of `require_relay_membership`, so an open relay's
    /// community can hold admin/owner rows. When one exists, the icon stays
    /// steward-only — the fix must not widen an owner-controlled icon to
    /// every authenticated key.
    #[test]
    fn open_relay_with_steward_keeps_workspace_profile_steward_only() {
        assert!(may_set_workspace_profile("owner", false, true));
        assert!(may_set_workspace_profile("admin", false, true));
        assert!(!may_set_workspace_profile("member", false, true));
        assert!(!may_set_workspace_profile("", false, true));
    }

    /// Open relay, genuinely rosterless (no admin/owner row anywhere): any
    /// authenticated sender may set the icon — including the roleless (empty
    /// role) case, which is *every* sender there. This is the bug being
    /// fixed: the desktop shows the icon editor on open relays (#2640) but
    /// the relay refused every 9033.
    #[test]
    fn rosterless_open_relay_admits_any_authenticated_sender_for_workspace_profile() {
        assert!(may_set_workspace_profile("", false, false));
        assert!(may_set_workspace_profile("member", false, false));
        assert!(may_set_workspace_profile("owner", false, false));
    }

    #[test]
    fn workspace_icon_https_ok() {
        assert!(validate_workspace_icon("https://example.com/icon.png").is_ok());
    }

    #[test]
    fn workspace_icon_data_url_ok() {
        assert!(validate_workspace_icon("data:image/webp;base64,UklGRg==").is_ok());
    }

    #[test]
    fn workspace_icon_rejects_non_url() {
        assert!(validate_workspace_icon("javascript:alert(1)").is_err());
        assert!(validate_workspace_icon("data:text/html;base64,PGI+").is_err());
    }

    #[test]
    fn workspace_icon_rejects_whitespace_and_control() {
        assert!(validate_workspace_icon("https://example.com/a b.png").is_err());
        assert!(validate_workspace_icon("https://example.com/a\nb.png").is_err());
    }

    #[test]
    fn workspace_icon_rejects_oversized() {
        let long_url = format!("https://example.com/{}.png", "a".repeat(2048));
        assert!(validate_workspace_icon(&long_url).is_err());
        let long_data = format!("data:image/png;base64,{}", "A".repeat(98_304));
        assert!(validate_workspace_icon(&long_data).is_err());
    }

    // ─── Call-site integration: the 9033 gate wired to real config + DB ────
    //
    // The unit tests above pin `may_set_workspace_profile`'s truth table, but
    // not its wiring: mutation-testing showed that inverting
    // `state.config.require_relay_membership` at the call site — an exact
    // inversion of the security contract — survives the default suite. These
    // tests drive `handle_relay_admin_event` with a real `AppState` against
    // Postgres, on both relay modes, so the wiring itself is pinned. Selected
    // explicitly in CI's Backend Integration job; requires local Postgres
    // (and hard-fails rather than skipping when it is unreachable).

    const TEST_DB_URL: &str = "postgres://buzz:buzz_dev@localhost:5432/buzz"; // sadscan:disable np.postgres.1

    /// Build a real `AppState` + tenant for a fresh community on `host`, with
    /// `require_relay_membership` set as given. Mirrors
    /// `api::invites::tests::invite_test_state`.
    async fn workspace_profile_test_state(
        host: &str,
        require_relay_membership: bool,
    ) -> (Arc<AppState>, TenantContext) {
        let mut config = crate::config::Config::for_test(); // [FI-TRACE-ENV-RACE]
        let database_url = std::env::var("BUZZ_TEST_DATABASE_URL")
            .or_else(|_| std::env::var("DATABASE_URL"))
            .unwrap_or_else(|_| TEST_DB_URL.to_string());
        config.database_url = database_url.clone();
        config.redis_url = "redis://127.0.0.1:1".to_string();
        config.relay_url = format!("wss://{host}");
        config.require_relay_membership = require_relay_membership;

        let pool = sqlx::PgPool::connect(&database_url)
            .await
            .expect("requires reachable Postgres");
        let db = buzz_db::Db::from_pool(pool.clone());
        let record = db
            .ensure_configured_community(host)
            .await
            .expect("ensure community");
        let tenant = TenantContext::resolved(record.id, host);

        let redis_pool = deadpool_redis::Config::from_url(&config.redis_url)
            .create_pool(Some(deadpool_redis::Runtime::Tokio1))
            .expect("redis pool config");
        let pubsub = Arc::new(
            buzz_pubsub::PubSubManager::new(&config.redis_url, redis_pool.clone())
                .await
                .expect("pubsub manager"),
        );
        let audit = buzz_audit::AuditService::new(pool.clone());
        let auth = buzz_auth::AuthService::new(config.auth.clone());
        let search = buzz_search::SearchService::new(pool.clone());
        let workflow_engine = Arc::new(buzz_workflow::WorkflowEngine::new(
            db.clone(),
            buzz_workflow::WorkflowConfig::default(),
        ));
        let media_storage = buzz_media::MediaStorage::new(&config.media).expect("media storage");
        let (state, _audit_shutdown) = AppState::new(
            config,
            db,
            redis_pool,
            audit,
            pubsub,
            auth,
            search,
            workflow_engine,
            Keys::generate(),
            media_storage,
        );
        (Arc::new(state), tenant)
    }

    /// Sign a fresh kind:9033 with `icon` and run it through the real
    /// admission + command path.
    async fn submit_9033(
        state: &Arc<AppState>,
        tenant: &TenantContext,
        keys: &Keys,
        icon: &str,
    ) -> Result<(), RelayAdminError> {
        let event = EventBuilder::new(Kind::Custom(9033), "")
            .tags(vec![Tag::parse(["icon", icon]).expect("icon tag")])
            .sign_with_keys(keys)
            .expect("sign 9033");
        handle_relay_admin_event(tenant, state, &event).await
    }

    async fn stored_icon(state: &Arc<AppState>, tenant: &TenantContext) -> Option<String> {
        state
            .db
            .get_community_icon(tenant.community())
            .await
            .expect("read icon")
    }

    /// Open relay (`require_relay_membership = false`): a rosterless
    /// community admits any authenticated sender, but the moment a steward
    /// (admin/owner row) exists the gate reverts to steward-only.
    ///
    /// Discriminating: fails if the call site inverts or drops
    /// `require_relay_membership`, or stops consulting `has_admin_or_owner`.
    #[tokio::test]
    #[ignore = "requires Postgres"]
    async fn open_relay_9033_admits_roleless_only_until_a_steward_exists() {
        let host = format!("icon-gate-open-{}.example", uuid::Uuid::new_v4().simple());
        let (state, tenant) = workspace_profile_test_state(&host, false).await;
        let roleless = Keys::generate();
        let owner = Keys::generate();

        // Rosterless: the roleless sender may set the icon.
        submit_9033(&state, &tenant, &roleless, "https://example.com/open.png")
            .await
            .expect("rosterless open relay must admit an authenticated sender");
        assert_eq!(
            stored_icon(&state, &tenant).await.as_deref(),
            Some("https://example.com/open.png"),
            "icon must actually be stored"
        );

        // Seed a steward — the same roleless sender must now be refused, and
        // the previously stored icon must survive the refused attempt.
        state
            .db
            .add_relay_member(
                tenant.community(),
                &owner.public_key().to_hex(),
                "owner",
                None,
                &nostr::Keys::generate(),
            )
            .await
            .map(|write| write.outcome)
            .expect("seed owner");
        let refused = submit_9033(&state, &tenant, &roleless, "https://evil.example/pwn.png").await;
        assert_eq!(
            refused,
            Err(RelayAdminError::Rejected(
                "actor not authorized: must be admin or owner".to_string()
            )),
            "an open relay with a steward must refuse a roleless sender"
        );
        assert_eq!(
            stored_icon(&state, &tenant).await.as_deref(),
            Some("https://example.com/open.png"),
            "refused attempt must not mutate the icon"
        );

        // The steward still can.
        submit_9033(&state, &tenant, &owner, "https://example.com/owner.png")
            .await
            .expect("the steward must retain icon control");
        assert_eq!(
            stored_icon(&state, &tenant).await.as_deref(),
            Some("https://example.com/owner.png")
        );
    }

    /// Closed relay (`require_relay_membership = true`): admin/owner only —
    /// a plain member and a roleless key are refused even though the
    /// community also *looks* rosterless-then-stewarded to the open-relay
    /// branch. Together with the open-relay test this kills the inverted-flag
    /// mutant: no assignment of the flag satisfies both.
    #[tokio::test]
    #[ignore = "requires Postgres"]
    async fn closed_relay_9033_still_requires_admin_or_owner() {
        let host = format!("icon-gate-closed-{}.example", uuid::Uuid::new_v4().simple());
        let (state, tenant) = workspace_profile_test_state(&host, true).await;
        let roleless = Keys::generate();
        let member = Keys::generate();
        let admin = Keys::generate();
        state
            .db
            .add_relay_member(
                tenant.community(),
                &member.public_key().to_hex(),
                "member",
                None,
                &nostr::Keys::generate(),
            )
            .await
            .map(|write| write.outcome)
            .expect("seed member");
        state
            .db
            .add_relay_member(
                tenant.community(),
                &admin.public_key().to_hex(),
                "admin",
                None,
                &nostr::Keys::generate(),
            )
            .await
            .map(|write| write.outcome)
            .expect("seed admin");

        for (keys, label) in [(&roleless, "roleless"), (&member, "member")] {
            let refused = submit_9033(&state, &tenant, keys, "https://evil.example/pwn.png").await;
            assert_eq!(
                refused,
                Err(RelayAdminError::Rejected(
                    "actor not authorized: must be admin or owner".to_string()
                )),
                "closed relay must refuse a {label} sender"
            );
        }
        assert_eq!(
            stored_icon(&state, &tenant).await,
            None,
            "refused attempts must not set an icon"
        );

        submit_9033(&state, &tenant, &admin, "https://example.com/closed.png")
            .await
            .expect("closed-relay admin must set the icon");
        assert_eq!(
            stored_icon(&state, &tenant).await.as_deref(),
            Some("https://example.com/closed.png")
        );
    }

    /// Member removal (kind 9031) ends the removed member's live sessions,
    /// and no one else's.
    /// Mutation: drop the `revoke_live_access` call from the 9031 arm → RED.
    #[tokio::test]
    #[ignore = "requires Postgres"]
    async fn removing_a_member_closes_their_live_connections() {
        use crate::state::CommunityConnectionControl;
        use tokio_util::sync::CancellationToken;

        let host = format!("remove-revoke-{}.example", uuid::Uuid::new_v4().simple());
        let (state, tenant) = workspace_profile_test_state(&host, true).await;
        let (owner, member, bystander) = (Keys::generate(), Keys::generate(), Keys::generate());
        for (keys, role) in [
            (&owner, "owner"),
            (&member, "member"),
            (&bystander, "member"),
        ] {
            state
                .db
                .add_relay_member(
                    tenant.community(),
                    &keys.public_key().to_hex(),
                    role,
                    None,
                    &nostr::Keys::generate(),
                )
                .await
                .map(|write| write.outcome)
                .expect("seed member");
        }
        let bound = |keys: &Keys| {
            let control = CommunityConnectionControl::new(CancellationToken::new());
            control.bind_pubkey(keys.public_key().to_bytes());
            let guard = state.community_connections.register(
                uuid::Uuid::new_v4(),
                tenant.community(),
                control.clone(),
            );
            (control, guard)
        };
        let (member_socket, _g1) = bound(&member);
        let (bystander_socket, _g2) = bound(&bystander);

        let removal = EventBuilder::new(Kind::Custom(RELAY_ADMIN_REMOVE_MEMBER as u16), "")
            .tags(vec![Tag::public_key(member.public_key())])
            .sign_with_keys(&owner)
            .expect("sign 9031");
        handle_relay_admin_event(&tenant, &state, &removal)
            .await
            .expect("owner removes member");

        assert!(member_socket.cancellation_token().is_cancelled());
        assert!(!bystander_socket.cancellation_token().is_cancelled());
    }

    /// A kind:9030 add joins the new relay member to the community's
    /// effective default channels, once: the flagged open channel gains them
    /// as a member with one kind:44100; the unflagged channel does not. A
    /// kind:9022 leave followed by a repeat kind:9030 (an idempotent no-op on
    /// the roster) does not re-add them. An added agent's `channel_add_policy`
    /// holds against the adder. Mutations: delete the
    /// `auto_join_default_channels` call → RED; pass no actor, or drop the
    /// policy check → the `nobody` agent is joined (RED); check the policy
    /// against anyone but the adder → the owned `owner_only` agent is not
    /// (RED).
    #[tokio::test]
    #[ignore = "requires Postgres"]
    async fn adding_a_member_auto_joins_default_channels() {
        use crate::handlers::group_state_postgres_tests::{
            create_channel, edit_channel, http_auth,
        };
        use crate::handlers::ingest::ingest_event;

        let host = format!("add-auto-join-{}.example", uuid::Uuid::new_v4().simple());
        let (state, tenant) = workspace_profile_test_state(&host, true).await;
        let (owner, target) = (Keys::generate(), Keys::generate());
        state
            .db
            .add_relay_member(
                tenant.community(),
                &owner.public_key().to_hex(),
                "owner",
                None,
                &nostr::Keys::generate(),
            )
            .await
            .map(|write| write.outcome)
            .expect("seed owner");
        let flagged = create_channel(&state, &tenant, &owner, &[]).await;
        let control = create_channel(&state, &tenant, &owner, &[]).await;
        edit_channel(&state, &tenant, &owner, flagged, &[&["auto_join", "true"]])
            .await
            .expect("relay owner flags channel");

        let roles = |keys: &Keys| {
            let state = state.clone();
            let community = tenant.community();
            let pubkey = keys.public_key().to_bytes();
            async move {
                let mut roles = Vec::new();
                for channel_id in [flagged, control] {
                    roles.push(
                        state
                            .db
                            .get_member_role(community, channel_id, &pubkey)
                            .await
                            .expect("member role"),
                    );
                }
                roles
            }
        };
        let added_notifications = || {
            let state = state.clone();
            let community = tenant.community();
            let target_hex = target.public_key().to_hex();
            async move {
                state
                    .db
                    .count_events(&buzz_db::EventQuery {
                        kinds: Some(vec![buzz_core::kind::KIND_MEMBER_ADDED_NOTIFICATION as i32]),
                        p_tag_hex: Some(target_hex),
                        global_only: true,
                        ..buzz_db::EventQuery::for_community(community)
                    })
                    .await
                    .expect("count 44100")
            }
        };
        let add = || {
            EventBuilder::new(Kind::Custom(RELAY_ADMIN_ADD_MEMBER as u16), "")
                .tags(vec![Tag::public_key(target.public_key())])
                .sign_with_keys(&owner)
                .expect("sign 9030")
        };

        handle_relay_admin_event(&tenant, &state, &add())
            .await
            .expect("owner adds member");
        assert_eq!(roles(&target).await, [Some("member".to_string()), None]);
        assert_eq!(added_notifications().await, 1);

        let leave = EventBuilder::new(Kind::Custom(9022), "")
            .tags([Tag::parse(["h", &flagged.to_string()]).expect("h tag")])
            .sign_with_keys(&target)
            .expect("sign 9022");
        let left = ingest_event(&state, &tenant, leave, http_auth(&target))
            .await
            .expect("ingest 9022");
        assert!(left.accepted, "{:?}", left.message);
        handle_relay_admin_event(&tenant, &state, &add())
            .await
            .expect("repeat add is a roster no-op");
        assert_eq!(
            roles(&target).await,
            [None, None],
            "a repeat kind:9030 must not resurrect a kind:9022 leave"
        );
        assert_eq!(added_notifications().await, 1);

        // The adder acts for someone else, so the added agent's
        // `channel_add_policy` decides, as for the same actor's kind:9000:
        // `nobody` refuses every default channel; `owner_only` admits only
        // the agent's owner.
        let (refusing, owned) = (Keys::generate(), Keys::generate());
        for keys in [&owner, &refusing, &owned] {
            state
                .db
                .ensure_user(tenant.community(), &keys.public_key().to_bytes())
                .await
                .expect("user row");
        }
        for (agent, policy) in [(&refusing, "nobody"), (&owned, "owner_only")] {
            state
                .db
                .set_channel_add_policy(tenant.community(), &agent.public_key().to_bytes(), policy)
                .await
                .expect("agent policy");
        }
        state
            .db
            .set_agent_owner(
                tenant.community(),
                &owned.public_key().to_bytes(),
                &owner.public_key().to_bytes(),
            )
            .await
            .expect("agent owner");
        for (agent, expected) in [
            (&refusing, [None, None]),
            (&owned, [Some("member".to_string()), None]),
        ] {
            let add = EventBuilder::new(Kind::Custom(RELAY_ADMIN_ADD_MEMBER as u16), "")
                .tags(vec![Tag::public_key(agent.public_key())])
                .sign_with_keys(&owner)
                .expect("sign 9030");
            handle_relay_admin_event(&tenant, &state, &add)
                .await
                .expect("owner adds agent");
            assert!(
                state
                    .db
                    .get_relay_member(tenant.community(), &agent.public_key().to_hex())
                    .await
                    .expect("relay member")
                    .is_some(),
                "the roster add stands either way"
            );
            assert_eq!(roles(agent).await, expected);
        }
    }

    fn add_with_owner_tags(sender: &Keys, agent: &Keys, tags: &[&[&str]]) -> nostr::Event {
        let mut all = vec![Tag::public_key(agent.public_key())];
        all.extend(tags.iter().map(|tag| Tag::parse(*tag).expect("tag")));
        EventBuilder::new(Kind::Custom(RELAY_ADMIN_ADD_MEMBER as u16), "")
            .tags(all)
            .sign_with_keys(sender)
            .expect("sign 9030")
    }

    /// A kind:9030 that names `owner` for `agent` with the consent of `consenting`.
    fn add_with_owner(
        sender: &Keys,
        agent: &Keys,
        owner: &Keys,
        consenting: &Keys,
    ) -> nostr::Event {
        let owner_hex = owner.public_key().to_hex();
        let message = nostr::secp256k1::Message::from_digest(
            <nostr::hashes::sha256::Hash as nostr::hashes::Hash>::hash(
                format!(
                    "nostr:agent-owner:{}:{owner_hex}",
                    agent.public_key().to_hex()
                )
                .as_bytes(),
            )
            .to_byte_array(),
        );
        let consent = consenting.sign_schnorr(&message).to_string();
        add_with_owner_tags(sender, agent, &[&["owner", &owner_hex, &consent]])
    }

    struct OwnerTagFixture {
        state: Arc<AppState>,
        tenant: TenantContext,
        relay_owner: Keys,
        admin: Keys,
        human: Keys,
    }

    impl OwnerTagFixture {
        async fn new(label: &str) -> Self {
            let host = format!("{label}-{}.example", uuid::Uuid::new_v4().simple());
            let (state, tenant) = workspace_profile_test_state(&host, true).await;
            let fixture = Self {
                state,
                tenant,
                relay_owner: Keys::generate(),
                admin: Keys::generate(),
                human: Keys::generate(),
            };
            for (keys, role) in [
                (&fixture.relay_owner, "owner"),
                (&fixture.admin, "admin"),
                (&fixture.human, "member"),
            ] {
                fixture.seed_member(keys, role, None).await;
            }
            fixture
        }

        async fn seed_member(&self, keys: &Keys, role: &str, added_by: Option<&Keys>) {
            self.state
                .db
                .add_relay_member(
                    self.tenant.community(),
                    &keys.public_key().to_hex(),
                    role,
                    added_by.map(|k| k.public_key().to_hex()).as_deref(),
                    &Keys::generate(),
                )
                .await
                .map(|write| write.outcome)
                .expect("seed member");
        }

        async fn submit(&self, event: &nostr::Event) -> Result<(), RelayAdminError> {
            handle_relay_admin_event(&self.tenant, &self.state, event).await
        }

        async fn is_member(&self, keys: &Keys) -> bool {
            self.state
                .db
                .get_relay_member(self.tenant.community(), &keys.public_key().to_hex())
                .await
                .expect("relay member")
                .is_some()
        }

        async fn owner_of(&self, agent: &Keys) -> Option<Vec<u8>> {
            self.state
                .db
                .get_agent_channel_policy(self.tenant.community(), agent.public_key().as_bytes())
                .await
                .expect("stored owner")
                .and_then(|(_, owner)| owner)
        }

        async fn assert_refused(&self, event: &nostr::Event, reason: &str) {
            match self.submit(event).await {
                Err(RelayAdminError::Rejected(message)) => assert_eq!(
                    message,
                    format!("{OWNER_REFUSED}: {reason}"),
                    "refusal reason"
                ),
                other => panic!("expected a refusal ({reason}), got {other:?}"),
            }
        }
    }

    /// An admin's kind:9030 with the agent's consent adds the agent and
    /// stores its owner, so the owner gates (`is_agent_owner`: kind:44200,
    /// observer frames) pass; a socket the agent holds without an owner is
    /// closed so that it reconnects with the owner attached; a repeat is a
    /// no-op. Mutations: ignore the tag → no stored owner (RED); drop
    /// `disconnect_unowned_agent_clusterwide` → the socket stays (RED); skip
    /// the cache writes → the cached negative stays (RED).
    #[tokio::test]
    #[ignore = "requires Postgres"]
    async fn admin_adds_an_agent_with_its_owner() {
        let f = OwnerTagFixture::new("owner-tag-add").await;
        let (agent, bystander) = (Keys::generate(), Keys::generate());
        let community = f.tenant.community();
        let agent_socket = bound_root_socket(&f.state, community, &agent);
        let bystander_socket = bound_root_socket(&f.state, community, &bystander);
        let cache_key = (
            community,
            agent.public_key().to_bytes().to_vec(),
            f.human.public_key().to_bytes().to_vec(),
        );
        f.state
            .observer_owner_cache
            .insert(cache_key.clone(), false);

        let add = add_with_owner(&f.admin, &agent, &f.human, &agent);
        f.submit(&add)
            .await
            .expect("admin adds the agent with its owner");

        let member = f
            .state
            .db
            .get_relay_member(community, &agent.public_key().to_hex())
            .await
            .expect("relay member")
            .expect("agent is a member");
        assert_eq!(
            (member.role.as_str(), member.added_by),
            ("member", Some(f.admin.public_key().to_hex()))
        );
        assert!(f
            .state
            .db
            .is_agent_owner(
                community,
                agent.public_key().as_bytes(),
                f.human.public_key().as_bytes()
            )
            .await
            .expect("owner lookup"));
        assert_eq!(f.state.observer_owner_cache.get(&cache_key), Some(true));
        assert!(
            agent_socket.is_cancelled(),
            "ownerless agent socket reconnects"
        );
        assert!(!bystander_socket.is_cancelled());

        let again = bound_root_socket(&f.state, community, &agent);
        f.submit(&add_with_owner(&f.admin, &agent, &f.human, &agent))
            .await
            .expect("a repeat with the same owner is accepted");
        assert!(!again.is_cancelled(), "a repeat changes nothing");
    }

    /// The refusals of a kind:9030 `owner` tag. Each leaves the roster and
    /// the stored owners as they were: the add and the owner are one write.
    /// Mutations: drop the consent check → a member is made an agent without
    /// its key (RED); drop a refusal in `assign_agent_owner_in` → its case is
    /// RED; commit a refused add → the agent is a member afterwards (RED).
    #[tokio::test]
    #[ignore = "requires Postgres"]
    async fn owner_tag_refusals_change_nothing() {
        let f = OwnerTagFixture::new("owner-tag-refuse").await;
        let (outsider, owned_agent, other_admin) =
            (Keys::generate(), Keys::generate(), Keys::generate());
        f.seed_member(&other_admin, "admin", None).await;
        f.submit(&add_with_owner(
            &f.admin,
            &owned_agent,
            &f.human,
            &owned_agent,
        ))
        .await
        .expect("seed an owned agent");
        let human_hex = f.human.public_key().to_hex();

        let fresh = Keys::generate();
        for (event, reason) in [
            (
                add_with_owner(&f.admin, &fresh, &f.human, &f.admin),
                "invalid input: consent signature is not by the agent for this owner",
            ),
            (
                add_with_owner(&f.admin, &fresh, &f.human, &f.human),
                "invalid input: consent signature is not by the agent for this owner",
            ),
            (
                add_with_owner_tags(&f.admin, &fresh, &[&["owner", &human_hex]]),
                "owner tag must hold the owner pubkey and the agent's consent signature",
            ),
            (
                {
                    let one = add_with_owner(&f.admin, &fresh, &f.human, &fresh);
                    let tag: Vec<String> = one
                        .tags
                        .iter()
                        .map(|t| t.as_slice().to_vec())
                        .find(|t| t[0] == "owner")
                        .expect("owner tag");
                    let tag: Vec<&str> = tag.iter().map(String::as_str).collect();
                    add_with_owner_tags(&f.admin, &fresh, &[&tag, &tag])
                },
                "more than one owner tag",
            ),
            (
                add_with_owner(&f.admin, &fresh, &outsider, &fresh),
                "the owner is not a relay member",
            ),
            (
                add_with_owner(&f.admin, &fresh, &owned_agent, &fresh),
                "the owner is itself an agent",
            ),
        ] {
            f.assert_refused(&event, reason).await;
            assert!(!f.is_member(&fresh).await, "{reason}: the add is undone");
            assert_eq!(f.owner_of(&fresh).await, None, "{reason}");
        }
        let with_admin_role = {
            let plain = add_with_owner(&f.relay_owner, &fresh, &f.human, &fresh);
            let owner_tag: Vec<String> = plain
                .tags
                .iter()
                .map(|t| t.as_slice().to_vec())
                .find(|t| t[0] == "owner")
                .expect("owner tag");
            let owner_tag: Vec<&str> = owner_tag.iter().map(String::as_str).collect();
            add_with_owner_tags(&f.relay_owner, &fresh, &[&["role", "admin"], &owner_tag])
        };
        f.assert_refused(
            &with_admin_role,
            "the agent must be a relay member with the member role",
        )
        .await;
        assert!(!f.is_member(&fresh).await);

        // An agent keeps its owner.
        f.assert_refused(
            &add_with_owner(&f.admin, &owned_agent, &f.admin, &owned_agent),
            "the agent has a different owner",
        )
        .await;
        f.assert_refused(
            &add_with_owner(&f.relay_owner, &owned_agent, &f.relay_owner, &owned_agent),
            "the agent has a different owner",
        )
        .await;
        assert_eq!(
            f.owner_of(&owned_agent).await,
            Some(f.human.public_key().to_bytes().to_vec())
        );

        // A member that owns agents, and an admin, cannot become agents.
        f.assert_refused(
            &add_with_owner(&f.relay_owner, &f.human, &f.relay_owner, &f.human),
            "the agent is the owner of other agents",
        )
        .await;
        f.assert_refused(
            &add_with_owner(&f.relay_owner, &other_admin, &f.human, &other_admin),
            "the agent must be a relay member with the member role",
        )
        .await;

        // An admin sets the owner only of a member it added; the relay owner
        // is not bound by that.
        let (unowned, by_other_admin) = (Keys::generate(), Keys::generate());
        f.seed_member(&unowned, "member", None).await;
        f.seed_member(&by_other_admin, "member", Some(&other_admin))
            .await;
        for agent in [&unowned, &by_other_admin] {
            f.assert_refused(
                &add_with_owner(&f.admin, agent, &f.human, agent),
                "an admin can set the owner only of a member it added",
            )
            .await;
            assert!(f.is_member(agent).await, "an existing member stays");
            assert_eq!(f.owner_of(agent).await, None);
        }
        f.submit(&add_with_owner(
            &other_admin,
            &by_other_admin,
            &f.human,
            &by_other_admin,
        ))
        .await
        .expect("the admin that added the member sets its owner");
        f.submit(&add_with_owner(
            &f.relay_owner,
            &unowned,
            &f.human,
            &unowned,
        ))
        .await
        .expect("the relay owner sets the owner of any member");

        // A plain member cannot use the tag at all.
        match f
            .submit(&add_with_owner(&f.human, &fresh, &f.human, &fresh))
            .await
        {
            Err(RelayAdminError::Rejected(message)) => {
                assert_eq!(message, "actor not authorized: must be admin or owner")
            }
            other => panic!("{other:?}"),
        }
        assert!(!f.is_member(&fresh).await);
    }

    /// The owner must be a member of the community the command is sent to,
    /// and the owner is stored there only. Mutation: read the owner's
    /// membership or write the owner without the community → RED.
    #[tokio::test]
    #[ignore = "requires Postgres"]
    async fn owner_tag_stays_inside_one_community() {
        let here = OwnerTagFixture::new("owner-tag-here").await;
        let host = format!("owner-tag-there-{}.example", uuid::Uuid::new_v4().simple());
        let there = here
            .state
            .db
            .ensure_configured_community(&host)
            .await
            .expect("second community");
        let there = TenantContext::resolved(there.id, &host);
        let (agent, foreign_owner) = (Keys::generate(), Keys::generate());
        here.state
            .db
            .add_relay_member(
                there.community(),
                &foreign_owner.public_key().to_hex(),
                "member",
                None,
                &Keys::generate(),
            )
            .await
            .map(|write| write.outcome)
            .expect("member of the other community");

        here.assert_refused(
            &add_with_owner(&here.admin, &agent, &foreign_owner, &agent),
            "the owner is not a relay member",
        )
        .await;
        let add = add_with_owner(&here.admin, &agent, &here.human, &agent);
        match handle_relay_admin_event(&there, &here.state, &add).await {
            Err(RelayAdminError::Rejected(message)) => {
                assert_eq!(message, "actor not authorized: must be admin or owner")
            }
            other => panic!("an admin of one community acted in another: {other:?}"),
        }

        here.submit(&add)
            .await
            .expect("add in the admin's community");
        for (community, expected) in [(here.tenant.community(), true), (there.community(), false)] {
            assert_eq!(
                here.state
                    .db
                    .is_agent_owner(
                        community,
                        agent.public_key().as_bytes(),
                        here.human.public_key().as_bytes()
                    )
                    .await
                    .expect("owner lookup"),
                expected
            );
        }
        assert!(here
            .state
            .db
            .get_relay_member(there.community(), &agent.public_key().to_hex())
            .await
            .expect("relay member")
            .is_none());
    }

    /// A pod-local root socket registered and bound to `keys`, as root AUTH
    /// leaves it.
    fn bound_root_socket(
        state: &crate::state::AppState,
        community: buzz_core::tenant::CommunityId,
        keys: &Keys,
    ) -> tokio_util::sync::CancellationToken {
        let (tx, _rx) = tokio::sync::mpsc::channel(4);
        let (ctrl, _ctrl_rx) = tokio::sync::mpsc::channel(4);
        let (terminal, _terminal_rx) = tokio::sync::mpsc::channel(1);
        let cancel = tokio_util::sync::CancellationToken::new();
        let conn_id = uuid::Uuid::new_v4();
        state.conn_manager.register(
            conn_id,
            tx,
            ctrl,
            terminal,
            None,
            cancel.clone(),
            community,
            std::sync::Arc::new(std::sync::atomic::AtomicU8::new(0)),
            std::sync::Arc::new(tokio::sync::Mutex::new(std::collections::HashMap::new())),
            3,
            crate::state::CommunityConnectionControl::new(cancel.clone()),
        );
        state
            .conn_manager
            .set_authenticated_pubkey(conn_id, keys.public_key().to_bytes().to_vec());
        cancel
    }

    /// Live sockets around a NIP-43 self-leave: the member's root and audio
    /// sockets, their owned agent's root and audio sockets, and the member's
    /// root socket in another community.
    struct SelfLeaveFixture {
        state: std::sync::Arc<crate::state::AppState>,
        tenant: buzz_core::tenant::TenantContext,
        member: Keys,
        closing: Vec<(&'static str, tokio_util::sync::CancellationToken)>,
        other_community: tokio_util::sync::CancellationToken,
        _guards: Vec<crate::state::CommunityConnectionGuard>,
    }

    async fn self_leave_fixture() -> SelfLeaveFixture {
        use crate::state::CommunityConnectionControl;
        use tokio_util::sync::CancellationToken;

        let host = format!("self-leave-{}.example", uuid::Uuid::new_v4().simple());
        let (state, tenant) = workspace_profile_test_state(&host, true).await;
        let other_host = format!(
            "self-leave-control-{}.example",
            uuid::Uuid::new_v4().simple()
        );
        let (_, other_tenant) = workspace_profile_test_state(&other_host, true).await;
        let (member, agent) = (Keys::generate(), Keys::generate());
        state
            .db
            .add_relay_member(
                tenant.community(),
                &member.public_key().to_hex(),
                "member",
                None,
                &nostr::Keys::generate(),
            )
            .await
            .map(|write| write.outcome)
            .expect("seed member");
        for keys in [&member, &agent] {
            state
                .db
                .ensure_user(tenant.community(), keys.public_key().as_bytes())
                .await
                .expect("ensure user");
        }
        assert!(state
            .db
            .set_agent_owner(
                tenant.community(),
                agent.public_key().as_bytes(),
                member.public_key().as_bytes(),
            )
            .await
            .expect("link agent"));

        let mut guards = Vec::new();
        let mut audio = |keys: &Keys| {
            let control = CommunityConnectionControl::new(CancellationToken::new());
            control.bind_pubkey(keys.public_key().to_bytes());
            guards.push(state.community_connections.register(
                uuid::Uuid::new_v4(),
                tenant.community(),
                control.clone(),
            ));
            control.cancellation_token()
        };
        let closing = vec![
            ("member audio", audio(&member)),
            ("agent audio", audio(&agent)),
            (
                "member root",
                bound_root_socket(&state, tenant.community(), &member),
            ),
            (
                "agent root",
                bound_root_socket(&state, tenant.community(), &agent),
            ),
        ];
        let other_community = bound_root_socket(&state, other_tenant.community(), &member);
        SelfLeaveFixture {
            state,
            tenant,
            member,
            closing,
            other_community,
            _guards: guards,
        }
    }

    fn signed_leave(keys: &Keys) -> nostr::Event {
        EventBuilder::new(
            Kind::Custom(buzz_core::kind::KIND_NIP43_LEAVE_REQUEST as u16),
            "",
        )
        .tags([nostr::Tag::parse(["-"]).unwrap()])
        .sign_with_keys(keys)
        .expect("sign leave")
    }

    fn assert_left(f: &SelfLeaveFixture) {
        for (name, socket) in &f.closing {
            assert!(socket.is_cancelled(), "the {name} socket closes");
        }
        assert!(
            !f.other_community.is_cancelled(),
            "the member's socket in another community stays open"
        );
    }

    /// A NIP-43 self-leave ends access now: the member's and their owned
    /// agent's sockets close; the member's socket in another community stays.
    /// Mutation: drop `revoke_live_access` from the leave path → RED.
    #[tokio::test]
    #[ignore = "requires Postgres — runs in postgres-ci nextest lane"]
    async fn self_leave_closes_member_audio_and_agent_sockets() {
        let f = self_leave_fixture().await;
        let auth = crate::handlers::ingest::IngestAuth::Http {
            pubkey: f.member.public_key(),
            scopes: vec![buzz_auth::Scope::ChannelsRead],
            auth_method: crate::handlers::ingest::HttpAuthMethod::Nip98,
        };
        crate::handlers::ingest::ingest_event(&f.state, &f.tenant, signed_leave(&f.member), auth)
            .await
            .expect("member leaves");
        assert_left(&f);
    }

    /// A leave sent as `EVENT` over an authenticated WebSocket removes the
    /// membership and closes the same sockets. Kind 28936 is in the ephemeral
    /// range, so it must be routed to ingest, not the ephemeral fan-out.
    /// Mutation: drop the leave exclusion from `handle_event`'s ephemeral
    /// branch → `OK true`, membership kept, sockets open → RED.
    #[tokio::test]
    #[ignore = "requires Postgres — runs in postgres-ci nextest lane"]
    async fn websocket_self_leave_removes_membership_and_closes_sockets() {
        let f = self_leave_fixture().await;
        let auth = crate::connection::AuthState::Authenticated(buzz_auth::AuthContext {
            pubkey: f.member.public_key(),
            scopes: buzz_auth::Scope::all_known(),
            channel_ids: None,
            auth_method: buzz_auth::AuthMethod::Nip42,
            agent_owner_pubkey: None,
        });
        let (mut conn, mut sent) = crate::connection::tests::test_conn_with_auth(auth);
        std::sync::Arc::get_mut(&mut conn).unwrap().tenant = f.tenant.clone();
        let leave = signed_leave(&f.member);
        crate::handlers::event::handle_event(leave.clone(), conn, f.state.clone()).await;

        let axum::extract::ws::Message::Text(ack) = sent.try_recv().expect("OK frame") else {
            panic!("expected an OK frame");
        };
        let ack: serde_json::Value = serde_json::from_str(&ack).unwrap();
        assert_eq!(ack[1], leave.id.to_hex());
        assert_eq!(ack[2], true, "the leave is accepted: {ack}");
        assert!(
            !f.state
                .db
                .is_relay_member_writer(f.tenant.community(), &f.member.public_key().to_hex())
                .await
                .expect("membership read"),
            "the membership row is gone"
        );
        assert_left(&f);
    }

    /// A direct ban (kind 9040) whose audit insert fails still closes the
    /// banned member's socket, and the command still reports the failure.
    /// A bystander stays connected.
    /// Mutation: move `revoke_live_access` back after `insert_audit(...)?`
    /// in `handle_ban` → the socket stays open → RED.
    #[tokio::test]
    #[ignore = "requires Postgres — runs in postgres-ci nextest lane"]
    async fn ban_closes_socket_even_when_audit_insert_fails() {
        let host = format!("ban-audit-{}.example", uuid::Uuid::new_v4().simple());
        let (state, tenant) = workspace_profile_test_state(&host, true).await;
        let (owner, target, bystander) = (Keys::generate(), Keys::generate(), Keys::generate());
        for (keys, role) in [
            (&owner, "owner"),
            (&target, "member"),
            (&bystander, "member"),
        ] {
            state
                .db
                .add_relay_member(
                    tenant.community(),
                    &keys.public_key().to_hex(),
                    role,
                    None,
                    &nostr::Keys::generate(),
                )
                .await
                .map(|write| write.outcome)
                .expect("seed member");
        }
        let target_socket = bound_root_socket(&state, tenant.community(), &target);
        let bystander_socket = bound_root_socket(&state, tenant.community(), &bystander);

        // Audit inserts fail for this community only.
        let suffix = uuid::Uuid::new_v4().simple().to_string();
        let community = *tenant.community().as_uuid();
        sqlx::raw_sql(sqlx::AssertSqlSafe(format!(
            "CREATE FUNCTION fail_audit_{suffix}() RETURNS trigger AS $$ BEGIN \
               IF NEW.community_id = '{community}' THEN RAISE EXCEPTION 'audit unavailable'; END IF; \
               RETURN NEW; END $$ LANGUAGE plpgsql; \
             CREATE TRIGGER fail_audit_{suffix} BEFORE INSERT ON moderation_actions \
               FOR EACH ROW EXECUTE FUNCTION fail_audit_{suffix}();"
        )))
        .execute(state.db.pool())
        .await
        .expect("install audit-failure trigger");

        let ban = EventBuilder::new(
            Kind::Custom(buzz_core::kind::KIND_MODERATION_BAN as u16),
            "",
        )
        .tags([Tag::public_key(target.public_key())])
        .sign_with_keys(&owner)
        .expect("sign 9040");
        let result =
            crate::handlers::moderation_commands::handle_moderation_command(&tenant, &state, &ban)
                .await;

        let _ = sqlx::raw_sql(sqlx::AssertSqlSafe(format!(
            "DROP TRIGGER fail_audit_{suffix} ON moderation_actions; \
             DROP FUNCTION fail_audit_{suffix}();"
        )))
        .execute(state.db.pool())
        .await;

        let error = result.expect_err("the audit failure is reported");
        assert!(
            matches!(&error, crate::handlers::ingest::IngestError::Rejected(m) if m.contains("audit")),
            "reports the audit failure: {error:?}"
        );
        assert!(
            state
                .db
                .moderation_restriction_state(tenant.community(), target.public_key().as_bytes())
                .await
                .expect("restriction read")
                .banned,
            "the ban committed"
        );
        assert!(target_socket.is_cancelled(), "the banned socket closes");
        assert!(!bystander_socket.is_cancelled(), "the bystander stays");
    }

    /// A timeout and an untimeout each drop the target's cached restriction
    /// row on the pod that handles them, so typing and observer frames see
    /// the change at once instead of after the cache TTL.
    /// Mutation: remove `invalidate_restriction_cache` from either → RED.
    #[tokio::test]
    #[ignore = "requires Postgres — runs in postgres-ci nextest lane"]
    async fn timeout_commands_drop_the_cached_restriction_row() {
        let host = format!("timeout-cache-{}.example", uuid::Uuid::new_v4().simple());
        let (state, tenant) = workspace_profile_test_state(&host, true).await;
        let (owner, target) = (Keys::generate(), Keys::generate());
        for (keys, role) in [(&owner, "owner"), (&target, "member")] {
            state
                .db
                .add_relay_member(
                    tenant.community(),
                    &keys.public_key().to_hex(),
                    role,
                    None,
                    &nostr::Keys::generate(),
                )
                .await
                .map(|write| write.outcome)
                .expect("seed member");
        }
        let key = (tenant.community(), target.public_key().to_bytes().to_vec());
        let until = (chrono::Utc::now() + chrono::Duration::hours(1)).timestamp();
        let command = |kind: u32, tags: Vec<Tag>| {
            EventBuilder::new(Kind::Custom(kind as u16), "")
                .tags(tags)
                .sign_with_keys(&owner)
                .expect("sign moderation command")
        };

        for event in [
            command(
                buzz_core::kind::KIND_MODERATION_TIMEOUT,
                vec![
                    Tag::public_key(target.public_key()),
                    Tag::parse(["expiration", &until.to_string()]).expect("expiration tag"),
                ],
            ),
            command(
                buzz_core::kind::KIND_MODERATION_UNTIMEOUT,
                vec![Tag::public_key(target.public_key())],
            ),
        ] {
            state.seed_restriction(
                key.clone(),
                buzz_db::moderation::RestrictionState::default(),
            );
            crate::handlers::moderation_commands::handle_moderation_command(
                &tenant, &state, &event,
            )
            .await
            .unwrap_or_else(|e| panic!("kind {} must apply: {e:?}", event.kind.as_u16()));
            assert_eq!(
                state.restriction_cache.get(&key).map(|cached| cached.state),
                None,
                "kind {} must drop the cached row",
                event.kind.as_u16()
            );
        }
    }
}
