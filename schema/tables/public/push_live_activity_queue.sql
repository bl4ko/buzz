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
