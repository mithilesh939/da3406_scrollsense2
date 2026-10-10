# plan_analysis.md - Assignment 2 (da24b048)

This file holds the plans, timings, calculations and schedules of Assignment 2. The full explanations, figures (trees and precedence graphs)
and the handout checklist are in the PDF report `DA24B048_A2_report.pdf`. Every plan, number and calculation below is copied from an output file
by a script (`local_only/build_report.py md`), so nothing is retyped. The raw outputs are in `local_only/results_v3/` (not part of the submission).

Machine: Intel Core i7-1355U (10 cores, 12 threads), 15.7 GB RAM, SSD, Windows 11, on AC power. SQLite 3.50.4, Python 3.14.7. SCALE = 50,
page_size 4096, journal_mode WAL, default page cache 2000 KiB = 500 pages.

Timing rule: one warm-up run (not counted), then 3 timed runs, median reported, warm cache. The `TIME` lines show the three runs, the median and a hash of the
result rows (same hash = same answer). Reproduce: `python bench.py task1` ... `task4`, `python concurrency_demo.py`, `python bench.py scale`.
Ratios matter more than single numbers: the same query can differ by about 25 percent between two Python processes, and by 3 to 4 times between battery and AC power.

### Scale check (handout: confirm the row counts are about 50 times A1)
`python bench.py scale` builds a SCALE 1 database with the same generator and the same 8 patch scripts and compares row counts.
```
table                        SCALE 1      SCALE 50    ratio
AgentSession                   2,000       100,000    50.0x
AppUser                        5,000       250,000    50.0x
AudioTrack                       500        25,000    50.0x
Block                          2,500       124,999    50.0x
Comment                        1,613        78,643    48.8x
Creator                          750        37,500    50.0x
CreatorTierPeriod                750        37,500    50.0x
Follow                        15,000       750,000    50.0x
Handle                         5,000       250,000    50.0x
Hashtag                           50            50     1.0x
Impression                   308,409    15,420,333    50.0x
InferredInterest              12,605       630,001    50.0x
InterestCategory                  12            12     1.0x
InterestSuppression            2,534       126,007    49.7x
JudgeScore                       695        35,249    50.7x
Like_                          8,326       420,623    50.5x
ModelPricePeriod                   3             3     1.0x
ModerationState                    5             5     1.0x
Mute                           5,000       249,998    50.0x
PromptTemplateVersion             11            18     1.6x
Recommendation                 8,409       420,333    50.0x
Retraction                       815        41,953    51.5x
Share                          2,150       104,190    48.5x
SignalEvent                    1,037        52,325    50.5x
ToolCall                       7,527       372,748    49.5x
Turn                           7,004       350,275    50.0x
TurnUsage                      7,004       350,275    50.0x
TypeAffinityTest                   0             0        -
UserRating                       316        14,076    44.5x
Video                         20,000     1,000,000    50.0x
VideoHashtag                  20,000     1,000,000    50.0x
VideoModerationEvent          24,800     1,240,003    50.0x
ViewSegment                  113,424     5,672,455    50.0x
```

Hashtag, InterestCategory, ModelPricePeriod and ModerationState are fixed lookup tables. PromptTemplateVersion is random (1 to 4 versions of 5 templates).
UserRating is a small random sample (4 percent of turns), so it is 44.5x.

## Changelog (A1 changes needed for A2)
Nothing was changed silently. Every change is listed in this one table. Foreign key check after all patches: 0 violations
(`python verify_db.py`). Row counts after all patches are in the "Scale check" below.

| # | What changed | Why | Effect on data and results |
|---|---|---|---|
| 1 | `generate_data.py` (rewritten for speed and SCALE before this work started, see CLAUDE.md): SCALE multiplies the four volumes (users, videos, impressions, agent sessions); the whole load is ONE transaction with `PRAGMA foreign_keys = ON`; rows are inserted in batches (executemany); bulk-load pragmas during the load; WAL mode restored at the end. | The A1 generator never used SCALE and was too slow for 50x. | None on the data. **How I checked it (I ran this myself in this session):** I ran the A1 original generator (`a1_scripts/generate_data_A1_original.py`) and the new one, and compared every table row by row, rowids included. SCALE 1: all tables identical (original 6.7 s, new 2.4 s). SCALE 10: all tables identical (original 81.6 s, new 24.0 s). The original has no SCALE, so for SCALE 10 I multiplied its four volume numbers by 10 in a scratch copy and changed nothing else. SCALE 50 itself was NOT compared with the original (too slow); it is the same code as at SCALE 10. Outputs are in `local_only/generator_check/`. |
| 2 | `patch_missing_data.py` **rebuilt, NOT the original A1 code** (the original is lost). Set-based SQL. Fills Hashtag, VideoHashtag (parsed from captions), InterestCategory, InferredInterest, InterestSuppression, Block, Mute, Recommendation, plus the Impression and ViewSegment rows of the recommendation outcomes. | Without it these tables are empty, so F12 returns nothing. | Same intent as A1, **different random values**. Details A1 does not state (12 category names, about 2.5 interests per user, 0.5 blocks and 1 mute per user, 3 recommendations for 40 percent of turns) are my own choice. At SCALE 1 it gives 20,000 VideoHashtag, 12,605 inferred interests (A1 PDF: about 12,500) and 8,409 recommendations (A1 PDF: about 8,600). |
| 3 | `fix_view_durations.py` **rebuilt, NOT the original A1 code.** One `UPDATE ... FROM`; watch time is u^3 x duration x (0.8 to 1.6), the same shape as the generator. | Every base ViewSegment had started_at = ended_at, so F2 completion rates were all zero. | **Different random values.** About 19 percent of segments still round down to 0 seconds (1,078,732 of 5,672,455 at the time of the run, which includes the recommendation segments). |
| 4 | `fix_retraction_gaps.py` **rebuilt, NOT the original A1 code.** 60 percent of retractions get a 1 to 55 second gap, 40 percent 120 to 7200 seconds (the split is stated in the A1 PDF). | Every retraction had retracted_at = liked_at, so F4 matched 100 percent. | **Different random values.** F4 returns 25,164 of 41,953 retractions at SCALE 50 (A1 PDF: 487 of 815 = 60 percent; here 60 percent). |
| 5 | `patch_moderation_history.py` **rebuilt, NOT the original A1 code.** About 8 percent of videos get a 4 step history from five valid state sequences, with strictly increasing times built by `strftime`. | One moderation event per video made F8 empty. | **Different random values.** 80,001 videos with more than 2 events at SCALE 50 (1,600 of 20,000 at SCALE 1, the same count as the A1 PDF). 0 timestamps out of order. |
| 6 | `backfill_turn_usage.py` **rebuilt, NOT the original A1 code.** One TurnUsage row per Turn. Token ranges: input 100 to 1300, output 20 to 320, cached up to half of input. | TurnUsage was empty, so F7 and the view v_turn_cost had nothing to add up. | **Different random values.** The ranges are my choice (my first, smaller ranges gave only 14 of 2000 sessions in F7 at SCALE 1; these give 309 of 2000). |
| 7 | `fix_user_activity_pattern.py` rewritten (original kept in `a1_scripts/original_A1_versions/`). Same user profiles from the same seed; ONE set-based UPDATE instead of 15M row-by-row updates. The day for each impression comes from a hash of impression_id instead of `random.choice`. | The loop would take hours at 50x. | Same distribution of active days per user. The exact A1 values cannot be reproduced. |
| 8 | `patch_toolcall_nesting.py` rewritten (original kept). Sample is 500 x SCALE turns (A1: 500); one pass over ToolCall instead of one full scan per turn; one executemany. | One full scan per turn is too slow, and a fixed 500 turns would make nested calls vanish at 50x. | 22,364 nested calls at SCALE 50. The share of nested calls stays like A1. |
| 9 | `fix_recommendation_watches.py` rewritten (original kept). Row-by-row UPDATE replaced by one executemany. Same logic, same seed, same draw order. | Speed. | None in logic. |
| 10 | New helper files: `a1_scripts/apply_a1_patches.py` (runs the 8 scripts in the README_A1.md order), `a1_scripts/_sqlhash.py` (deterministic hash used instead of random()), `verify_db.py`, `bench.py`, `concurrency_demo.py`. | Needed to run and check the pipeline. | None on the data. |
| 11 | Patch ORDER is exactly as in README_A1.md. One A1 quirk is kept on purpose: `fix_user_activity_pattern` moves `Impression.ts` only, so `ViewSegment.started_at` and `Like_.liked_at` keep their old dates. | Changing it would change the A1 behaviour. | Queries that use only Impression.ts (F9, F10) are consistent. Queries that mix Impression.ts with ViewSegment dates are not exact. |
| 12 | Query, transaction and index file edits. `queries.sql`: A1 text unchanged (first 7,366 bytes identical), A2 section appended. `transactions.sql`: two minimal fixes so the file runs as one script and shows what it says: (a) T1's `SELECT 1/0` never fails in SQLite (it returns NULL), so the transaction committed; it is now a duplicate-key insert with OR ROLLBACK, which really fails and undoes everything (as A1's Python version did); (b) T2 deliberately leaves a transaction open, so the next BEGIN failed; a ROLLBACK line was added after it. The T3 statements are unchanged; an A2 section was appended, with statements commented out where they would break the rule they demonstrate. `indexes.sql` uses IF NOT EXISTS. | The professor may run the files in DBeaver; I ran each file statement by statement on a small copy (no errors except the intended T1 failure). | None on A1 results. T1 now changes nothing (Like_ row 1 and the 815 Retraction rows unchanged). T3 still changes the handles of user 20, so run the file on a copy. |
| 13 | Schema change: **none.** `schema.sql` (9,587 bytes), `views.sql` (3,140 bytes), `bonus.sql` (1,073 bytes) and `generate_data.py` (16,625 bytes) have exactly the same size as in my first directory listing of this work, and I did not edit them. The only objects created by A2 are temporary test indexes, which bench.py drops again. The databases contain no A2 index. | | None. |
| 14 | Backups (not committed, `*.db` is in `.gitignore`): `scrollsense_base_unpatched.db` (before the patches), `scrollsense_clean.db` (patched, views created, no A2 index). | Re-run from a clean state. | None. |

---

## Task 1 - Access paths and cost arithmetic
Queries: F1 (Video + AudioTrack), F11 (ToolCall + Turn, recursive), F12 (Recommendation, Turn, Video, AgentSession, Impression, ViewSegment). All three touch the handout's high-volume tables.
Database: patched SCALE 50, no secondary indexes. Reproduce: `python bench.py task1`.

### 1.1 Plans (raw `EXPLAIN QUERY PLAN`, `[node<-parent]` are SQLite's ids)
```
EXPLAIN QUERY PLAN F1
  [9<-0] SCAN v
  [14<-0] SCALAR SUBQUERY 1
  [19<-14] SEARCH Video
  [31<-0] SEARCH at USING INTEGER PRIMARY KEY (rowid=?)
  [34<-0] USE TEMP B-TREE FOR GROUP BY
  [83<-0] USE TEMP B-TREE FOR ORDER BY
```

```
EXPLAIN QUERY PLAN F11
  [2<-0] CO-ROUTINE call_tree
  [5<-2] SETUP
  [7<-5] SCAN ToolCall
  [12<-5] LIST SUBQUERY 1
  [15<-12] SEARCH Turn USING COVERING INDEX sqlite_autoindex_Turn_1 (session_id=?)
  [23<-12] CREATE BLOOM FILTER
  [54<-2] RECURSIVE STEP
  [56<-54] SCAN ct
  [59<-54] BLOOM FILTER ON tc (parent_call_id=?)
  [71<-54] SEARCH tc USING AUTOMATIC COVERING INDEX (parent_call_id=?)
  [92<-0] SCAN call_tree
  [103<-0] USE TEMP B-TREE FOR ORDER BY
```

```
EXPLAIN QUERY PLAN F12
  [12<-0] SCAN r USING INDEX sqlite_autoindex_Recommendation_1
  [15<-0] SEARCH t USING INTEGER PRIMARY KEY (rowid=?)
  [18<-0] SEARCH v USING INTEGER PRIMARY KEY (rowid=?)
  [24<-0] SEARCH s USING INTEGER PRIMARY KEY (rowid=?)
  [29<-0] BLOOM FILTER ON i (video_id=? AND user_id=?)
  [39<-0] SEARCH i USING AUTOMATIC COVERING INDEX (video_id=? AND user_id=?)
  [48<-0] BLOOM FILTER ON vs (impression_id=?)
  [59<-0] SEARCH vs USING AUTOMATIC COVERING INDEX (impression_id=?)
```


| Query | Table | Access path |
|---|---|---|
| F1 | Video (main) | full scan (`SCAN v`) |
| F1 | Video (MAX subquery) | full scan (the plan says SEARCH; the bytecode is Rewind, AggStep, Next, a loop over all rows) |
| F1 | AudioTrack | rowid / primary key lookup |
| F11 | ToolCall (start rows) | full scan (`SCAN ToolCall`) |
| F11 | Turn | existing index (UNIQUE session_id, turn_index), covering |
| F11 | ToolCall (recursive step) | temporary automatic index on parent_call_id, built at run time |
| F12 | Recommendation | existing index (primary key), scanned fully |
| F12 | Turn, Video, AgentSession | rowid / primary key lookup |
| F12 | Impression | temporary automatic index on (video_id, user_id) |
| F12 | ViewSegment | temporary automatic index on impression_id |

```
TIME F1 as written: rows=10  runs(s)=0.335, 0.344, 0.269  median=0.335s  result_hash=d4bf73d592
```

```
TIME F11 as written: rows=7  runs(s)=0.224, 0.224, 0.226  median=0.224s  result_hash=0b0d718dc8
```


### 1.2 Hand calculation: the `SCAN ToolCall` step of F11 (real output)
```
table                = ToolCall
block size (page)    = 4096 bytes   (PRAGMA page_size; I assume block = page)
row count (n)        = 372,748
avg record payload   = 126.23 bytes (largest row 128 bytes, so no row needs an overflow page: the limit is about 4061)
avg cell size        = 132.94 bytes = payload 126.23 + payload-length varint 1.76 + rowid varint 2.96 + cell pointer 2
usable bytes / page  = 4096 - 8 = 4088
rows per page        = floor(4088 / 132.94) = 30
blocks to read       = ceil(372,748 / 30) = 12,425 pages = 50.9 MB
CHECK (real)         : a fresh database holding the same 372,748 rows in rowid order uses 12,300 pages
estimate minus real  : +125 pages (+1.02 percent)

SCAN PROBE  SELECT SUM(latency_ms) FROM ToolCall (reads every page of the table): runs(s)=0.040, 0.041, 0.042  median=0.041s
            = 301,035 pages per second, 0.11 microseconds per row (warm cache)
```


### 1.3 One sentence per query
- F1: Video has no index on uploaded_at or audio_track_id, so it reads all 1,000,000 rows and finds each AudioTrack by primary key; the alternative (start from the 25,000 AudioTrack rows and look up videos by audio_track_id) needs an index that does not exist.
- F11: the starting ToolCall rows can only be found by a scan (no index on turn_id or parent_call_id); the few turn ids of session 389 come from the existing UNIQUE index on Turn; for the recursion SQLite builds one temporary index on parent_call_id and uses it at every level, because rescanning 372,748 rows per queue row would be far worse.
- F12: it starts from the small Recommendation table through its primary key index, uses primary keys for Turn, Video and AgentSession, and builds a temporary index for Impression and ViewSegment because scanning 15.4 million impressions for each of 420,333 recommendations would be hopeless.

---

## Task 2 - Composite indexes
Indexes (file `indexes.sql`): `Video(audio_track_id, uploaded_at)` for F1, `Like_(retracted_at, liked_at, user_id, video_id)` for F4, `Impression(video_id, user_id)` for F12.
Rule: equality columns first, then the range column, then sort/group columns, then columns that only make the index covering.

| Query | Clause by clause | The other order |
|---|---|---|
| F1 | JOIN equality audio_track_id first; WHERE range uploaded_at second; no Video column in GROUP BY / ORDER BY | `(uploaded_at, audio_track_id)`: can only seek on the range (26.7 percent of Video); measured below |
| F4 | `retracted_at IS NOT NULL` is the only part that can seek (10 percent of rows); the 60-second test is a calculation, cannot seek; the other columns make it covering | `(liked_at, ...)`: nothing can seek; the planner ignores the index |
| F12 | two join equalities video_id, user_id; video_id first because it is more selective and its prefix serves other joins | either order works for F12 itself |

### 2.2 Plans and times (raw)
F1, no index:
```
EXPLAIN QUERY PLAN F1
  [9<-0] SCAN v
  [14<-0] SCALAR SUBQUERY 1
  [19<-14] SEARCH Video
  [31<-0] SEARCH at USING INTEGER PRIMARY KEY (rowid=?)
  [34<-0] USE TEMP B-TREE FOR GROUP BY
  [83<-0] USE TEMP B-TREE FOR ORDER BY
```

```
TIME F1 before: rows=10  runs(s)=0.288, 0.289, 0.300  median=0.289s  result_hash=d4bf73d592
```

F1, chosen index `Video(audio_track_id, uploaded_at)`:
```
BUILD CREATE INDEX idx_video_audio_uploaded ON Video(audio_track_id, uploaded_at);
      took 1.2s, index size = 7,724 pages = 31.6 MB
```

```
EXPLAIN QUERY PLAN F1
  [9<-0] SCAN at
  [11<-0] SEARCH v USING COVERING INDEX idx_video_audio_uploaded (audio_track_id=? AND uploaded_at>?)
  [15<-0] SCALAR SUBQUERY 1
  [20<-15] SEARCH Video USING COVERING INDEX idx_video_audio_uploaded
  [74<-0] USE TEMP B-TREE FOR count(DISTINCT)
  [77<-0] USE TEMP B-TREE FOR ORDER BY
```

```
TIME F1 after: rows=10  runs(s)=0.116, 0.109, 0.115  median=0.115s  result_hash=d4bf73d592
```

F1, other order `Video(uploaded_at, audio_track_id)` (control):
```
BUILD CREATE INDEX idx_wrong_order ON Video(uploaded_at, audio_track_id);
      took 0.9s, index size = 7,708 pages = 31.6 MB
EXPLAIN QUERY PLAN F1 with other order
  [9<-0] SEARCH v USING COVERING INDEX idx_wrong_order (uploaded_at>?)
  [12<-0] SCALAR SUBQUERY 1
  [17<-12] SEARCH Video USING COVERING INDEX idx_wrong_order
  [33<-0] SEARCH at USING INTEGER PRIMARY KEY (rowid=?)
  [36<-0] USE TEMP B-TREE FOR GROUP BY
  [83<-0] USE TEMP B-TREE FOR count(DISTINCT)
  [86<-0] USE TEMP B-TREE FOR ORDER BY
TIME F1 other order: rows=10  runs(s)=0.132, 0.134, 0.136  median=0.134s  result_hash=d4bf73d592

==============================================================================
F4: index idx_like_retracted_cover
==============================================================================
```

```
EXPLAIN QUERY PLAN F1 with other order
  [9<-0] SEARCH v USING COVERING INDEX idx_wrong_order (uploaded_at>?)
  [12<-0] SCALAR SUBQUERY 1
  [17<-12] SEARCH Video USING COVERING INDEX idx_wrong_order
  [33<-0] SEARCH at USING INTEGER PRIMARY KEY (rowid=?)
  [36<-0] USE TEMP B-TREE FOR GROUP BY
  [83<-0] USE TEMP B-TREE FOR count(DISTINCT)
  [86<-0] USE TEMP B-TREE FOR ORDER BY
```

```
TIME F1 other order: rows=10  runs(s)=0.132, 0.134, 0.136  median=0.134s  result_hash=d4bf73d592
```

F4, no index:
```
EXPLAIN QUERY PLAN F4
  [2<-0] SCAN l
```

```
TIME F4 before: rows=25,164  runs(s)=0.051, 0.050, 0.052  median=0.051s  result_hash=24c86ed4e0
```

F4, chosen index:
```
BUILD CREATE INDEX idx_like_retracted_cover ON Like_(retracted_at, liked_at, user_id, video_id);
      took 0.5s, index size = 4,112 pages = 16.8 MB
```

```
EXPLAIN QUERY PLAN F4
  [2<-0] SEARCH l USING COVERING INDEX idx_like_retracted_cover (retracted_at>?)
```

```
TIME F4 after: rows=25,164  runs(s)=0.030, 0.029, 0.030  median=0.030s  result_hash=24c86ed4e0
```

F4, other order (control, index ignored):
```
BUILD CREATE INDEX idx_wrong_order ON Like_(liked_at, retracted_at, user_id, video_id);
      took 0.4s, index size = 4,116 pages = 16.9 MB
EXPLAIN QUERY PLAN F4 with other order
  [2<-0] SCAN l
TIME F4 other order: rows=25,164  runs(s)=0.049, 0.050, 0.049  median=0.049s  result_hash=24c86ed4e0

==============================================================================
F12: index idx_impression_video_user
==============================================================================
```

```
EXPLAIN QUERY PLAN F4 with other order
  [2<-0] SCAN l
```

```
TIME F4 other order: rows=25,164  runs(s)=0.049, 0.050, 0.049  median=0.049s  result_hash=24c86ed4e0
```

F12, no index:
```
EXPLAIN QUERY PLAN F12
  [12<-0] SCAN r USING INDEX sqlite_autoindex_Recommendation_1
  [15<-0] SEARCH t USING INTEGER PRIMARY KEY (rowid=?)
  [18<-0] SEARCH v USING INTEGER PRIMARY KEY (rowid=?)
  [24<-0] SEARCH s USING INTEGER PRIMARY KEY (rowid=?)
  [29<-0] BLOOM FILTER ON i (video_id=? AND user_id=?)
  [39<-0] SEARCH i USING AUTOMATIC COVERING INDEX (video_id=? AND user_id=?)
  [48<-0] BLOOM FILTER ON vs (impression_id=?)
  [59<-0] SEARCH vs USING AUTOMATIC COVERING INDEX (impression_id=?)
```

```
TIME F12 before: rows=128,805  runs(s)=236.325, 215.335, 220.275  median=220.275s  result_hash=8dfe7302fc
```

F12, chosen index:
```
BUILD CREATE INDEX idx_impression_video_user ON Impression(video_id, user_id);
      took 12.0s, index size = 61,623 pages = 252.4 MB
```

```
EXPLAIN QUERY PLAN F12
  [12<-0] SCAN r USING INDEX sqlite_autoindex_Recommendation_1
  [15<-0] SEARCH v USING INTEGER PRIMARY KEY (rowid=?)
  [21<-0] SEARCH t USING INTEGER PRIMARY KEY (rowid=?)
  [24<-0] SEARCH s USING INTEGER PRIMARY KEY (rowid=?)
  [27<-0] SEARCH i USING COVERING INDEX idx_impression_video_user (video_id=? AND user_id=?)
  [41<-0] BLOOM FILTER ON vs (impression_id=?)
  [52<-0] SEARCH vs USING AUTOMATIC COVERING INDEX (impression_id=?)
```

```
TIME F12 after: rows=128,805  runs(s)=9.037, 8.970, 8.930  median=8.970s  result_hash=8dfe7302fc
```

F12, chosen index plus `ViewSegment(impression_id)` (control):
```
EXPLAIN QUERY PLAN F12 with both indexes
  [13<-0] SCAN r USING INDEX sqlite_autoindex_Recommendation_1
  [16<-0] SEARCH v USING INTEGER PRIMARY KEY (rowid=?)
  [22<-0] SEARCH t USING INTEGER PRIMARY KEY (rowid=?)
  [25<-0] SEARCH s USING INTEGER PRIMARY KEY (rowid=?)
  [28<-0] SEARCH i USING COVERING INDEX idx_impression_video_user (video_id=? AND user_id=?)
  [40<-0] SEARCH vs USING INDEX idx_extra_seg_impression (impression_id=?)
```

```
TIME F12 with both indexes: rows=128,805  runs(s)=5.735, 6.043, 6.209  median=6.043s  result_hash=8dfe7302fc
```


Medians: F1 0.289 s to 0.115 s;
F4 0.051 s to 0.030 s;
F12 220.3 s to 8.970 s.

### Extra measurements (`python bench.py task2more`)
```
TASK 2 EXTRA 1 - the MAX(uploaded_at) subquery of F1 with each column order
==============================================================================
EXPLAIN QUERY PLAN no index
  [3<-0] SEARCH Video
TIME MAX subquery, no index: rows=1  runs(s)=0.095, 0.094, 0.104  median=0.095s  result_hash=ae9446ef96
BUILD CREATE INDEX idx_video_audio_uploaded ON Video(audio_track_id, uploaded_at);
      took 1.1s, index size = 7,724 pages = 31.6 MB
EXPLAIN QUERY PLAN index (audio_track_id, uploaded_at)
  [3<-0] SEARCH Video USING COVERING INDEX idx_video_audio_uploaded
TIME MAX subquery, audio_track_id first: rows=1  runs(s)=0.068, 0.068, 0.065  median=0.068s  result_hash=ae9446ef96
BUILD CREATE INDEX idx_wrong_order ON Video(uploaded_at, audio_track_id);
      took 0.9s, index size = 7,708 pages = 31.6 MB
EXPLAIN QUERY PLAN index (uploaded_at, audio_track_id)
  [3<-0] SEARCH Video USING COVERING INDEX idx_wrong_order
TIME MAX subquery, uploaded_at first: rows=1  runs(s)=0.000, 0.000, 0.000  median=0.000s  result_hash=ae9446ef96

==============================================================================
TASK 2 EXTRA 2 - write cost of each index (scratch database copy of the first rows; the real database is not touched)
==============================================================================
WRITE COST F1 index: table Video, 300,000 rows preloaded, then 50,000 rows in one transaction, then 1,000 single-row transactions (median of 3)
   bulk insert   :      49.1 ms without index,     651.5 ms with index  ->   0.98 and  13.03 microseconds per row, +1228 percent
   single inserts:    1266.7 ms without index,    1294.7 ms with index  ->  1.267 and  1.295 ms per row, +2 percent
   pages used after the preload: 4,850 without index, 7,384 with index -> the index adds 2,534 pages = 10.4 MB for 300,000 rows
WRITE COST F4 index: table Like_, 300,000 rows preloaded, then 50,000 rows in one transaction, then 1,000 single-row transactions (median of 3)
   bulk insert   :      42.6 ms without index,     780.4 ms with index  ->   0.85 and  15.61 microseconds per row, +1730 percent
   single inserts:    1247.6 ms without index,    1294.0 ms with index  ->  1.248 and  1.294 ms per row, +4 percent
   pages used after the preload: 2,943 without index, 6,208 with index -> the index adds 3,265 pages = 13.4 MB for 300,000 rows
WRITE COST F12 index: table Impression, 300,000 rows preloaded, then 50,000 rows in one transaction, then 1,000 single-row transactions (median of 3)
   bulk insert   :      45.1 ms without index,     445.6 ms with index  ->   0.90 and   8.91 microseconds per row, +889 percent
   single inserts:    1282.8 ms without index,    1291.7 ms with index  ->  1.283 and  1.292 ms per row, +1 percent
   pages used after the preload: 3,670 without index, 4,944 with index -> the index adds 1,274 pages = 5.2 MB for 300,000 rows

==============================================================================
TASK 2 EXTRA 3 - the rejected index, measured in a scratch copy only (it is NOT created in the real database)
==============================================================================
Turn rows: 350,275; rows inside the F7 window: 350,275; selectivity of the range = 100.0 percent
F7 plan today:
EXPLAIN QUERY PLAN F7 no index
  [11<-0] SCAN t USING INDEX sqlite_autoindex_Turn_1
  [18<-0] SEARCH tu USING INTEGER PRIMARY KEY (rowid=?)
  [21<-0] SEARCH mp USING INDEX sqlite_autoindex_ModelPricePeriod_1 (model_id=? AND priced_at=?)
  [28<-0] USE TEMP B-TREE FOR GROUP BY
  [93<-0] USE TEMP B-TREE FOR ORDER BY
TIME F7 no index: rows=37,926  runs(s)=0.350, 0.342, 0.355  median=0.350s  result_hash=d0c3bb24e9
WRITE COST rejected Turn index: table Turn, 250,000 rows preloaded, then 50,000 rows in one transaction, then 1,000 single-row transactions (median of 3)
   bulk insert   :     130.1 ms without index,     804.3 ms with index  ->   2.60 and  16.09 microseconds per row, +518 percent
   single inserts:    1249.9 ms without index,    1276.5 ms with index  ->  1.250 and  1.277 ms per row, +2 percent
   pages used after the preload: 7,778 without index, 11,062 with index -> the index adds 3,284 pages = 13.5 MB for 250,000 rows
```



### Rejected index (2.3)
`Turn(occurred_at, model_id, priced_at, session_id, template_id, template_version)` for F7. F7 filters `occurred_at` to 2026-08-01 .. 2026-09-01.
The range covers 100 percent of Turn (350,275 of 350,275 rows), so there is nothing to seek; the measured price in a scratch copy is the size and write cost printed above
(`TASK 2 EXTRA 3`), and F7 takes only about 0.3 s in total (`TIME F7 no index` above), so there is little to gain.

---

## Task 3 - Join algorithms
SQLite has only nested-loop joins (inner side by rowid/primary key, existing index, or a temporary automatic index) and uses sorters (`USE TEMP B-TREE`) for GROUP BY, DISTINCT and ORDER BY.
It has no hash join and no sort-merge join, so 3.2 compares formulas (block transfers, memory M = 500 pages, page counts measured by copying each table to a fresh database).
Reproduce: `python bench.py task3`.

### 3.1 Plans and strategy
```
EXPLAIN QUERY PLAN J1  ViewSegment JOIN Impression on impression_id
  [4<-0] SCAN vs
  [6<-0] SEARCH i USING INTEGER PRIMARY KEY (rowid=?)

EXPLAIN QUERY PLAN J2  Like_ JOIN Impression on (user_id, video_id)
  [4<-0] SCAN l
  [8<-0] BLOOM FILTER ON i (user_id=? AND video_id=?)
  [18<-0] SEARCH i USING AUTOMATIC COVERING INDEX (user_id=? AND video_id=?)

```

```
TIME J1 execution: rows=1  runs(s)=1.466, 1.450, 1.453  median=1.453s  result_hash=a606d1524e
```

```
EXPLAIN QUERY PLAN J2  Like_ JOIN Impression on (user_id, video_id)
  [4<-0] SCAN l
  [8<-0] BLOOM FILTER ON i (user_id=? AND video_id=?)
  [18<-0] SEARCH i USING AUTOMATIC COVERING INDEX (user_id=? AND video_id=?)
```

```
TIME J2 execution, no index (SQLite builds a temporary index on 15.4M Impression rows in every run): rows=1  runs(s)=199.307, 200.841, 197.228  median=199.307s  result_hash=6888b63e74
```

```
EXPLAIN QUERY PLAN J2 with index
  [4<-0] SCAN l
  [6<-0] SEARCH i USING COVERING INDEX idx_impression_video_user (video_id=? AND user_id=?)
```

```
TIME J2 execution, with the permanent index: rows=1  runs(s)=2.753, 2.656, 2.646  median=2.656s  result_hash=6888b63e74
```

J1: nested loop, outer = full scan of ViewSegment, inner = primary key lookup in Impression. J2: nested loop, outer = full scan of Like_, inner = temporary automatic covering index over all Impression rows (with my permanent index: that index).

### 3.2 Cost of J1 by formulas (real output)
```
r = ViewSegment: n_r = 5,672,455 rows, b_r = 76,984 pages (measured by copying into a fresh database)
s = Impression : n_s = 15,420,333 rows, b_s = 192,597 pages (measured the same way)
buffer M = default cache 2000 KiB / 4096 B = 500 pages
b-tree of s: interior fanout about 408, interior levels h = ceil(log_408(192,597)) = 3, one lookup = h + 1 = 4 page reads (worst case)

nested loop, block (outer r):  b_r + ceil(b_r / (M-2)) * b_s = 76,984 + 155 * 192,597 = 29,929,519
nested loop, index (PK of s):  b_r + n_r * (h+1)             = 76,984 + 5,672,455 * 4 = 22,766,804   (worst case, nothing cached)
      same, interior pages cached (they are only about 473 pages): b_r + n_r * 1 = 5,749,439
sort-merge: sort r = 2*b_r*(ceil(log_499(ceil(b_r/M))) + 1) = 2*76,984*(1+1) = 307,936; s already in key order;
            merge = b_r + b_s ; total = 307,936 + 76,984 + 192,597 = 577,517
hash join (r is build side, does not fit in M): 3*(b_r + b_s) = 3*(76,984 + 192,597) = 808,743
   sort-merge                                   577,517
   hash join                                    808,743
   index nested loop (interior cached)        5,749,439
   index nested loop (worst)                 22,766,804
   block nested loop                         29,929,519
cheapest by formula: sort-merge

nested loop WITHOUT any index, tuple at a time (one full scan of s for every row of r): b_r + n_r * b_s = 76,984 + 5,672,455 * 192,597 = 1,092,497,892,619  (shown for scale only)

Effect of the memory size M on the cost (block transfers). Sort: 0 extra transfers if r fits in memory, otherwise 2*b_r*(1 + ceil(log_(M-1)(runs))).
Hash join: b_r + b_s if r (the build side) fits in M - 2 pages, otherwise 3*(b_r + b_s).
 M (pages)   M (MB)        block NL    sort-merge     hash join
        50      0.2     309,002,572       731,485       808,743
       500      2.0      29,929,519       577,517       808,743
     5,000     20.5       3,158,536       577,517       808,743
    50,000    204.8         462,178       577,517       808,743
   100,000    409.6         269,581       269,581       269,581

```

```
locality check: in segment_id order, impression_id goes DOWN 0 times out of 5,672,455 rows.
So the PK lookups of the engine's nested loop walk the Impression b-tree almost in order (like a merge), not at random.
```

Cheapest by formula at M = 500: sort-merge. SQLite cannot run it. Its own plan (index nested loop through the primary key) is fast because the lookups walk the Impression b-tree in order.

### 3.3 Three tables: Video, Impression, ViewSegment for creator 12
```
STATISTICS from the data (these are the selectivities, measured with COUNT(DISTINCT ...)):
  Video: 1,000,000 rows, 107,745 distinct owner_id  -> selectivity of owner_id = ? is 1/107,745; videos per owner: min 1, average 9.28, max 46
  Impression: 15,420,333 rows, 1,000,000 distinct video_id -> 15.42 impressions per video
  ViewSegment: 5,672,455 rows, 5,672,455 distinct impression_id -> 0.368 segments per impression (36.8 percent of impressions have a segment)
  creator 12 really has 30 videos (the uniform estimate is 9.3)
```

```
MY ESTIMATES (uniform assumption: every owner has the average number of videos):
  order A  Video(owner) -> Impression -> ViewSegment : intermediate sizes 9.3 -> 143 -> 53
  order B  ViewSegment -> Impression -> Video(owner) : intermediate sizes 5,672,455 -> 5,672,455 (every segment has an impression) -> 53
  order C  Impression -> Video(owner) -> ViewSegment : intermediate sizes 15,420,333 -> 143 -> 53
```

```
  Choice: A, because the selective filter shrinks the first table to a few rows and every later step is a lookup of a few rows.
```

```
Engine's own choice with NO helper indexes:
EXPLAIN QUERY PLAN T3 no indexes
  [5<-0] SCAN vs
  [7<-0] SEARCH i USING INTEGER PRIMARY KEY (rowid=?)
  [10<-0] SEARCH v USING INTEGER PRIMARY KEY (rowid=?)
```

```
TIME T3 engine's order, no helper indexes: rows=1  runs(s)=25.910, 28.284, 67.825  median=28.284s  result_hash=5f8f164255
```

```
Engine's own choice WITH helper indexes (Video(owner_id), Impression(video_id,user_id), ViewSegment(impression_id)):
EXPLAIN QUERY PLAN T3 with indexes
  [5<-0] SEARCH v USING COVERING INDEX idx_t3_video_owner (owner_id=?)
  [11<-0] SEARCH i USING COVERING INDEX idx_impression_video_user (video_id=?)
  [15<-0] SEARCH vs USING COVERING INDEX idx_t3_seg_impression (impression_id=?)
```

```
TIME T3 engine's order: rows=1  runs(s)=0.002, 0.004, 0.008  median=0.004s  result_hash=5f8f164255
```

```
Actual intermediate sizes (real counts):
  videos of the creator   : 30
  impressions of those    : 452
  segments (final count)  : 168

```

```
Forced orders (CROSS JOIN makes SQLite keep the written order):
EXPLAIN QUERY PLAN A video,impression,segment
  [5<-0] SEARCH v USING COVERING INDEX idx_t3_video_owner (owner_id=?)
  [11<-0] SEARCH i USING COVERING INDEX idx_impression_video_user (video_id=?)
  [15<-0] SEARCH vs USING COVERING INDEX idx_t3_seg_impression (impression_id=?)
TIME order A video,impression,segment: rows=1  runs(s)=0.006, 0.007, 0.006  median=0.006s  result_hash=5f8f164255
EXPLAIN QUERY PLAN B segment,impression,video
  [5<-0] SCAN vs USING COVERING INDEX idx_t3_seg_impression
  [7<-0] SEARCH i USING INTEGER PRIMARY KEY (rowid=?)
  [10<-0] SEARCH v USING COVERING INDEX idx_t3_video_owner (owner_id=? AND rowid=?)
TIME order B segment,impression,video: rows=1  runs(s)=6.013, 6.414, 6.248  median=6.248s  result_hash=5f8f164255
EXPLAIN QUERY PLAN C impression,video,segment
  [5<-0] SCAN i USING COVERING INDEX idx_impression_video_user
  [7<-0] SEARCH v USING COVERING INDEX idx_t3_video_owner (owner_id=? AND rowid=?)
  [14<-0] SEARCH vs USING COVERING INDEX idx_t3_seg_impression (impression_id=?)
TIME order C impression,video,segment: rows=1  runs(s)=6.800, 6.835, 6.994  median=6.835s  result_hash=5f8f164255
```

With the helper indexes the engine picks my order A by itself; order A is far faster than B and C; without indexes the engine picks order B and takes 28.28 s.

---

## Task 4 - Predicate pushdown
Query: the "shown" part of F6 (users shown the videos of creator 12). Different from A1 C.3 (which rewrote F2). Reproduce: `python bench.py task4`.

Heuristic algorithm, step by step (rules: selection cascade, selections commute, commuting a selection with a join, selection + product = join, projection pushdown):
1. start: `project[user_id]( select[i.video_id = v.video_id AND v.owner_id = 12]( Impression x Video ) )`
2. cascade (rule 1): two chained selections, the join condition and `owner_id = 12`
3. push `owner_id = 12` below the product, onto Video (rules 2 and 4), because it uses only Video attributes
4. put the most restrictive leaf (Video after the filter: 30 rows) first
5. product + join condition become a join on video_id (rule 3)
6. push projections: Impression keeps (user_id, video_id), Video keeps (video_id) (rule 5)
7. mark the join as pipelined
Final tree: `project[user_id]( join[video_id]( project[user_id,video_id](Impression), project[video_id](select[owner_id = 12](Video)) ) )`. Figures are in the PDF.

Where the rule fails (outer join, filter on the null-supplying side):
```
WHERE after LEFT JOIN: 7,092 rows   <- SELECT COUNT(*) FROM Turn t LEFT JOIN UserRating ur ON ur.turn_id = t.turn_id WHERE ur.thumbs = 'down'
filter pushed INTO the null-supplying side: 350,275 rows   <- SELECT COUNT(*) FROM Turn t LEFT JOIN (SELECT * FROM UserRating WHERE thumbs = 'down') ur ON ur.turn_id = t.turn_id
same WHERE with an INNER join: 7,092 rows   <- SELECT COUNT(*) FROM Turn t JOIN UserRating ur ON ur.turn_id = t.turn_id WHERE ur.thumbs = 'down'
```

```
EXPLAIN QUERY PLAN WHERE after LEFT JOIN
  [4<-0] SCAN ur
  [8<-0] SEARCH t USING INTEGER PRIMARY KEY (rowid=?)
```


Literal SQL:
```
Naive:  WITH j AS MATERIALIZED (SELECT i.user_id, v.owner_id FROM Impression i JOIN Video v ON v.video_id = i.video_id)
        SELECT DISTINCT user_id FROM j WHERE owner_id = 12
Pushed: WITH vv AS MATERIALIZED (SELECT video_id FROM Video WHERE owner_id = 12)
        SELECT DISTINCT i.user_id FROM vv JOIN Impression i ON i.video_id = vv.video_id
As written: SELECT DISTINCT i.user_id FROM Impression i JOIN Video v ON v.video_id = i.video_id WHERE v.owner_id = 12
```
Raw plans and times, no helper index, then with `Impression(video_id, user_id)`:
```
EXPLAIN QUERY PLAN as written (optimizer)
  [4<-0] SCAN i
  [6<-0] SEARCH v USING INTEGER PRIMARY KEY (rowid=?)
  [17<-0] USE TEMP B-TREE FOR DISTINCT
```

```
TIME as written (optimizer): rows=451  runs(s)=65.915, 65.669, 65.543  median=65.669s  result_hash=6e1759760c
```

```
EXPLAIN QUERY PLAN pushed
  [3<-0] MATERIALIZE vv
  [6<-3] SCAN Video
  [18<-0] SCAN i
  [24<-0] BLOOM FILTER ON vv (video_id=?)
  [33<-0] SEARCH vv USING AUTOMATIC COVERING INDEX (video_id=?)
  [46<-0] USE TEMP B-TREE FOR DISTINCT
```

```
TIME pushed: rows=451  runs(s)=1.084, 1.079, 1.143  median=1.084s  result_hash=6e1759760c
```

```
EXPLAIN QUERY PLAN naive
  [3<-0] MATERIALIZE j
  [7<-3] SCAN i
  [9<-3] SEARCH v USING INTEGER PRIMARY KEY (rowid=?)
  [22<-0] SCAN j
  [32<-0] USE TEMP B-TREE FOR DISTINCT
```

```
TIME naive: rows=451  runs(s)=69.180, 68.757, 69.174  median=69.174s  result_hash=6e1759760c
```

```
EXPLAIN QUERY PLAN as written (optimizer)
  [4<-0] SCAN v
  [8<-0] SEARCH i USING COVERING INDEX idx_impression_video_user (video_id=?)
  [19<-0] USE TEMP B-TREE FOR DISTINCT
```

```
TIME as written (optimizer): rows=451  runs(s)=0.075, 0.080, 0.076  median=0.076s  result_hash=6e1759760c
```

```
EXPLAIN QUERY PLAN pushed
  [3<-0] MATERIALIZE vv
  [6<-3] SCAN Video
  [20<-0] SCAN vv
  [22<-0] SEARCH i USING COVERING INDEX idx_impression_video_user (video_id=?)
  [35<-0] USE TEMP B-TREE FOR DISTINCT
```

```
TIME pushed: rows=451  runs(s)=0.074, 0.074, 0.077  median=0.074s  result_hash=6e1759760c
```

```
EXPLAIN QUERY PLAN naive
  [3<-0] MATERIALIZE j
  [7<-3] SCAN i USING COVERING INDEX idx_impression_video_user
  [9<-3] SEARCH v USING INTEGER PRIMARY KEY (rowid=?)
  [22<-0] SCAN j
  [32<-0] USE TEMP B-TREE FOR DISTINCT
```

```
TIME naive: rows=451  runs(s)=2.779, 2.730, 2.598  median=2.730s  result_hash=6e1759760c
```

Without an index SQLite did NOT push the filter down in the query as written (scan of Impression first, Video looked up per row, owner tested last). With the index it changed the loop order itself
(`SCAN v` first, then an index search into Impression): the plan is the evidence that the pushdown happened.

---

## Task 5 - Concurrency
Reproduce: `python concurrency_demo.py` (builds `concurrency_demo.db` from schema.sql, WAL mode, two connections in two threads, steps forced with events). Step-by-step SQL for two shells: `concurrency_demo.sql`.

WAL locking facts used: one writer at a time; readers use a snapshot and never block or get blocked; a deferred BEGIN that read and then writes after another connection committed is refused
("database is locked", SQLITE_BUSY_SNAPSHOT); BEGIN IMMEDIATE takes the write lock first and other writers wait for it.

### 5.1 A1 transaction T2: schedule `W_A(E) R_B(E) C_A`, E = VideoModerationEvent
Only conflict: `R_B(E)` before `W_A(E)`. Precedence graph: `B --> A`. No cycle, so conflict-serializable; equivalent serial order B then A.
```
[    89.5 ms] A  BEGIN
[    89.6 ms] A  INSERT VideoModerationEvent(video 1, 'taken_down')   [write W_A(E)]
[   102.5 ms] B  SELECT current state  [read R_B(E)] -> 'live'   (A has not committed: B still sees the old row)
[   102.6 ms] B  INSERT [write W_B(E)] -> error: database is locked   (WAL allows ONE writer at a time)
[   103.4 ms] A  COMMIT
[   108.1 ms] B  SELECT current state  [read R_B(E)] -> 'taken_down'   (after the commit B sees the new row)
```


### 5.2 New interleaving: handle change limit (A1 T3 rule: at most 2 changes), item H = Handle rows of user 20
```
step | Request A                              | Request B
 1   | R_A(H): changes = 1, allowed           |
 2   |                                        | R_B(H): changes = 1, allowed
 3   | W_A(H): end handle, insert from_A      |
 4   | commit                                 |
 5   |                                        | W_B(H): end handle, insert from_B
 6   |                                        | commit
```
Edges `A --> B` (R_A before W_B) and `B --> A` (R_B before W_A): a cycle `A --> B --> A`, so NOT conflict-serializable. Anomaly: write skew (check-then-act race).
Seen as four separate database transactions (read A, read B, write A, write B) the schedule has no cycle: SQLite kept its promise; the application split one logical step into two transactions.

### 5.3 Demo, fix and cost (real output)
```
[   185.0 ms] A  check (autocommit read): changes so far = 1, limit 2 -> allowed
[   196.9 ms] B  check (autocommit read): changes so far = 1, limit 2 -> allowed
[   202.4 ms] A  write transaction committed
[   204.0 ms] B  write transaction committed
RESULT 5.3a: handle changes for user 20 = 3 (limit 2) -> LIMIT BROKEN
       ('first', '2026-01-01T00:00:00Z', '2026-03-01T00:00:00Z')
       ('second', '2026-03-01T00:00:00Z', '2026-09-10T10:00:00Z')
       ('handle_from_A', '2026-09-10T10:00:00Z', '2026-09-10T10:00:05Z')
       ('handle_from_B', '2026-09-10T10:00:05Z', None)
```

```
[   284.3 ms] A  BEGIN (deferred); check inside: changes = 1 -> allowed
[   295.8 ms] B  BEGIN (deferred); check inside: changes = 1 -> allowed
[   303.5 ms] A  write + COMMIT ok
[   303.7 ms] B  write -> database is locked   (B's snapshot is stale; SQLite refuses the write)
[   303.8 ms] B  RETRY: BEGIN, check again: changes = 2 -> refused
RESULT 5.3b: handle changes for user 20 = 2 (limit 2) -> limit kept
       ('first', '2026-01-01T00:00:00Z', '2026-03-01T00:00:00Z')
       ('second', '2026-03-01T00:00:00Z', '2026-09-10T10:00:00Z')
       ('handle_from_A', '2026-09-10T10:00:00Z', None)
```

```
[   378.9 ms] B  BEGIN IMMEDIATE ... (blocks, busy timeout 5 s)
[   379.4 ms] A  BEGIN IMMEDIATE (write lock taken); check: changes = 1 -> allowed
[   689.5 ms] A  write + COMMIT ok
[   707.3 ms] B  got the lock after waiting 328 ms; check: changes = 2 -> refused (limit reached)
RESULT 5.3c: handle changes for user 20 = 2 (limit 2) -> limit kept
       ('first', '2026-01-01T00:00:00Z', '2026-03-01T00:00:00Z')
       ('second', '2026-03-01T00:00:00Z', '2026-09-10T10:00:00Z')
       ('handle_from_A', '2026-09-10T10:00:00Z', None)
```

```
 lock held (ms)  median wait (ms)  extra over hold (ms)  predicted by backoff (ms)
            1.6              14.5                  12.9                          3
           51.9              57.0                   5.2                         53
          101.5             120.6                  19.0                        103
          301.5             334.5                  33.0                        328
         1001.6            1094.1                  92.6                       1028
The waiter does not wake the moment the lock is free. It sleeps in growing steps (1, 2, 5, 10, 15, 20, 25, 25, 25, 50, 50, 100 ms ...), so it is late by up to one step.
```

```
 threads mode        expected  final  lost  retries  total s  median ms   p95 ms
       2 autocommit       200    106    94        0     0.28       1.12     2.56
       2 deferred         200    200     0      142     0.26       1.14     2.57
       2 immediate        200    200     0        0     0.27       1.13     2.40
       4 autocommit       400    100   300        0     0.57       1.14     2.54
       4 deferred         400    400     0      719     0.51       1.13     2.80
       4 immediate        400    400     0        0     0.57       1.14     2.67
       8 autocommit       800    100   700        0     1.36       1.14     2.65
       8 deferred         800    800     0     3518     0.99       1.14    53.39
       8 immediate        800    800     0        0     1.43       1.14     2.54
```

```
Uncontended cost of BEGIN IMMEDIATE (one connection, 300 transactions of read + write, median per transaction):
  deferred   median 1.13 ms per transaction
  immediate  median 1.12 ms per transaction
```

```
[ 18584.3 ms] A  BEGIN; INSERT VideoModerationEvent(video 1, 'taken_down')   [write W_A(E), not committed]
[ 18585.5 ms] B  default isolation: SELECT state -> error: database table is locked: VideoModerationEvent   (shared cache: the table is write-locked, so the reader is blocked)
[ 18585.7 ms] B  PRAGMA read_uncommitted = 1; SELECT state -> 'taken_down'   [read R_B(E) in the middle of A's write]
[ 18585.7 ms] A  ROLLBACK   (the reviewer withdraws the decision)
[ 18585.8 ms] B  SELECT state -> 'live'
RESULT 5.4: B saw 'taken_down', a value that was never committed and is not in the database now ('live'). That is a dirty read.
Schedule: W_A(E)  R_B(E)  Abort_A. Remove the aborted transaction A and B has read a value that no committed transaction ever wrote,
so no serial order of the committed transactions explains what B saw.
[ 18666.2 ms] B  ordinary WAL connection, same moment: SELECT state -> 'live'   (B reads the last committed snapshot, no waiting)
```

What the fix costs: with BEGIN IMMEDIATE the second writer waits at BEGIN while the first holds the lock (about 330 ms in the demo), and all writers of the database wait, because WAL allows one writer; readers never wait and nothing retries.
With a plain BEGIN nobody waits for the lock, but the loser is refused and must roll back and run the transaction again (see the retries column).

---


---

## Stability of the numbers (this run against an earlier session)
| Measurement | Earlier session (s) | Final run (s) |
|---|---|---|
| F12 before the index | 252.0 | 220.3 |
| F12 after the index | 10.61 | 8.970 |
| F4 before the index | 0.059 | 0.051 |
| Task 4 as written, no index | 84.29 | 65.67 |
| Task 4 pushed, no index | 1.385 | 1.084 |
| Task 3 three tables, no helper index | 33.38 | 28.28 |

Ratios and conclusions are the same; single numbers move (different sessions, and about 25 percent between two Python processes). The F12 re-run of an earlier session had one unexplained 507.6 s outlier among its three timed runs; the cause was not found.
All final numbers were taken in one sitting on AC power. A first attempt on battery power was 3 to 4 times slower and was discarded.

## Appendix - LLM use
The full, honest list of the assistant's mistakes (ten cases) is in the PDF report, appendix. In short: wrong predictions about the F1 column order and about where the F12 time goes; wrong index sizes (freed pages reused);
broken scripts from shell here-documents (including a tab character in a LaTeX table); a wait loop that reported "finished" too early; Task 1 queries that did not meet the handout rule (F7, then F4);
shortened plans in an earlier version; an unverified "checked" claim about the generator (then verified by running both generators at SCALE 1 and 10: identical); an unsupported guess about the laptop sleeping;
timings started on battery power; and four false alarms of my own spot-check script. In A1 the assistant claimed that LaTeX compiled without testing it.

