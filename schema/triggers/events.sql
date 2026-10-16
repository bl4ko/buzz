CREATE TRIGGER events_enqueue_push_match
AFTER INSERT ON events
FOR EACH ROW EXECUTE FUNCTION enqueue_push_match_job();

CREATE CONSTRAINT TRIGGER events_refresh_channel_ttl
AFTER INSERT ON events
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION refresh_channel_ttl_after_event_insert();
CREATE TRIGGER trg_events_guard_channel_roster_snapshot
    BEFORE INSERT ON events
    FOR EACH ROW EXECUTE FUNCTION guard_channel_roster_snapshot();

-- INSERT OR UPDATE OF: an UPDATE can move a previously exempt row into the
-- guarded set (channel_id NULL -> NOT NULL) or move a channel row's
-- created_at below the fence, so both mutation paths re-run the guard on the
-- NEW row. A created_at rewrite that crosses partition bounds runs as
-- DELETE + INSERT and hits the cloned AFTER INSERT guard on the destination
-- partition; an in-partition rewrite fires the UPDATE OF arm.
CREATE CONSTRAINT TRIGGER events_created_at_floor
    AFTER INSERT OR UPDATE OF created_at, channel_id ON events
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW
    EXECUTE FUNCTION events_created_at_floor_guard();
SELECT attach_community_write_fence('events');

CREATE TRIGGER events_enqueue_live_activity
AFTER INSERT ON events
FOR EACH ROW
WHEN (NEW.kind = 30320 OR (NEW.kind = 7 AND NEW.content IN ('✅', '❌')))
EXECUTE FUNCTION enqueue_live_activity_job();

CREATE TRIGGER events_enqueue_live_activity_on_delete
AFTER UPDATE OF deleted_at ON events
FOR EACH ROW
WHEN (OLD.deleted_at IS DISTINCT FROM NEW.deleted_at AND NEW.kind IN (7, 9, 30320, 40002, 45001))
EXECUTE FUNCTION enqueue_live_activity_job();
