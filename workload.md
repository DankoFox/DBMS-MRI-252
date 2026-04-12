# Workload Plan — DBMS MRI Project (SQL Server 2025)

## Project Overview

- **DBMS:** Microsoft SQL Server 2025 (Docker)
- **Dataset:** 500 patients — text (Excel radiologist reports) + images (DICOM `.ima` files)
- **Stack:** Python ETL (ResNet-18 embeddings, pydicom, pyodbc) → SQL Server with native `VECTOR(512)` support

---

## Assessment Criteria

| # | Criterion | Points |
|---|-----------|--------|
| 1 | Indexing | 2 |
| 2 | Query Processing | 2 |
| 3 | Transactions | 2 |
| 4 | Concurrency Control | 2 |
| 5 | Final Report | 1 |
| 6 | Presentation | 1 |
| **Total** | | **10** |

---

## Member A — Indexing + Query Processing (4 points)

**Deliverables:** `sql/02_indexes.sql`, `sql/03_query_processing.sql`, `src/app_queries.py`

### Indexing Tasks

| Task | Detail |
|------|--------|
| A1. B-Tree Index demo | Query `MRIImages` by `SeriesType` WITHOUT index → `SET STATISTICS IO ON` → record logical reads (Table Scan). Create `CREATE INDEX idx_series ON MRIImages(SeriesType)` → re-run → record logical reads (Index Seek). Screenshot both. |
| A2. Composite Index demo | Create `(PatientID, SliceNumber)` covering index. Show scan vs. seek difference. |
| A3. DiskANN Vector Index | `CREATE VECTOR INDEX idx_mri_embeddings ON MRIImages(Embedding) WITH (DISTANCE_METRIC = 'COSINE')`. Compare `VECTOR_DISTANCE()` performance before/after. |

### Query Processing Tasks

| Task | Detail |
|------|--------|
| A4. Execution Plan analysis | Use `SET SHOWPLAN_XML ON` or SSMS visual plan for: (1) simple SELECT, (2) JOIN query (Patient + Images), (3) vector similarity query. Annotate operators: Table Scan, Index Seek, Nested Loop, Hash Match, Vector Distance. |
| A5. Query optimization | Show how adding indexes changes the execution plan. Compare estimated vs. actual row counts. |
| A6. Theory vs. Practice | Compare textbook B-Tree indexing with SQL Server's clustered/non-clustered index implementation. Compare theoretical KNN with DiskANN approximate nearest neighbor. |

**Estimated effort:** ~8–10 hours

---

## Member B — Transactions (2 points)

**Deliverables:** `sql/04_transactions.sql`

| Task | Detail |
|------|--------|
| B1. Basic ACID demo | `BEGIN TRAN` → insert a patient + images → `COMMIT`. Verify data exists. |
| B2. Rollback demo | `BEGIN TRAN` → insert patient → insert partial images → simulate error → `ROLLBACK`. Prove zero partial records (atomicity). |
| B3. SAVEPOINT demo | `BEGIN TRAN` → insert patient → `SAVE TRAN sp1` → insert images → error → `ROLLBACK TRAN sp1` → `COMMIT`. Show patient exists but images don't. |
| B4. Implicit vs Explicit transactions | `SET IMPLICIT_TRANSACTIONS ON` — show auto-begin behavior. Compare with explicit `BEGIN TRAN`. |
| B5. Error handling with TRY/CATCH | Wrap ingestion in `BEGIN TRY...BEGIN CATCH` with `XACT_STATE()` checks. |
| B6. WAL (Write-Ahead Logging) | Query `sys.fn_dblog()` to show log records before/after a transaction. Explain theory of WAL vs. SQL Server's implementation. |
| B7. Theory vs. Practice | Compare textbook ACID properties and WAL protocol with SQL Server's transaction log architecture. |

**Estimated effort:** ~6–8 hours

---

## Member C — Concurrency Control (2 points)

**Deliverables:** `sql/05_concurrency.sql`

| Task | Detail |
|------|--------|
| C1. Dirty Read demo | Session 1: `BEGIN TRAN` → UPDATE patient notes. Session 2: `SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED` → SELECT → sees uncommitted data. Session 1: `ROLLBACK`. |
| C2. Blocking demo | Session 1: `BEGIN TRAN` → `UPDATE Patients SET ... WHERE PatientID=1` (holds X lock). Session 2: `SELECT ... WHERE PatientID=1` → blocked. Show via `sys.dm_exec_requests` + `sys.dm_tran_locks`. |
| C3. Deadlock demo | Session 1 locks row A then requests row B. Session 2 locks row B then requests row A. SQL Server detects deadlock → one victim. Capture deadlock graph from `system_health` extended event. |
| C4. Isolation levels comparison | Run same scenario under `READ COMMITTED`, `REPEATABLE READ`, `SERIALIZABLE`. Show different behaviors. |
| C5. RCSI (Row-versioning) | `ALTER DATABASE MRIDatabase SET READ_COMMITTED_SNAPSHOT ON`. Re-run C2 — Session 2 now reads old version (no blocking). Explain `tempdb` version store. |
| C6. Lock monitoring | Query `sys.dm_tran_locks`, `sys.dm_os_wait_stats`. Show lock types: S, X, IX, IS. |
| C7. Theory vs. Practice | Compare textbook 2PL (Two-Phase Locking), timestamp ordering, and MVCC with SQL Server's lock manager + row-versioning (RCSI/Snapshot). |

**Estimated effort:** ~6–8 hours

---

## Member D — Report + Presentation (2 points)

**Deliverables:** Final report (PDF), presentation slides

| Task | Detail |
|------|--------|
| D1. Report structure | Title, Abstract, Introduction, Architecture, Methodology (per criterion), Results (screenshots + analysis), Theory vs. Practice comparison table, Conclusion. |
| D2. Collect demo outputs | Gather screenshots/outputs from A, B, C: execution plans, STATISTICS IO, lock DMVs, deadlock graphs, transaction logs. |
| D3. Theory vs. Practice table | For each of the 4 criteria, create a two-column comparison: "Textbook concept" vs. "SQL Server 2025 implementation". |
| D4. Presentation slides | ~15–20 slides for 30-min presentation. Architecture diagram, live demo flow, key findings, Q&A preparation. |
| D5. Q&A prep | Prepare answers for likely questions: Why SQL Server 2025? Why VECTOR type over application-side search? How does DiskANN compare to brute-force KNN? What isolation level would you use in production? |

**Estimated effort:** ~8–10 hours

---

## Timeline (2-week sprint)

```
Week 1:
  Day 1-2:  All members set up Docker + ingest data (verify pipeline works)
  Day 2-4:  A → indexing scripts, B → transaction scripts, C → concurrency scripts
  Day 4-5:  A → query processing, B/C → screenshots + theory comparison notes
  Day 5-7:  D collects outputs, starts report draft

Week 2:
  Day 1-2:  A/B/C review each other's scripts, fix issues
  Day 3-4:  D finishes report, all review
  Day 5:    D builds slides, team rehearses presentation
  Day 6:    Dry run with Q&A practice
  Day 7:    Final polish + submission
```

---

## Files To Be Created

| File | Owner | Status |
|------|-------|--------|
| `sql/02_indexes.sql` | Member A | Not started |
| `sql/03_query_processing.sql` | Member A | Not started |
| `sql/04_transactions.sql` | Member B | Not started |
| `sql/05_concurrency.sql` | Member C | Not started |
| `src/app_queries.py` | Member A | Not started |
| Report (PDF) | Member D | Not started |
| Slides | Member D | Not started |
