NIP-OL
======

Olympus Agents
--------------

`draft` `optional` `relay` `fork`

Five fork-only kinds let the Olympus app show and change the agents and
workspaces that the Hephaestus operator runs. The operator publishes state
and the change proposals of agents (Zeus); the owner sends change requests,
also to approve or reject a proposal; the operator answers each request with
a result. The full tag and content shapes are in the Olympus agents event
contract (`build/hephaestus/olympus-agents/contract.md`); this file states
what the relay enforces.

## Kinds

| Kind | Name | Type | Author |
|---|---|---|---|
| 30190 | Agent state | addressable, `d` = `<namespace>/<name>` | operator |
| 30191 | Workspace state | addressable, `d` = `<workspace>` | operator |
| 30192 | Change proposal | addressable, `d` = proposal name | operator |
| 44310 | Change request | regular, stored | owner |
| 44311 | Change result | regular, stored | operator |

Content is JSON with `"v": 1`. 30190 and 30191 carry the object spec and
status when `status` is `active`, and an empty string when `status` is
`deleted` (a tombstone). 44310 carries the action and its parameters. 44311
carries `status`, `reason`, and the request id. 30192 carries one change
proposal of an agent: target, JSON merge patch, diff, reason, high-risk marks,
digest, and phase; the owner approves or rejects it with a 44310 (`approve`
or `reject`, with the digest).

## Tags

All hex values are 64 lowercase hex characters.

- All kinds: 1 to 4 `p` tags (44310: exactly one, the operator). No `h` tag.
- 30190, 30191, 30192: exactly one non-empty `d` tag of at most 255 bytes, and
  exactly one `status` tag, `active` or `deleted`.
- 44311: exactly one `e` tag (the request id), and exactly one `status` tag,
  `accepted` or `refused`.

Other tags (`workspace`, `agent`, `action`, `proposal`, `requester`) are not
checked by the relay.

The operator tags its own key in 30190, 30191, 30192, and 44311 so that it can read
its events back. rust-nostr removes a `p` tag equal to the signer unless the
builder calls `allow_self_tagging()`.

## Write rule

The relay setting `BUZZ_OLYMPUS_OPERATOR_PUBKEYS` lists the operator keys
(comma-separated hex). When it is unset or empty, the relay refuses all five
kinds.

- 30190, 30191, 30192, 44311: the author must be in the operator list and have the
  relay role `owner` or `admin` in the community.
- 44310: the author must have the relay role `owner`, and its `p` tag must be
  in the operator list.

The event needs the `admin:users` scope. The relay refuses an event with a bad
tag shape.

The relay refuses a kind 5 that names one of these kinds in a `k` tag, or
that targets one of these events through an `e` or `a` tag. To remove an
agent or workspace, the operator publishes a `deleted` tombstone.

## Read rule

All five kinds are `#p`-gated and result-gated:

- A filter that can match them must have `#p` equal to the authenticated
  reader, else the relay closes it.
- Each result reaches only a reader named in one of its `p` tags. This also
  holds for a kindless `ids` lookup, COUNT, HTTP `/query` and `/count`, live
  fan-out on the same pod and through Redis, push, and admin reads.
- The kinds are not in the full-text search allowlist, so they are not
  searchable.
