//! NIP-OL: write rules for the Olympus agent kinds (30190, 30191, 30192, 44310, 44311).

use std::sync::Arc;

use buzz_core::kind::{
    KIND_OLYMPUS_AGENT, KIND_OLYMPUS_CHANGE_REQUEST, KIND_OLYMPUS_CHANGE_RESULT,
    KIND_OLYMPUS_PROPOSAL, KIND_OLYMPUS_WORKSPACE, OLYMPUS_KINDS,
};
use buzz_core::tenant::TenantContext;
use nostr::Event;

use super::ingest::IngestError;
use crate::state::AppState;

const MAX_D_TAG_BYTES: usize = 255;

fn tag_values<'a>(event: &'a Event, name: &str) -> Vec<&'a str> {
    event
        .tags
        .iter()
        .filter_map(|tag| {
            let parts = tag.as_slice();
            (parts.first().map(String::as_str) == Some(name))
                .then(|| parts.get(1).map_or("", String::as_str))
        })
        .collect()
}

fn is_lower_hex64(value: &str) -> bool {
    value.len() == 64
        && value
            .bytes()
            .all(|b| matches!(b, b'0'..=b'9' | b'a'..=b'f'))
}

fn one_status<'a>(event: &'a Event, allowed: &[&str]) -> Result<&'a str, String> {
    match tag_values(event, "status").as_slice() {
        [status] if allowed.contains(status) => Ok(status),
        [status] => Err(format!(
            "`status` tag must be one of {allowed:?}, got {status:?}"
        )),
        other => Err(format!(
            "exactly one `status` tag required (got {})",
            other.len()
        )),
    }
}

/// Check the tag shape of a NIP-OL event; `Ok` for every other kind.
pub(crate) fn validate_envelope(event: &Event) -> Result<(), String> {
    let kind = buzz_core::kind::event_kind_u32(event);
    if !OLYMPUS_KINDS.contains(&kind) {
        return Ok(());
    }
    if !tag_values(event, "h").is_empty() {
        return Err("Olympus events are global and must not have an `h` tag".into());
    }
    let p = tag_values(event, "p");
    let max_p = if kind == KIND_OLYMPUS_CHANGE_REQUEST {
        1
    } else {
        4
    };
    if p.is_empty() || p.len() > max_p {
        return Err(format!(
            "kind {kind} needs 1 to {max_p} `p` tags (got {})",
            p.len()
        ));
    }
    if !p.iter().all(|value| is_lower_hex64(value)) {
        return Err("`p` tag must be 64 lowercase hex chars".into());
    }
    match kind {
        KIND_OLYMPUS_AGENT | KIND_OLYMPUS_WORKSPACE | KIND_OLYMPUS_PROPOSAL => {
            match tag_values(event, "d").as_slice() {
                [d] if !d.is_empty() && d.len() <= MAX_D_TAG_BYTES => {}
                [_] => return Err(format!("`d` tag must be 1 to {MAX_D_TAG_BYTES} bytes")),
                other => {
                    return Err(format!(
                        "exactly one `d` tag required (got {})",
                        other.len()
                    ))
                }
            }
            one_status(event, &["active", "deleted"])?;
        }
        KIND_OLYMPUS_CHANGE_RESULT => {
            match tag_values(event, "e").as_slice() {
                [e] if is_lower_hex64(e) => {}
                [_] => return Err("`e` tag must be a 64 lowercase hex event id".into()),
                other => {
                    return Err(format!(
                        "exactly one `e` tag required (got {})",
                        other.len()
                    ))
                }
            }
            one_status(event, &["accepted", "refused"])?;
        }
        _ => {}
    }
    Ok(())
}

/// Accept Olympus state, proposals, and results (30190, 30191, 30192, 44311) only from a configured Olympus
/// operator key with relay role `owner` or `admin`, and a change request (44310) only from the
/// relay `owner`, addressed to a configured operator key. Call after [`validate_envelope`].
pub(crate) async fn authorize_author(
    tenant: &TenantContext,
    state: &Arc<AppState>,
    event: &Event,
) -> Result<(), IngestError> {
    let operators = &state.config.olympus_operator_pubkeys;
    let request = buzz_core::kind::event_kind_u32(event) == KIND_OLYMPUS_CHANGE_REQUEST;
    let listed = if request {
        tag_values(event, "p")
            .iter()
            .all(|p| operators.iter().any(|operator| operator == p))
    } else {
        operators.contains(&event.pubkey.to_hex())
    };
    if !listed {
        return Err(IngestError::AuthFailed(if request {
            "restricted: Olympus change requests must name a configured Olympus operator".into()
        } else {
            "restricted: Olympus state requires a configured Olympus operator key".into()
        }));
    }
    let role = state
        .db
        .get_relay_member(tenant.community(), &event.pubkey.to_hex())
        .await
        .map_err(|e| IngestError::Internal(format!("error: relay role lookup: {e}")))?
        .map(|member| member.role);
    match (request, role.as_deref()) {
        (true, Some("owner")) | (false, Some("owner" | "admin")) => Ok(()),
        (true, _) => Err(IngestError::AuthFailed(
            "restricted: Olympus change requests require the relay owner".into(),
        )),
        (false, _) => Err(IngestError::AuthFailed(
            "restricted: Olympus state requires a relay owner or admin".into(),
        )),
    }
}

/// Whether a kind 5 names a NIP-OL kind in a `k` tag. These events are never deleted; the
/// operator publishes a `deleted` tombstone instead.
pub(crate) fn deletion_names_olympus_kind(event: &Event) -> bool {
    buzz_core::kind::k_tag_kinds(event).any(|kind| OLYMPUS_KINDS.contains(&kind))
}

#[cfg(test)]
mod tests {
    use super::*;
    use nostr::{EventBuilder, Keys, Kind, Tag};

    const HEX_A: &str = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    const HEX_B: &str = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";

    fn event(kind: u32, tags: &[&[&str]]) -> Event {
        EventBuilder::new(Kind::Custom(kind as u16), "")
            .tags(
                tags.iter()
                    .map(|tag| Tag::parse(tag.iter().copied()).unwrap()),
            )
            .sign_with_keys(&Keys::generate())
            .unwrap()
    }

    #[test]
    fn envelope_table() {
        let long_d = "x".repeat(MAX_D_TAG_BYTES + 1);
        let max_d = "x".repeat(MAX_D_TAG_BYTES);
        let upper = HEX_A.to_uppercase();
        let short = &HEX_A[..63];
        let h = "6f4b2a52-8c3e-4c47-9d6a-0f4c7e7f2f11";
        let ok = true;
        let bad = false;
        let cases: &[(u32, &[&[&str]], bool)] = &[
            (
                30190,
                &[
                    &["d", "olympus-dev/proof"],
                    &["p", HEX_A],
                    &["p", HEX_B],
                    &["workspace", "dev"],
                    &["status", "active"],
                ],
                ok,
            ),
            (
                30190,
                &[&["d", &max_d], &["p", HEX_A], &["status", "deleted"]],
                ok,
            ),
            (
                30191,
                &[
                    &["d", "dev"],
                    &["p", HEX_A],
                    &["p", HEX_B],
                    &["status", "active"],
                ],
                ok,
            ),
            (
                30192,
                &[
                    &["d", "p-0123456789ab"],
                    &["p", HEX_A],
                    &["p", HEX_B],
                    &["workspace", "dev"],
                    &["requester", HEX_A],
                    &["status", "active"],
                ],
                ok,
            ),
            (30192, &[&["p", HEX_A], &["status", "active"]], bad),
            (
                30192,
                &[&["d", "p-1"], &["p", HEX_A], &["status", "applied"]],
                bad,
            ),
            (
                44310,
                &[
                    &["p", HEX_B],
                    &["workspace", "dev"],
                    &["agent", "proof"],
                    &["action", "suspend"],
                ],
                ok,
            ),
            (
                44311,
                &[
                    &["e", HEX_A],
                    &["p", HEX_A],
                    &["p", HEX_B],
                    &["status", "refused"],
                ],
                ok,
            ),
            (30190, &[&["d", "a"], &["status", "active"]], bad),
            (
                30190,
                &[&["d", "a"], &["p", short], &["status", "active"]],
                bad,
            ),
            (
                30190,
                &[&["d", "a"], &["p", &upper], &["status", "active"]],
                bad,
            ),
            (30190, &[&["d", "a"], &["p"], &["status", "active"]], bad),
            (
                30190,
                &[
                    &["d", "a"],
                    &["p", HEX_A],
                    &["p", HEX_A],
                    &["p", HEX_A],
                    &["p", HEX_A],
                    &["p", HEX_A],
                    &["status", "active"],
                ],
                bad,
            ),
            (
                30190,
                &[
                    &["d", "a"],
                    &["d", "b"],
                    &["p", HEX_A],
                    &["status", "active"],
                ],
                bad,
            ),
            (30190, &[&["p", HEX_A], &["status", "active"]], bad),
            (
                30190,
                &[&["d", ""], &["p", HEX_A], &["status", "active"]],
                bad,
            ),
            (30190, &[&["d"], &["p", HEX_A], &["status", "active"]], bad),
            (
                30191,
                &[&["d", &long_d], &["p", HEX_A], &["status", "active"]],
                bad,
            ),
            (30190, &[&["d", "a"], &["p", HEX_A]], bad),
            (
                30191,
                &[&["d", "a"], &["p", HEX_A], &["status", "accepted"]],
                bad,
            ),
            (
                30191,
                &[
                    &["d", "a"],
                    &["p", HEX_A],
                    &["status", "active"],
                    &["status", "active"],
                ],
                bad,
            ),
            (
                30190,
                &[&["d", "a"], &["p", HEX_A], &["status", "active"], &["h", h]],
                bad,
            ),
            (44310, &[&["p", HEX_A], &["p", HEX_B]], bad),
            (44310, &[], bad),
            (44310, &[&["p", HEX_B], &["h", h]], bad),
            (44311, &[&["p", HEX_A], &["status", "accepted"]], bad),
            (
                44311,
                &[
                    &["e", HEX_A],
                    &["e", HEX_B],
                    &["p", HEX_A],
                    &["status", "accepted"],
                ],
                bad,
            ),
            (
                44311,
                &[&["e", "abc"], &["p", HEX_A], &["status", "accepted"]],
                bad,
            ),
            (44311, &[&["e", HEX_A], &["p", HEX_A]], bad),
            (
                44311,
                &[&["e", HEX_A], &["p", HEX_A], &["status", "active"]],
                bad,
            ),
            (
                44311,
                &[
                    &["e", HEX_A],
                    &["p", HEX_A],
                    &["status", "accepted"],
                    &["h", h],
                ],
                bad,
            ),
            (1, &[&["h", h]], ok),
        ];
        for (kind, tags, expected) in cases {
            let result = validate_envelope(&event(*kind, tags));
            assert_eq!(
                result.is_ok(),
                *expected,
                "kind {kind} tags {tags:?}: {result:?}"
            );
        }
    }

    #[test]
    fn deletion_naming_table() {
        for (k, expected) in [
            ("30190", true),
            ("30191", true),
            ("44310", true),
            ("44311", true),
            ("44200", false),
            ("030190", false),
        ] {
            let ev = event(5, &[&["e", HEX_A], &["k", k]]);
            assert_eq!(deletion_names_olympus_kind(&ev), expected, "k={k}");
        }
        assert!(!deletion_names_olympus_kind(&event(5, &[&["e", HEX_A]])));
    }
}
