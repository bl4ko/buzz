-- Freeze a delete action's original message slot (time + thread position) at
-- mutation time so the relay-signed deletion notice can be rebuilt identically
-- on every outbox retry, even after the target row is purged.
--
-- NULL                 = not captured yet (pre-migration rows, non-delete actions).
-- {"slot": {...}}      = captured slot.
-- {"slot": null}       = captured, but the target row no longer existed.
--
-- Additive and nullable; no backfill. Legacy delete actions freeze their slot
-- once during finalization.

ALTER TABLE relay_admin_actions
    ADD COLUMN original_slot JSONB
        CHECK (original_slot IS NULL OR jsonb_typeof(original_slot) = 'object');
