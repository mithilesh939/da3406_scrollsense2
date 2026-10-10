BEGIN;
    UPDATE Like_ SET retracted_at = '2026-09-01T00:00:00Z' WHERE like_id = 1;
    INSERT INTO Retraction (like_id, retracted_at) VALUES (1, '2026-09-01T00:00:00Z');

    INSERT OR ROLLBACK INTO Retraction (retraction_id, like_id, retracted_at) VALUES (1, 1, '2026-09-01T00:00:00Z');

BEGIN;
    INSERT INTO VideoModerationEvent (video_id, state, decided_by_type, decided_by_id, decided_at)
    VALUES (1, 'taken_down', 'reviewer', NULL, '2026-09-01T00:00:00Z');

ROLLBACK;

BEGIN;
    UPDATE Handle SET ended_at = '2026-09-01T00:00:00Z' WHERE user_id = 20 AND ended_at IS NULL;
    INSERT INTO Handle (user_id, handle, started_at, ended_at) VALUES (20, 'newhandle1', '2026-09-01T00:00:00Z', NULL);
COMMIT;

BEGIN;
    UPDATE Handle SET ended_at = '2026-09-02T00:00:00Z' WHERE user_id = 20 AND ended_at IS NULL;
    INSERT INTO Handle (user_id, handle, started_at, ended_at) VALUES (20, 'newhandle2', '2026-09-02T00:00:00Z', NULL);
COMMIT;

BEGIN;
    UPDATE Handle SET ended_at = '2026-09-03T00:00:00Z' WHERE user_id = 20 AND ended_at IS NULL;
    INSERT INTO Handle (user_id, handle, started_at, ended_at) VALUES (20, 'newhandle3', '2026-09-03T00:00:00Z', NULL);
COMMIT;
