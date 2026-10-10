# ScrollSense - Assignment 2 (DA3406 Data Management)

Roll no: DA24B048 | Name: Mithilesh Rathod | IIT Madras

Storage, indexing and query processing on my own A1 schema, SQLite, scaled to SCALE = 50 (15.4 million impressions).

## Files

| File | What it is |
|---|---|
| `DA24B048_A2_report.pdf` | Full report: Tasks 1 to 5, code, plans, timings, answers |
| `indexes.sql` | The 3 composite indexes (Task 2) |
| `plan_analysis.md` | Query plans, timings and calculations for all tasks |
| `concurrency_demo.sql` | Step-by-step two-session demo of the anomaly and the fix (Task 5) |
| `queries.sql` | A1 queries (unchanged) plus the A2 queries |
| `transactions.sql` | A1 transactions, updated so the file runs as a script |

## Main results (SCALE 50, median of 3 runs)

| Query | Before | After | Faster |
|---|---|---|---|
| F1 | 0.289 s | 0.115 s | 2.5x |
| F4 | 0.051 s | 0.030 s | 1.7x |
| F12 | 220.3 s | 8.97 s | 24.6x |

Predicate pushdown (Task 4): 65.7 s as written, 1.08 s pushed down.

## How to run

1. Open the SCALE 50 database in DBeaver (the `.db` file is not in this repo, it is about 1.9 GB).
2. Run `indexes.sql` to create the indexes. Use `EXPLAIN QUERY PLAN` before and after.
3. Run the queries in `queries.sql` one at a time. F2 and F12 take minutes without the indexes.
4. For Task 5, follow `concurrency_demo.sql` in two separate SQL editor sessions.

**Warning:** `transactions.sql` changes data. Run it on a copy of the database only.

SQLite 3.50.4, page size 4096, WAL mode, PRAGMA foreign_keys = ON.
