BEGIN;
DROP TABLE IF EXISTS push_gateway_live_activities;
DROP TABLE IF EXISTS push_gateway_live_activity_starts;
DROP FUNCTION IF EXISTS push_gateway_origin_hashes_valid(BYTEA[]);
DELETE FROM _sqlx_migrations WHERE version = 9001;
COMMIT;
