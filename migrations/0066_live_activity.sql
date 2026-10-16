CREATE TABLE push_live_activity_queue (
    community_id UUID NOT NULL REFERENCES communities(id),
    due_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    state TEXT NOT NULL DEFAULT 'pending' CHECK (state IN ('pending','running')),
    attempts INTEGER NOT NULL DEFAULT 0 CHECK (attempts >= 0),
    lease_until TIMESTAMPTZ,
    claim_id UUID,
    dirty BOOLEAN NOT NULL DEFAULT false,
    refresh BOOLEAN NOT NULL DEFAULT false,
    PRIMARY KEY (community_id)
);
CREATE INDEX push_live_activity_queue_due
    ON push_live_activity_queue (due_at) WHERE state = 'pending';
CREATE INDEX push_live_activity_queue_recovery
    ON push_live_activity_queue (lease_until) WHERE state = 'running';

CREATE TABLE push_live_activity_state (
    community_id UUID NOT NULL,
    author BYTEA NOT NULL CHECK (length(author) = 32),
    installation_id TEXT NOT NULL,
    lease_generation BIGINT NOT NULL CHECK (lease_generation > 0),
    ask_event_id BYTEA CHECK (ask_event_id IS NULL OR length(ask_event_id) = 32),
    open_count INTEGER NOT NULL CHECK (open_count BETWEEN 0 AND 999),
    content_hash BYTEA NOT NULL CHECK (length(content_hash) = 32),
    result TEXT NOT NULL CHECK (result IN ('started','updated','ended','pending','not_registered')),
    started_at BIGINT,
    last_sent_at BIGINT NOT NULL,
    attempts INTEGER NOT NULL DEFAULT 0 CHECK (attempts >= 0),
    next_attempt_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (community_id, author, installation_id),
    FOREIGN KEY (community_id, author, installation_id)
        REFERENCES push_leases (community_id, author, installation_id) ON DELETE CASCADE
);
CREATE INDEX push_live_activity_state_open
    ON push_live_activity_state (community_id) WHERE open_count > 0;

CREATE FUNCTION enqueue_live_activity_job() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO push_live_activity_queue (community_id, due_at)
    VALUES (NEW.community_id, now() + interval '1 second')
    ON CONFLICT (community_id) DO UPDATE
    SET dirty = push_live_activity_queue.dirty OR push_live_activity_queue.state = 'running',
        due_at = CASE WHEN push_live_activity_queue.state = 'pending'
            THEN LEAST(push_live_activity_queue.due_at, EXCLUDED.due_at)
            ELSE push_live_activity_queue.due_at END;
    RETURN NEW;
END
$$;

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

SELECT attach_community_write_fence('push_live_activity_queue');
SELECT attach_community_write_fence('push_live_activity_state');
