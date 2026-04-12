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


---

## Member C — Concurrency Control (2 points)

**Deliverables:** `sql/05_concurrency.sql`

### C1. Dirty Read Demo

| Step | Action | What to show |
|------|--------|-------------|
| 1 | Session 1: `BEGIN TRAN` → `UPDATE Patients SET ClinicalNotes='DIRTY...' WHERE PatientID=1` (do NOT commit) | X lock acquired on row |
| 2 | Session 2: `SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED` → `SELECT ... WHERE PatientID=1` | Sees the uncommitted value → **dirty read** |
| 3 | Session 1: `ROLLBACK` | Change reverted |
| 4 | Session 2: `SELECT` again | Original value restored — Session 2 previously read phantom data |

**Theory link:** Textbook says dirty read violates Isolation in ACID. The lecture's read/write lock rules (slide 15–16) require a read lock before reading — READ UNCOMMITTED skips requesting S locks, allowing dirty reads.

---

### C2. Blocking (Lock Wait) Demo

| Step | Action | What to show |
|------|--------|-------------|
| 1 | Session 1: `BEGIN TRAN` → `UPDATE Patients ... WHERE PatientID=2` | Holds X lock on row |
| 2 | Session 2 (READ COMMITTED): `SELECT ... WHERE PatientID=2` | **Blocked** — waits for S lock |
| 3 | Monitor: query `sys.dm_tran_locks` | Show S=WAIT vs X=GRANT |
| 4 | Session 1: `COMMIT` | Session 2 unblocks |

**Theory link:** This is the textbook's mutual exclusion — Shared/Exclusive lock compatibility matrix (slide 10): Read-Read = Yes, Read-Write = No, Write-Write = No. SQL Server implements the same compatibility table.

---

### C3. Deadlock Demo

| Step | Action | What to show |
|------|--------|-------------|
| 1 | Session 1: `BEGIN TRAN` → `UPDATE ... WHERE PatientID=1` | Holds X lock on P1 |
| 2 | Session 2: `BEGIN TRAN` → `UPDATE ... WHERE PatientID=2` | Holds X lock on P2 |
| 3 | Session 1: `UPDATE ... WHERE PatientID=2` | Waits for P2 (held by S2) |
| 4 | Session 2: `UPDATE ... WHERE PatientID=1` | Waits for P1 (held by S1) → **Deadlock!** |
| 5 | SQL Server detects cycle → kills one session (error 1205) | Capture deadlock graph from `system_health` extended event |

**Theory link:** Textbook wait-for-graph (slides 29–31): cycle T1→T2→T1 = deadlock. SQL Server maintains the same wait-for-graph internally and checks it every 5 seconds. Victim selection: textbook says roll back least-cost transaction; SQL Server uses `DEADLOCK_PRIORITY` + estimated rollback cost.

---

### C4. Isolation Levels Comparison

| Sub-task | Isolation Level | Anomaly tested | Expected |
|----------|----------------|---------------|----------|
| C4a | READ COMMITTED | Non-repeatable read | Second SELECT in same txn sees updated data → anomaly present |
| C4b | REPEATABLE READ | Non-repeatable read | Second SELECT sees same data → S lock held until COMMIT → anomaly prevented |
| C4c | REPEATABLE READ | Phantom read | `COUNT(*)` changes when another session INSERTs → anomaly present |
| C4d | SERIALIZABLE | Phantom read | Range lock blocks INSERTs → anomaly prevented |

**Anomaly prevention matrix:**

| Level | Dirty Read | Non-Repeatable Read | Phantom Read |
|-------|-----------|-------------------|-------------|
| READ UNCOMMITTED | Allowed | Allowed | Allowed |
| READ COMMITTED | Prevented | Allowed | Allowed |
| REPEATABLE READ | Prevented | Prevented | Allowed |
| SERIALIZABLE | Prevented | Prevented | Prevented |
| SNAPSHOT (SQL Server) | Prevented | Prevented | Prevented |

**Theory link:** The textbook (slide 3) defines purpose of CC as enforcing Isolation. SQL standard isolation levels map directly to which read/write conflicts are resolved. SQL Server adds SNAPSHOT as a 5th non-standard level using MVCC.

---

### C5. RCSI / Multi-Version Concurrency Control (MVCC)

| Step | Action | What to show |
|------|--------|-------------|
| 1 | `ALTER DATABASE MRIDatabase SET READ_COMMITTED_SNAPSHOT ON` | Enable row versioning |
| 2 | Session 1: `BEGIN TRAN` → `UPDATE ... WHERE PatientID=2` (don't commit) | X lock held |
| 3 | Session 2 (READ COMMITTED): `SELECT ... WHERE PatientID=2` | **No blocking!** Reads old committed version from tempdb version store |
| 4 | Session 1: `COMMIT` | New value committed |
| 5 | Session 2: `SELECT` again | Now sees new value |
| 6 | Query `sys.dm_tran_version_store_space_usage` | Show version store in tempdb |

**Theory link:** This maps to textbook Chapter 5 Section 4 — Multiversion Concurrency Control (slides 42–48). Theory says MVCC maintains multiple versions of each data item so reads are never rejected. SQL Server's implementation stores row versions in `tempdb` rather than inline, and uses a 14-byte version tag per row.

---

### C6. Lock Monitoring & Granularity

| Sub-task | What to do | What to show |
|----------|-----------|-------------|
| C6a | Query `sys.dm_tran_locks` during active transactions | Lock types: S, X, IS, IX, U |
| C6b | Query `sys.dm_os_wait_stats WHERE wait_type LIKE 'LCK%'` | Lock wait statistics |
| C6c | Force lock escalation: `UPDATE Patients SET StudyDate=GETDATE()` (all 500 rows) | Row locks → TABLE lock escalation |

**Theory link:** Textbook Multiple Granularity Locking (slides 52–58). Hierarchy: Database → File → Page → Row. SQL Server implements exactly this with intention locks (IS, IX, SIX) at higher levels and S/X at leaf level. Lock escalation is SQL Server's pragmatic solution to the overhead of many fine-grained locks.

---

### C7. Theory vs. Practice — Concurrency Control

*Comprehensive comparison based on Chapter 5 lecture (Elmasri et al., 2006) vs. Microsoft SQL Server implementation:*

#### 1. Two-Phase Locking (2PL)

| Aspect | Theory (Textbook) | SQL Server Practice |
|--------|-------------------|-------------------|
| **Basic concept** | Transaction has growing phase (acquire locks) and shrinking phase (release locks). No new locks after first unlock (slides 18–19). | SQL Server uses **Strict 2PL** — all locks held until `COMMIT` or `ROLLBACK` (never releases early). This is a stricter variant than basic 2PL. |
| **Lock types** | Binary locks (lock/unlock) or Shared/Exclusive locks (slides 6–16). | Shared (S), Exclusive (X), Update (U), Intent Shared (IS), Intent Exclusive (IX), Shared with Intent Exclusive (SIX), Schema locks (Sch-S, Sch-M), Bulk Update (BU), Key-Range locks. Much richer than textbook's 2 lock modes. |
| **Lock compatibility** | 2×2 matrix: Read-Read=Yes, Read-Write=No, Write-Write=No (slide 10). | Full compatibility matrix with ~8 lock modes. Key additions: U lock (for read-then-write pattern) prevents conversion deadlocks; Intent locks enable hierarchical locking. |
| **Lock conversion** | Upgrade (read→write) and downgrade (write→read) (slide 17). | SQL Server supports lock conversion. The U (Update) lock is specifically designed for this: acquire U first, then escalate to X when ready to write. This avoids the deadlock that can occur when two transactions both hold S locks and try to upgrade. |
| **Well-formed transactions** | Must lock before read/write, unlock after all ops complete (slides 5, 9, 15–16). | Handled automatically by the Lock Manager — application code never explicitly calls lock/unlock. SQL Server enforces well-formedness internally. |

#### 2. Deadlock Handling

| Aspect | Theory (Textbook) | SQL Server Practice |
|--------|-------------------|-------------------|
| **Prevention** | Conservative 2PL: lock all items before execution (slide 27–28). | Not used by default (impractical). Developers can use `sp_getapplock` for application-level lock ordering. |
| **Detection** | Wait-for-graph: nodes=transactions, edges=waits. Cycle=deadlock (slides 29–31). | SQL Server's Lock Monitor thread checks for cycles in the wait-for graph **every 5 seconds** (or immediately when a wait exceeds a threshold). |
| **Resolution** | Select a victim and roll back (slide 29). | Victim selection based on: (1) `SET DEADLOCK_PRIORITY` (-10 to 10), (2) estimated rollback cost. Victim gets error 1205. |
| **Avoidance (Wait-Die / Wound-Wait)** | Uses transaction timestamps to decide who waits and who dies (slides 33–34). | Not directly implemented. SQL Server relies on detection-and-kill instead. However, `LOCK_TIMEOUT` provides a timeout-based alternative. |
| **Starvation** | A transaction repeatedly chosen as victim (slide 35). | Mitigated by `DEADLOCK_PRIORITY`: set high priority on critical transactions. Also, restarted transactions retain the same priority. |

#### 3. Timestamp-Based Concurrency Control

| Aspect | Theory (Textbook) | SQL Server Practice |
|--------|-------------------|-------------------|
| **Basic TO** | Each transaction gets TS. read_TS(X) and write_TS(X) maintained per item. Conflict → abort younger/older based on TS comparison (slides 36–39). | SQL Server does NOT use pure timestamp ordering for concurrency control. It is a lock-based system. |
| **Thomas's Write Rule** | Obsolete writes ignored if write_TS(X) > TS(T) (slide 41). | Not applicable — SQL Server always uses locks to serialize writes. |
| **Where timestamps appear** | Theoretical concept only. | SQL Server uses row version timestamps internally for **SNAPSHOT** and **RCSI** isolation. The `@@DBTS` (rowversion) and transaction sequence numbers serve a similar logical role but are used for versioning, not for ordering. |

#### 4. Multi-Version Concurrency Control (MVCC)

| Aspect | Theory (Textbook) | SQL Server Practice |
|--------|-------------------|-------------------|
| **Core idea** | Maintain multiple versions of each data item X₁, X₂, ..., Xₙ. Reads always succeed by finding the right version (slides 42–44). | SQL Server MVCC via **Row Versioning**: when a row is modified, the old version is copied to the **tempdb version store**. Readers see the last committed version. |
| **Read never rejected** | Guaranteed in theory (slide 44, Rule 2). | Guaranteed under SNAPSHOT and RCSI modes. Under lock-based READ COMMITTED, reads CAN be blocked. |
| **Version storage** | Textbook implies per-item version chain. Garbage collection needed (slide 42). | Versions stored in **tempdb**. 14-byte version tag added to each row. Garbage collection runs automatically. `sys.dm_tran_version_store_space_usage` shows usage. |
| **Certify lock (MV2PL)** | Third lock mode: read/write/certify. Read+Write compatible, but Certify exclusive (slides 46–48). | Not directly implemented. SQL Server's RCSI achieves the same goal differently: writers hold X locks but readers read from version store without any lock. |
| **Trade-off** | More storage for versions vs. better concurrency (slide 42). | tempdb can grow significantly under heavy write workloads with long-running read transactions. Must monitor `version_store_reserved_page_count`. |

#### 5. Optimistic (Validation) Concurrency Control

| Aspect | Theory (Textbook) | SQL Server Practice |
|--------|-------------------|-------------------|
| **Three phases** | Read → Validation → Write (slides 49–51). | SQL Server's **SNAPSHOT isolation** is conceptually similar: transactions read from a consistent snapshot (read phase), detect write-write conflicts at commit time (validation), and apply changes (write phase). |
| **Validation check** | Compare read_set/write_set with committed transactions (slide 50). | Under SNAPSHOT isolation, if two transactions modify the same row, the second to commit gets error 3960 ("Snapshot isolation transaction aborted due to update conflict"). This is the validation failure. |
| **When to use** | When conflicts are rare — optimistic assumption (slide 49). | SNAPSHOT isolation is best for read-heavy workloads where write conflicts are rare. For write-heavy OLTP, lock-based READ COMMITTED is typically better. |

#### 6. Lock Granularity & Multiple Granularity Locking

| Aspect | Theory (Textbook) | SQL Server Practice |
|--------|-------------------|-------------------|
| **Hierarchy** | Database → File → Page → Record (slides 52–53). | Database → Table → Partition → Page → Row (KEY). Same concept, slightly different names. |
| **Intention locks** | IS, IX, SIX — signal intent to lock descendant nodes (slides 53–55). | Fully implemented: IS, IX, SIX. Visible in `sys.dm_tran_locks` as `resource_type` = TABLE with `request_mode` = IS/IX. |
| **Compatibility matrix** | 5×5 matrix: IS, IX, S, SIX, X (slide 55). | Same matrix. Plus additional modes (U, Sch-S, Sch-M, BU). |
| **Rules for MGL** | Lock root first, then descend with appropriate intent locks. Unlock bottom-up (slides 55–56). | Handled automatically by Lock Manager. Example: to update a single row, SQL Server acquires IX on TABLE → IX on PAGE → X on KEY. |
| **Lock escalation** | Not specifically in textbook. | SQL Server practical addition: when >5000 row/page locks on one table, escalates to TABLE lock. Configurable via `ALTER TABLE ... SET (LOCK_ESCALATION = {TABLE|AUTO|DISABLE})`. |

---

**Summary for presentation:**
- SQL Server is fundamentally a **lock-based (Strict 2PL)** system
- It adds **MVCC (row versioning)** as an optional layer via RCSI/SNAPSHOT
- It does **NOT use** pure timestamp ordering or optimistic validation (though SNAPSHOT has similarities to optimistic CC)
- Deadlock handling = **detection + resolution** (not prevention/avoidance)
- Lock granularity = **Multiple Granularity Locking** with automatic lock escalation

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
| `sql/05_concurrency.sql` | Member C | **Created** |
| `src/app_queries.py` | Member A | Not started |
| Report (PDF) | Member D | Not started |
| Slides | Member D | Not started |
