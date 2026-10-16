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
