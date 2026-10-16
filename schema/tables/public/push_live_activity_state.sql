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
