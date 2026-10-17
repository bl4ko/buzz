BEGIN;
DROP TRIGGER IF EXISTS events_enqueue_live_activity_on_delete ON events;
DROP TRIGGER IF EXISTS events_enqueue_live_activity ON events;
DROP FUNCTION IF EXISTS enqueue_live_activity_job();
DROP TABLE IF EXISTS push_live_activity_state;
DROP TABLE IF EXISTS push_live_activity_queue;
DELETE FROM _sqlx_migrations WHERE version = 9001;
COMMIT;
