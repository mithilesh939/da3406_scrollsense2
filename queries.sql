SELECT
    at.track_id,
    at.source,
    COUNT(DISTINCT v.video_id) AS distinct_video_count
FROM AudioTrack at
JOIN Video v ON v.audio_track_id = at.track_id
WHERE v.uploaded_at >= (
    SELECT datetime(MAX(uploaded_at), '-7 days') FROM Video
)
GROUP BY at.track_id, at.source
ORDER BY distinct_video_count DESC
LIMIT 10;

SELECT
    c.user_id AS creator_id,
    COALESCE(SUM(
        (julianday(vs.ended_at) - julianday(vs.started_at)) * 86400.0
    ) / 3600.0, 0) AS total_watch_hours,
    COALESCE(AVG(
        CASE
            WHEN (julianday(vs.ended_at) - julianday(vs.started_at)) * 86400000.0 >= v.duration_ms
            THEN 1.0 ELSE 0.0
        END
    ), 0) AS mean_completion_rate
FROM Creator c
LEFT JOIN Video v
    ON v.owner_id = c.user_id
LEFT JOIN VideoModerationEvent vme
    ON vme.video_id = v.video_id
   AND vme.state = 'live'
LEFT JOIN Impression i
    ON i.video_id = v.video_id
LEFT JOIN ViewSegment vs
    ON vs.impression_id = i.impression_id
GROUP BY c.user_id;

SELECT video_id
FROM Video
WHERE audio_track_id NOT IN (
    SELECT track_id FROM AudioTrack
);

SELECT v.video_id
FROM Video v
WHERE NOT EXISTS (
    SELECT 1 FROM AudioTrack at WHERE at.track_id = v.audio_track_id
);

SELECT
    l.user_id,
    l.video_id,
    l.liked_at,
    l.retracted_at,
    (julianday(l.retracted_at) - julianday(l.liked_at)) * 86400.0 AS seconds_between
FROM Like_ l
WHERE l.retracted_at IS NOT NULL
  AND (julianday(l.retracted_at) - julianday(l.liked_at)) * 86400.0 <= 60;

SELECT
    l.user_id,
    l.video_id,
    l.liked_at,
    l.retracted_at,
    (julianday(l.retracted_at) - julianday(l.liked_at)) * 86400.0 AS seconds_between
FROM Like_ l
WHERE l.retracted_at IS NOT NULL
  AND (julianday(l.retracted_at) - julianday(l.liked_at)) * 86400.0 <= 60;

SELECT video_id, caption
FROM Video
WHERE instr(
    ' ' || lower(replace(replace(caption, '.', ' '), ',', ' ')) || ' ',
    ' #' || lower(:target_tag) || ' '
) > 0
   OR lower(caption) LIKE '%#' || lower(:target_tag);

WITH shown AS (
    SELECT DISTINCT i.user_id
    FROM Impression i
    JOIN Video v ON v.video_id = i.video_id
    WHERE v.owner_id = :creator_id
),
engaged AS (
    SELECT l.user_id FROM Like_ l JOIN Video v ON v.video_id = l.video_id WHERE v.owner_id = :creator_id
    UNION
    SELECT c.user_id FROM Comment c JOIN Video v ON v.video_id = c.video_id WHERE v.owner_id = :creator_id
    UNION
    SELECT s.user_id FROM Share s JOIN Video v ON v.video_id = s.video_id WHERE v.owner_id = :creator_id
    UNION
    SELECT se.user_id FROM SignalEvent se JOIN Video v ON v.video_id = se.video_id WHERE v.owner_id = :creator_id
)
SELECT user_id FROM shown
EXCEPT
SELECT user_id FROM engaged;

SELECT user_id FROM Like_
UNION
SELECT user_id FROM Comment
UNION
SELECT user_id FROM Share;

SELECT user_id FROM Like_
UNION ALL
SELECT user_id FROM Comment
UNION ALL
SELECT user_id FROM Share;

SELECT
    t.session_id,
    t.template_id,
    t.template_version,
    SUM(tu.input_tokens * mp.input_rate
        + tu.output_tokens * mp.output_rate
        + tu.cached_tokens * mp.cached_input_rate) AS session_template_cost
FROM Turn t
JOIN TurnUsage tu ON tu.turn_id = t.turn_id
JOIN ModelPricePeriod mp
    ON mp.model_id = t.model_id AND mp.priced_at = t.priced_at
WHERE t.occurred_at >= '2026-08-01T00:00:00Z'
  AND t.occurred_at < '2026-09-01T00:00:00Z'
GROUP BY t.session_id, t.template_id, t.template_version
HAVING session_template_cost > 2.0
ORDER BY session_template_cost DESC;

SELECT
    video_id,
    COUNT(*) AS transition_count,
    group_concat(state, ' -> ' ORDER BY decided_at) AS transition_sequence
FROM VideoModerationEvent
GROUP BY video_id
HAVING COUNT(*) > 2
ORDER BY transition_count DESC;

WITH active_days AS (
    SELECT DISTINCT user_id, date(ts) AS active_date
    FROM Impression
),
numbered AS (
    SELECT
        user_id,
        active_date,
        ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY active_date) AS rn
    FROM active_days
),
grouped AS (
    SELECT
        user_id,
        active_date,
        date(active_date, '-' || rn || ' days') AS streak_group
    FROM numbered
),
streaks AS (
    SELECT
        user_id,
        streak_group,
        COUNT(*) AS streak_length
    FROM grouped
    GROUP BY user_id, streak_group
)
SELECT
    user_id,
    MAX(streak_length) AS longest_streak
FROM streaks
GROUP BY user_id
ORDER BY longest_streak DESC;

WITH daily_watch AS (
    SELECT
        v.owner_id AS creator_id,
        date(i.ts) AS watch_date,
        SUM((julianday(vs.ended_at) - julianday(vs.started_at)) * 86400.0) AS watch_seconds
    FROM ViewSegment vs
    JOIN Impression i ON i.impression_id = vs.impression_id
    JOIN Video v ON v.video_id = i.video_id
    GROUP BY v.owner_id, date(i.ts)
),
rolling AS (
    SELECT
        creator_id,
        watch_date,
        watch_seconds,
        SUM(watch_seconds) OVER (
            PARTITION BY creator_id
            ORDER BY julianday(watch_date)
            RANGE BETWEEN 6 PRECEDING AND CURRENT ROW
        ) AS rolling_7day_watch_seconds
    FROM daily_watch
)
SELECT
    creator_id,
    watch_date,
    rolling_7day_watch_seconds,
    rolling_7day_watch_seconds - LAG(rolling_7day_watch_seconds, 7) OVER (
        PARTITION BY creator_id ORDER BY julianday(watch_date)
    ) AS week_over_week_change
FROM rolling
ORDER BY creator_id, watch_date;

WITH RECURSIVE call_tree AS (
    SELECT
        call_id,
        turn_id,
        parent_call_id,
        tool_name,
        called_at,
        0 AS depth
    FROM ToolCall
    WHERE turn_id IN (SELECT turn_id FROM Turn WHERE session_id = 389)
      AND parent_call_id IS NULL

    UNION ALL

    SELECT
        tc.call_id,
        tc.turn_id,
        tc.parent_call_id,
        tc.tool_name,
        tc.called_at,
        ct.depth + 1
    FROM ToolCall tc
    JOIN call_tree ct ON tc.parent_call_id = ct.call_id
)
SELECT call_id, turn_id, parent_call_id, tool_name, depth
FROM call_tree
ORDER BY turn_id, depth, call_id;

SELECT
    t.session_id,
    r.turn_id,
    r.position,
    r.video_id,
    MAX(
        CASE
            WHEN (julianday(vs.ended_at) - julianday(vs.started_at)) * 86400000.0 >= v.duration_ms
            THEN 1 ELSE 0
        END
    ) AS watched_to_completion
FROM Recommendation r
JOIN Turn t ON t.turn_id = r.turn_id
JOIN AgentSession s ON s.session_id = t.session_id
JOIN Video v ON v.video_id = r.video_id
JOIN Impression i
    ON i.video_id = r.video_id
   AND i.user_id = s.user_id
JOIN ViewSegment vs
    ON vs.impression_id = i.impression_id
GROUP BY t.session_id, r.turn_id, r.position, r.video_id
HAVING watched_to_completion = 1;

SELECT
    t.turn_id,
    t.session_id,
    js.helpfulness,
    js.groundedness,
    js.safety,
    ur.thumbs
FROM Turn t
JOIN JudgeScore js ON js.turn_id = t.turn_id
JOIN UserRating ur ON ur.turn_id = t.turn_id
WHERE js.helpfulness > 4
  AND ur.thumbs = 'down';

SELECT COUNT(*) FROM ViewSegment vs JOIN Impression i ON i.impression_id = vs.impression_id;

SELECT COUNT(*) FROM Like_ l JOIN Impression i ON i.user_id = l.user_id AND i.video_id = l.video_id;

SELECT COUNT(*) FROM Video v
JOIN Impression i ON i.video_id = v.video_id
JOIN ViewSegment vs ON vs.impression_id = i.impression_id
WHERE v.owner_id = 12;

SELECT DISTINCT i.user_id FROM Impression i JOIN Video v ON v.video_id = i.video_id WHERE v.owner_id = 12;

WITH j AS MATERIALIZED (SELECT i.user_id, v.owner_id FROM Impression i JOIN Video v ON v.video_id = i.video_id)
SELECT DISTINCT user_id FROM j WHERE owner_id = 12;

WITH vv AS MATERIALIZED (SELECT video_id FROM Video WHERE owner_id = 12)
SELECT DISTINCT i.user_id FROM vv JOIN Impression i ON i.video_id = vv.video_id;

SELECT COUNT(*) FROM Turn t LEFT JOIN UserRating ur ON ur.turn_id = t.turn_id WHERE ur.thumbs = 'down';
SELECT COUNT(*) FROM Turn t LEFT JOIN (SELECT * FROM UserRating WHERE thumbs = 'down') ur ON ur.turn_id = t.turn_id;
