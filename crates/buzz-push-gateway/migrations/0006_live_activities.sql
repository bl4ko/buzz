CREATE FUNCTION push_gateway_origin_hashes_valid(hashes BYTEA[]) RETURNS BOOLEAN
LANGUAGE sql IMMUTABLE STRICT AS $$
    SELECT COALESCE(array_ndims(hashes), 1) = 1
        AND cardinality(hashes) BETWEEN 0 AND 16
        AND NOT EXISTS (SELECT 1 FROM unnest(hashes) AS h WHERE h IS NULL OR length(h) <> 32)
        AND (SELECT count(DISTINCT h) FROM unnest(hashes) AS h) = cardinality(hashes)
$$;

CREATE TABLE push_gateway_live_activity_starts (
    installation_id UUID PRIMARY KEY REFERENCES push_gateway_installations(id),
    token_ciphertext BYTEA NOT NULL CHECK (octet_length(token_ciphertext) BETWEEN 1 AND 2048),
    token_fingerprint BYTEA NOT NULL CHECK (length(token_fingerprint) = 32),
    origin_hashes BYTEA[] NOT NULL CHECK (push_gateway_origin_hashes_valid(origin_hashes)),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at TIMESTAMPTZ NOT NULL
);

CREATE TABLE push_gateway_live_activities (
    installation_id UUID NOT NULL REFERENCES push_gateway_live_activity_starts(installation_id) ON DELETE CASCADE,
    origin_hash BYTEA NOT NULL CHECK (length(origin_hash) = 32),
    update_token_ciphertext BYTEA CHECK (octet_length(update_token_ciphertext) BETWEEN 1 AND 2048),
    update_token_fingerprint BYTEA CHECK (length(update_token_fingerprint) = 32),
    started_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at TIMESTAMPTZ NOT NULL,
    PRIMARY KEY (installation_id, origin_hash),
    CHECK ((update_token_ciphertext IS NULL) = (update_token_fingerprint IS NULL))
);
CREATE INDEX push_gateway_live_activities_expiry ON push_gateway_live_activities (expires_at);
