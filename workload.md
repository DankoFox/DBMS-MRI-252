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

## Indexing + Query Processing

**Deliverables:** `sql/02_indexes.sql`, `sql/03_query_processing.sql`, `src/app_queries.py`

### A1. Primary Index (Clustered Index) Demo

| Step | Action | What to show |
|------|--------|-------------|
| 1 | Show `Patients` table already has a clustered index on `PatientID` (PK) | `sp_helpindex 'Patients'` — CLUSTERED, UNIQUE |
| 2 | `SET STATISTICS IO ON` → `SELECT * FROM Patients WHERE PatientID = 250` | **Clustered Index Seek** — very few logical reads |
| 3 | `SELECT * FROM Patients WHERE PatientID BETWEEN 100 AND 200` | **Clustered Index Seek (range)** — data physically ordered by PatientID |
| 4 | Show execution plan | Annotate: Clustered Index Seek operator |

**Theory link:** Ch.2 — Primary Index is built on the ordering key field of an ordered file. Each block has one index entry (sparse/dense). SQL Server's **Clustered Index** is the practical equivalent: the leaf level IS the data (table rows physically sorted by the key). Only one clustered index per table, just like only one primary index per file.

---

### A2. Secondary Index (Non-Clustered Index) Demo

| Step | Action | What to show |
|------|--------|-------------|
| 1 | Query WITHOUT index: `SELECT * FROM MRIImages WHERE SeriesType = 'T1'` | **Table Scan** — high logical reads |
| 2 | `CREATE NONCLUSTERED INDEX idx_series ON MRIImages(SeriesType)` | Create secondary index |
| 3 | Re-run the same query | **Index Seek + Key Lookup** — low logical reads |
| 4 | Compare `STATISTICS IO` output before/after | Screenshot both |

**Theory link:** Ch.2 — Secondary Index is built on a non-ordering field. Dense index (one entry per record). SQL Server's **Non-Clustered Index** is the equivalent: leaf level contains index key + a bookmark (row locator) back to the clustered index. Multiple non-clustered indexes allowed per table, just like multiple secondary indexes.

---

### A3. Clustering Index Demo

| Step | Action | What to show |
|------|--------|-------------|
| 1 | Show `MRIImages` has no clustered index on `SeriesType` | Non-unique, non-ordering → secondary index |
| 2 | Create a new table or show: when clustered index is on a non-unique column, SQL Server adds a 4-byte uniquifier | Explain difference from textbook's clustering index on non-key field |
| 3 | `SELECT SeriesType, COUNT(*) FROM MRIImages GROUP BY SeriesType` with clustered vs non-clustered | Show scan type difference |

**Theory link:** Ch.2 — Clustering Index is on a non-key ordering field where multiple records can have the same value. SQL Server doesn't have a separate "clustering index" type — it uses the **clustered index** for this. If the clustered key is non-unique, SQL Server internally adds a uniquifier.

---

### A4. Composite (Multi-Column) Index Demo

| Step | Action | What to show |
|------|--------|-------------|
| 1 | `CREATE INDEX idx_patient_slice ON MRIImages(PatientID, SliceNumber)` | Composite index |
| 2 | `SELECT * FROM MRIImages WHERE PatientID = 100 AND SliceNumber = 5` | **Index Seek** — both columns used |
| 3 | `SELECT * FROM MRIImages WHERE SliceNumber = 5` | **Index Scan** (not seek) — leading column not in WHERE |
| 4 | `SELECT PatientID, SliceNumber FROM MRIImages WHERE PatientID = 100` | **Covering index** — no key lookup needed |

**Theory link:** Ch.2 — Multilevel indexes use multiple levels of index entries. SQL Server's B+-Tree is inherently multilevel. Composite indexes demonstrate how the ordering of columns matters (leftmost prefix rule).

---

### A5. B-Tree / B+-Tree Index Structure

| Step | Action | What to show |
|------|--------|-------------|
| 1 | `SELECT * FROM sys.dm_db_index_physical_stats(DB_ID(), OBJECT_ID('MRIImages'), NULL, NULL, 'DETAILED')` | Show index depth, page counts, fragmentation per level |
| 2 | Explain: Root → Intermediate → Leaf levels | Diagram mapping to textbook B+-Tree structure |
| 3 | Show `avg_fragmentation_in_percent` | Explain when/why to rebuild (`ALTER INDEX ... REBUILD`) |
| 4 | `DBCC IND('MRIDatabase', 'MRIImages', 1)` | Show actual page chain of the index |

**Theory link:** Ch.2 — B-Trees and B+-Trees are dynamic multilevel indexes. B+-Tree: all data pointers at leaf level, internal nodes only contain keys. SQL Server uses **B+-Trees** for ALL indexes (clustered and non-clustered). Key difference from textbook: SQL Server's leaf pages are doubly-linked (for range scans), and page splits happen automatically on insert.

---

### A6. DiskANN Vector Index Demo

| Step | Action | What to show |
|------|--------|-------------|
| 1 | Without vector index: `SELECT TOP 5 ... ORDER BY VECTOR_DISTANCE('cosine', Embedding, @query_vec)` | Full scan of all 500×N embeddings — slow |
| 2 | `CREATE VECTOR INDEX idx_mri_embeddings ON MRIImages(Embedding) WITH (DISTANCE_METRIC = 'COSINE')` | Create DiskANN index |
| 3 | Re-run the same vector search | **Approximate Nearest Neighbor** — much faster |
| 4 | Compare execution plans and `STATISTICS TIME` before/after | Annotate: Vector Index Scan operator |

**Theory link:** Ch.2 doesn't cover vector indexes (it's a modern addition). This demonstrates how indexing concepts extend beyond traditional B-Trees. DiskANN is a graph-based ANN index — contrast with textbook's tree-based structures. Trade-off: approximate results (not exact KNN) for dramatically better performance.

---

### A7. Execution Plan Analysis (Query Processing)

| Step | Action | What to show |
|------|--------|-------------|
| 1 | `SET SHOWPLAN_XML ON` or use SSMS "Include Actual Execution Plan" | Enable plan capture |
| 2 | Simple SELECT: `SELECT * FROM Patients WHERE PatientID = 100` | **Clustered Index Seek** — single operator |
| 3 | JOIN query: `SELECT p.*, m.SeriesType FROM Patients p JOIN MRIImages m ON p.PatientID = m.PatientID WHERE p.PatientID = 100` | **Nested Loop Join** (or Hash Match depending on data size) |
| 4 | Aggregation: `SELECT PatientID, COUNT(*) FROM MRIImages GROUP BY PatientID` | **Hash Aggregate** or **Stream Aggregate** |
| 5 | Subquery: `SELECT * FROM Patients WHERE PatientID IN (SELECT DISTINCT PatientID FROM MRIImages WHERE SeriesType = 'T1')` | Show how optimizer transforms subquery |

**Theory link:** Ch.3 §1 — Query processing steps: parsing → optimization → execution. SQL Server's Query Optimizer performs the same logical steps. The execution plan is the visual representation of the chosen algorithm for each operation.

---

### A8. External Sorting Demo

| Step | Action | What to show |
|------|--------|-------------|
| 1 | `SELECT * FROM MRIImages ORDER BY SeriesType` — check plan | **Sort** operator appears if no suitable index |
| 2 | With index on SeriesType: `SELECT * FROM MRIImages ORDER BY SeriesType` | No Sort operator — data already ordered via index |
| 3 | Memory grant info in execution plan | Show `MemoryGrant` in plan XML — SQL Server allocates memory for sort |

**Theory link:** Ch.3 §3 — External sort-merge algorithm: divide file into runs, sort each in memory, merge. SQL Server's Sort operator does the same: if data fits in memory → in-memory quicksort; if not → tempdb spill (external sort). The `Sort Warnings` extended event fires when a spill occurs.

---

### A9. SELECT Algorithms Demo

| Step | Action | What to show |
|------|--------|-------------|
| 1 | No index: `SELECT * FROM MRIImages WHERE SeriesType = 'T2'` | **Table Scan** (linear search — Algorithm S1) |
| 2 | With B-Tree index on SeriesType | **Index Seek** (binary search — Algorithm S3a) |
| 3 | With clustered index range: `WHERE PatientID BETWEEN 1 AND 50` | **Clustered Index Seek** (Algorithm S6 — range on ordering field) |
| 4 | Conjunction: `WHERE SeriesType = 'T1' AND SliceNumber = 5` | Show if optimizer uses index intersection or composite index |

**Theory link:** Ch.3 §4 — SELECT algorithms: S1 (linear search), S2 (binary search), S3 (primary index), S4 (primary index range), S6 (secondary index). SQL Server's optimizer automatically picks the best algorithm based on statistics and cost estimation.

---

### A10. JOIN Algorithms Demo

| Step | Action | What to show |
|------|--------|-------------|
| 1 | Nested Loop: `SELECT * FROM Patients p JOIN MRIImages m ON p.PatientID = m.PatientID` (small outer table) | **Nested Loops** join operator in plan |
| 2 | Hash Join: force with hint or use larger result set | **Hash Match** join operator |
| 3 | Merge Join: both inputs sorted on join key | **Merge Join** operator (if optimizer chooses it) |
| 4 | Compare costs in execution plan | % cost of each operator |

**Theory link:** Ch.3 §4 — Join algorithms: J1 (Nested Loop), J2 (Single-loop with index), J3 (Sort-Merge), J4 (Hash Join). SQL Server implements all of these. The optimizer's cost-based decision maps directly to the textbook's cost formulas (block accesses, buffer size).

---

### A11. Heuristic & Cost-Based Optimization Demo

| Step | Action | What to show |
|------|--------|-------------|
| 1 | Write a complex query with JOIN + WHERE + GROUP BY | Show the execution plan |
| 2 | `SET SHOWPLAN_ALL ON` — show estimated rows, estimated cost | Cost-based optimization output |
| 3 | Compare plan with and without `OPTION (FORCE ORDER)` | Shows optimizer reorders joins for efficiency (heuristic: push selection down) |
| 4 | `UPDATE STATISTICS` on a table → re-run query → compare plan | Statistics drive cost estimation |

**Theory link:** Ch.3 §8–9 — Heuristic optimization: push SELECTs down, push PROJECTs down, reorder joins. Cost-based: use selectivity of predicates and storage cost formulas to pick cheapest plan. SQL Server combines both: heuristic rules for initial plan space pruning, then cost-based search (using cardinality estimates from statistics) to find optimal plan.

---

### A12. Theory vs. Practice — Indexing (Ch.2)

| Aspect | Theory (Textbook Ch.2) | SQL Server Practice |
|--------|----------------------|-------------------|
| **Primary Index** | Ordered file + sparse index on ordering key. One per file. | **Clustered Index**: leaf level = data rows sorted by key. One per table. |
| **Clustering Index** | Index on non-key ordering field (duplicates allowed). | Clustered index on non-unique column → SQL Server adds a 4-byte **uniquifier** internally. |
| **Secondary Index** | Dense index on non-ordering field. Multiple per file. | **Non-Clustered Index**: leaf = key + bookmark (RID or clustered key). Up to 999 per table. |
| **Multilevel Index** | Multiple levels of index to reduce search space. | All SQL Server indexes are B+-Trees = inherently multilevel. `sys.dm_db_index_physical_stats` shows depth. |
| **B-Tree** | Balanced tree, data pointers at all nodes. | SQL Server does NOT use B-Trees — only **B+-Trees**. |
| **B+-Tree** | Data pointers only at leaf level. Internal nodes = keys only. Leaves linked. | Exact implementation: leaf pages doubly-linked for range scans. Internal pages contain keys + child page pointers. Automatic page splits on overflow. |
| **Index storage** | Textbook discusses block factor, fan-out, levels formula: $t = \lceil \log_{fo}(b) \rceil$. | SQL Server: page size = 8KB. Fan-out depends on key size. `sys.dm_db_index_physical_stats` gives exact depth and page counts. |
| **Dynamic updates** | B+-Tree handles inserts/deletes via split/merge. | Same: page splits on insert, ghost records on delete (lazy cleanup). Fragmentation tracked; `ALTER INDEX REBUILD` to defrag. |

---

### A13. Theory vs. Practice — Query Processing (Ch.3)

| Aspect | Theory (Textbook Ch.3) | SQL Server Practice |
|--------|----------------------|-------------------|
| **Query processing steps** | Scanning/Parsing → Optimization → Code Generation → Execution. | Parsing → Algebrizer → Query Optimizer → Execution Engine. Same logical flow. |
| **Relational algebra translation** | SQL → relational algebra tree → optimize tree. | SQL → query tree → logical operators → physical operators → execution plan. |
| **External Sorting** | Sort-merge: create sorted runs in memory, merge passes. Cost = 2b × (1 + ⌈log_M(⌈b/M⌉)⌉). | Sort operator: in-memory quicksort if fits in memory grant; else spills to tempdb (external sort-merge). `Sort Warnings` event on spill. |
| **SELECT algorithms** | S1 (linear), S2 (binary), S3 (primary index), S4 (primary index range), S6 (secondary). | Optimizer picks automatically: Table Scan, Clustered Index Scan/Seek, NonClustered Index Seek + Key Lookup, Index Intersection. |
| **JOIN algorithms** | J1 (Nested Loop), J2 (index-based NL), J3 (Sort-Merge Join), J4 (Hash Join). | All four implemented: **Nested Loops**, **Merge Join**, **Hash Match**. Optimizer picks based on input sizes, sort order, memory. |
| **PROJECT** | Remove duplicates via sorting or hashing. | **Stream Aggregate** (if sorted input) or **Hash Aggregate** (for DISTINCT). |
| **Aggregate operations** | Sorting-based or hashing-based grouping. | **Stream Aggregate** (pre-sorted) or **Hash Match Aggregate**. Handles COUNT, SUM, AVG, etc. |
| **Pipelining** | Pass tuples between operators without materializing. | SQL Server uses **iterator model**: each operator implements `Open()`, `GetNext()`, `Close()`. Rows flow tuple-by-tuple (pipelining by default). Blocking operators (Sort, Hash) must materialize. |
| **Heuristic optimization** | Push selections down, push projections down, reorder joins by selectivity. | Optimizer applies transformation rules: predicate pushdown, join reordering, subquery unnesting, view merging. |
| **Cost-based optimization** | Use selectivity, block accesses, buffer size to estimate cost of each plan. | Statistics (histograms, density vectors) on columns → **Cardinality Estimator** → cost formula per operator → search cheapest plan. `OPTION (RECOMPILE)` forces fresh optimization. |
| **Selectivity** | $sl = 1/NDV$ for equality on key with NDV distinct values. | SQL Server uses multi-step histograms (up to 200 steps) + density vectors for selectivity estimates. `DBCC SHOW_STATISTICS` shows the histogram. |
| **Oracle-specific (Ch.3 §10)** | Rule-based vs. cost-based optimizer in Oracle. | SQL Server has always been **cost-based only** (no rule-based mode). The equivalent of Oracle hints: SQL Server **query hints** (`OPTION`, `WITH (INDEX(...))`, `FORCESEEK`). |

---

**Summary for presentation:**
- SQL Server indexes are ALL **B+-Trees** (not B-Trees) — covers primary, clustering, and secondary index concepts from Ch.2
- The Query Optimizer implements all major algorithms from Ch.3 (NL Join, Merge Join, Hash Join, external sort)
- SQL Server is purely **cost-based** optimization (no rule-based mode)
- **Iterator/pipelining model** used by default — matches textbook's pipelining concept
- Vector indexing (DiskANN) extends beyond textbook into modern approximate search

---

## Transactions

**Deliverables:** `sql/04_transactions.sql`

### B1. Basic Transaction — COMMIT (ACID: Atomicity + Durability)

| Step | Action | What to show |
|------|--------|-------------|
| 1 | Verify test patient does NOT exist: `SELECT COUNT(*) FROM Patients WHERE PatientID = 9999` | 0 rows — clean starting state |
| 2 | `BEGIN TRANSACTION` → `INSERT INTO Patients (9999, ...)` → `INSERT INTO MRIImages (9999, ...)` | Two writes inside one transaction |
| 3 | Inside transaction: `PRINT XACT_STATE()` | Returns **1** — transaction is in ACTIVE state (committable) |
| 4 | `COMMIT TRANSACTION` | Transaction moves to COMMITTED state |
| 5 | `SELECT ... FROM Patients WHERE PatientID = 9999` + `SELECT ... FROM MRIImages WHERE PatientID = 9999` | Both rows persist — **Durability** proven |

**Theory link (Transaction & System Concepts):** Ch.4 — "A Transaction is a logical unit of database processing that includes one or more access operations (read, write, delete)." Transaction boundaries are marked by `begin_transaction` and `end_transaction`. SQL Server's `BEGIN TRAN` / `COMMIT` maps directly to these boundaries. The **ACID** property of **Durability** guarantees that once committed, changes survive any failure — SQL Server enforces this via Write-Ahead Logging (WAL), flushing log records to disk before the COMMIT returns.

---

### B2. ROLLBACK — Proving Atomicity (All-or-Nothing)

| Step | Action | What to show |
|------|--------|-------------|
| 1 | `SELECT COUNT(*) FROM Patients` + `SELECT COUNT(*) FROM MRIImages` | Record baseline counts |
| 2 | `BEGIN TRANSACTION` → `INSERT INTO Patients (8888, ...)` → `INSERT INTO MRIImages (8888, ...)` | Two writes in one transaction |
| 3 | Inside transaction: `SELECT COUNT(*) FROM Patients WHERE PatientID = 8888` | Returns 1 — row visible inside ACTIVE transaction |
| 4 | `ROLLBACK TRANSACTION` | Transaction moves ACTIVE → FAILED → TERMINATED |
| 5 | `SELECT COUNT(*) FROM Patients WHERE PatientID = 8888` | Returns **0** — both inserts undone |
| 6 | `SELECT COUNT(*) FROM MRIImages WHERE PatientID = 8888` | Returns **0** — zero partial records (Atomicity) |

**Theory link (Desirable Properties — Atomicity):** Ch.4 — "rollback (or abort): signals that the transaction has ended unsuccessfully, so that any changes or effects that the transaction may have applied to the database must be undone." The **Atomicity** property mandates all-or-nothing execution. SQL Server traces backward through the transaction log to undo writes. This is the same mechanism used by `ingest.py` — on error, per-patient ROLLBACK ensures no "partial patient" records (metadata without images).

---

### B3. SAVEPOINT — Partial Rollback

| Step | Action | What to show |
|------|--------|-------------|
| 1 | `BEGIN TRANSACTION` → `INSERT INTO Patients (7777, ...)` | Phase 1: insert patient (we want to KEEP this) |
| 2 | `SAVE TRANSACTION SP_AfterPatient` | Create savepoint after patient insert |
| 3 | `INSERT INTO MRIImages (7777, ..., slice 1)` → `INSERT INTO MRIImages (7777, ..., slice 2)` | Phase 2: insert images (we will UNDO this) |
| 4 | `ROLLBACK TRANSACTION SP_AfterPatient` | Partial rollback — undo images only |
| 5 | Inside transaction: verify patient exists (1) and images don't (0) | Partial undo confirmed |
| 6 | `COMMIT TRANSACTION` | Outer transaction commits successfully |
| 7 | `SELECT ... FROM Patients WHERE PatientID = 7777` → exists; `SELECT COUNT(*) FROM MRIImages WHERE PatientID = 7777` → 0 | Patient persists, images rolled back |

**Theory link (Transaction & System Concepts):** Ch.4 — "undo: Similar to rollback except that it applies to a single operation rather than to a whole transaction." Savepoints implement partial undo within a transaction. Use case: insert patient metadata, then attempt image batch; if image batch fails, keep the patient but discard images. SQL Server's `SAVE TRANSACTION <name>` + `ROLLBACK TRANSACTION <name>` is the practical implementation of per-operation undo.

---

### B4. TRY/CATCH Error Handling with XACT_STATE()

| Step | Action | What to show |
|------|--------|-------------|
| 1 | `SET XACT_ABORT ON` | Any runtime error automatically makes the transaction uncommittable |
| 2 | `BEGIN TRY` → `BEGIN TRANSACTION` → insert patient 6666 (success) → insert patient 9999 (duplicate PK → error!) | PK violation triggers the CATCH block |
| 3 | In CATCH: `PRINT ERROR_MESSAGE()` + `PRINT XACT_STATE()` | Error message shown; `XACT_STATE()` returns **-1** (uncommittable = FAILED state) |
| 4 | `IF XACT_STATE() = -1` → `ROLLBACK TRANSACTION` | Must rollback — transaction is doomed |
| 5 | `SELECT COUNT(*) FROM Patients WHERE PatientID = 6666` → 0 | Whole transaction rolled back — patient 6666 also undone (Atomicity) |

**Theory link (Transaction States & System Concepts):** Ch.4 — Why recovery is needed: transaction/system errors (division by zero, overflow), local exception conditions, concurrency control enforcement (deadlock). The **Transaction State Diagram**: ACTIVE → PARTIALLY COMMITTED → COMMITTED (success path) or ACTIVE → FAILED → TERMINATED (failure path). SQL Server's `XACT_STATE()` maps directly: `1` = committable (≈ Active/Partially Committed), `-1` = uncommittable (≈ Failed, must ROLLBACK), `0` = no transaction (≈ Terminated).

---

### B5. Implicit vs Explicit Transactions (Transaction Support in SQL)

| Step | Action | What to show |
|------|--------|-------------|
| 1 | **Autocommit mode** (default): `PRINT XACT_STATE()` | Returns 0 — no active transaction; each statement auto-commits |
| 2 | `SET IMPLICIT_TRANSACTIONS ON` → `INSERT INTO Patients (5555, ...)` | SQL Server auto-begins a transaction on DML |
| 3 | `PRINT XACT_STATE()` + `PRINT @@TRANCOUNT` | Returns 1, 1 — transaction is active (user must commit/rollback manually) |
| 4 | `ROLLBACK` → `SET IMPLICIT_TRANSACTIONS OFF` | Clean up implicit mode |
| 5 | **Explicit mode**: `BEGIN TRANSACTION` → `PRINT @@TRANCOUNT` → `ROLLBACK` | Most common in application code (e.g., `ingest.py`) |

**Theory link (Transaction Support in SQL):** Ch.4 — "With SQL, there is no explicit Begin Transaction statement. Transaction initiation is done implicitly when particular SQL statements are encountered." + "Every transaction must have an explicit end statement, which is either a COMMIT or ROLLBACK." SQL Server offers three modes: (1) **Autocommit** (default — each statement is its own transaction), (2) **Implicit** (`SET IMPLICIT_TRANSACTIONS ON` — matches the SQL2 standard behavior: auto-begin on DML, but must manually COMMIT/ROLLBACK), (3) **Explicit** (`BEGIN TRAN ... COMMIT` — SQL Server's extension beyond the SQL standard, and the recommended approach for application code).

---

### B6. Transaction Log Inspection — WAL in Practice

| Step | Action | What to show |
|------|--------|-------------|
| 1 | `CHECKPOINT` | Flush dirty pages — clean starting point for log inspection |
| 2 | `BEGIN TRANSACTION` → `INSERT INTO Patients (4444, ...)` → `COMMIT TRANSACTION` | Perform a traceable transaction |
| 3 | Query `sys.fn_dblog(NULL, NULL)` — show `[Current LSN]`, `[Transaction ID]`, `[Operation]`, `[AllocUnitName]` | Raw transaction log records visible |
| 4 | Map log operations to theory: `LOP_BEGIN_XACT` → `[start_transaction, T]`, `LOP_INSERT_ROWS` → `[write_item, T, X, _, new]`, `LOP_COMMIT_XACT` → `[commit, T]`, `LOP_ABORT_XACT` → `[abort, T]` | Theory-to-practice mapping of log record types |
| 5 | Show transaction lifecycle in log ordered by LSN | Full traceability of a transaction's log footprint |

**Theory link (Transaction & System Concepts — System Log):** Ch.4 — "The log keeps track of all transaction operations that affect the values of database items." Log record types: `[start_transaction, T]`, `[write_item, T, X, old_value, new_value]`, `[read_item, T, X]`, `[commit, T]`, `[abort, T]`. "The log is kept on disk → not affected by any type of failure except for disk or catastrophic failure." Recovery principle: "undo the effect by tracing backward through the log" and "redo the effect by tracing forward through the log." SQL Server implements WAL via the `.ldf` file and uses an **ARIES-based** recovery algorithm: Phase 1 (Analysis) → Phase 2 (Redo) → Phase 3 (Undo) on crash restart.

---

### B7. Transaction States — XACT_STATE() Mapping to Theory

| Step | Action | What to show |
|------|--------|-------------|
| 1 | Before any transaction: `PRINT @@TRANCOUNT` + `PRINT XACT_STATE()` | `0`, `0` — **No transaction** (≈ Terminated or never started) |
| 2 | `BEGIN TRANSACTION` → `PRINT @@TRANCOUNT` + `PRINT XACT_STATE()` | `1`, `1` — **ACTIVE** state (committable) |
| 3 | `COMMIT` | Transition: ACTIVE → PARTIALLY COMMITTED → COMMITTED → TERMINATED |
| 4 | `SET XACT_ABORT ON` → `BEGIN TRY` → `BEGIN TRANSACTION` → `SELECT 1/0` (force error) | Division by zero triggers CATCH |
| 5 | In CATCH: `PRINT XACT_STATE()` → `-1` | **FAILED** state (uncommittable — must ROLLBACK) |
| 6 | `ROLLBACK` → `PRINT XACT_STATE()` → `0` | Back to **TERMINATED** state |

**Theory link (Transaction States):** Ch.4 — State diagram: `BEGIN TRANSACTION` → ACTIVE ←(READ, WRITE); ACTIVE → `END TRANSACTION` → PARTIALLY COMMITTED → `COMMIT` → COMMITTED → TERMINATED. Failure path: ACTIVE (or PARTIALLY COMMITTED) → `ABORT` → FAILED → TERMINATED. SQL Server's `XACT_STATE()` provides a runtime query of this state machine: `0` = no transaction (Terminated), `1` = committable (Active / Partially Committed), `-1` = doomed (Failed). `@@TRANCOUNT` tracks nesting depth for nested transactions.

---

### B8. Isolation Levels and Read Phenomena

| Step | Action | What to show |
|------|--------|-------------|
| 1 | `DBCC USEROPTIONS` | Show current session isolation level (default: READ COMMITTED) |
| 2 | `SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED` → `SELECT ... WHERE PatientID = 9999` | Allows dirty reads (no S locks acquired) |
| 3 | `SET TRANSACTION ISOLATION LEVEL READ COMMITTED` → same `SELECT` | Default level — blocks if row has uncommitted X lock |
| 4 | `SET TRANSACTION ISOLATION LEVEL REPEATABLE READ` → `BEGIN TRAN` → two identical `SELECT`s → `COMMIT` | Both reads guaranteed identical — S locks held until COMMIT |
| 5 | `SET TRANSACTION ISOLATION LEVEL SERIALIZABLE` → `BEGIN TRAN` → `SELECT COUNT(*) WHERE PatientID BETWEEN 9000 AND 9999` → `COMMIT` | Range lock prevents phantom inserts in [9000, 9999] |
| 6 | Reset: `SET TRANSACTION ISOLATION LEVEL READ COMMITTED` | Restore default |

**Anomaly prevention matrix (Schedules & Recoverability):**

| Isolation Level | Dirty Read | Non-Repeatable Read | Phantom Read |
|-----------------|-----------|-------------------|-------------|
| READ UNCOMMITTED | Allowed | Allowed | Allowed |
| READ COMMITTED | Prevented | Allowed | Allowed |
| REPEATABLE READ | Prevented | Prevented | Allowed |
| SERIALIZABLE | Prevented | Prevented | Prevented |
| SNAPSHOT (SQL Server) | Prevented | Prevented | Prevented |

**Theory link (Characterizing Schedules — Recoverability & Transaction Support in SQL):** Ch.4 — SQL2 defines four isolation levels that progressively prevent more concurrency anomalies. **Dirty Read**: reading uncommitted data from a failed transaction violates Isolation. **Non-repeatable Read**: same query returns different values within one transaction. **Phantom Read**: new rows appear in a range query within one transaction. A **recoverable schedule** requires that if T₂ reads a value written by T₁, then T₁ must commit before T₂ commits. SQL Server enforces this via its lock-based protocol: READ COMMITTED prevents dirty reads (recoverable), SERIALIZABLE prevents all anomalies (strict schedules). **SNAPSHOT** (SQL Server extension) uses MVCC row versioning to prevent all three anomalies without blocking.

---

### B9. Theory vs. Practice — Transaction Processing (Ch.4)

| Aspect | Theory (Textbook Ch.4) | SQL Server Practice |
|--------|----------------------|-------------------|
| **Transaction Definition** | Logical unit of DB processing with read/write ops, bounded by `begin_transaction` / `end_transaction`. | `BEGIN TRAN` ... `COMMIT` / `ROLLBACK`. Each SQL statement is also atomic on its own (autocommit). |
| **ACID — Atomicity** | All operations execute or none do. | `ROLLBACK` undoes all; `XACT_ABORT` + `TRY`/`CATCH` enforces. Demo B2 proved zero partial records. |
| **ACID — Consistency** | Transaction takes DB from one consistent state to another. | PK / FK / CHECK constraints enforced at statement level. `FK_Patient` prevents orphan images. |
| **ACID — Isolation** | Transaction appears to execute in isolation from others. | 5 isolation levels (READ UNCOMMITTED → SNAPSHOT). Default: READ COMMITTED. |
| **ACID — Durability** | Committed changes must never be lost. | WAL ensures log records written to disk BEFORE commit returns. `.ldf` file on persistent storage. |
| **Transaction States** | Active → Partially Committed → Committed, or Active/PartCommit → Failed → Terminated. | `XACT_STATE()`: `1` = committable, `-1` = uncommittable (failed), `0` = no transaction. Demo B7. |
| **System Log** | `[start_transaction, T]`, `[write_item, T, X, old, new]`, `[commit, T]`, `[abort, T]`. | `sys.fn_dblog()`: `LOP_BEGIN_XACT`, `LOP_MODIFY_ROW`, `LOP_COMMIT_XACT`, `LOP_ABORT_XACT`. Demo B6. |
| **Recovery (Undo/Redo)** | Undo: trace backward, restore old values. Redo: trace forward, apply new values. | ARIES-based recovery: Analysis → Redo → Undo phases on crash restart. Automatic. |
| **Schedules & Serializability** | Serial schedule: all ops of T consecutive. Serializable: equivalent to some serial schedule. | SQL Server uses **Strict 2PL** (locks held until commit) to guarantee serializability at SERIALIZABLE level. |
| **Conflict Serializability** | Two operations conflict if: different transactions, same data item, at least one is a write. A schedule is conflict-serializable if its precedence graph is acyclic. | Lock compatibility matrix: S-S compatible, S-X conflict, X-X conflict. `sys.dm_tran_locks` shows lock state. Strict 2PL guarantees conflict-serializable schedules. |
| **Recoverable Schedules** | If T₂ reads a value written by T₁, T₁ must commit before T₂ commits. Cascading rollback: abort of T₁ forces abort of T₂. | READ COMMITTED (default) prevents dirty reads → guarantees recoverability. Strict 2PL holds write locks until commit → prevents cascading rollbacks (ACA). |
| **Isolation Levels (SQL2)** | READ UNCOMMITTED, READ COMMITTED, REPEATABLE READ, SERIALIZABLE. | Same 4 levels + SNAPSHOT (MVCC via row versioning in tempdb). `SET TRANSACTION ISOLATION LEVEL`. |
| **Dirty / Non-Repeatable / Phantom** | Violation table: each level prevents progressively more anomalies. | Same behavior in SQL Server. SNAPSHOT additionally prevents all 3 via row versioning without blocking. |
| **Savepoint / Partial Undo** | "undo applies to single operation rather than whole transaction." | `SAVE TRANSACTION <name>` + `ROLLBACK TRANSACTION <name>`. Demo B3. |
| **Implicit vs Explicit** | SQL2: no explicit `BEGIN`, transactions start implicitly. | SQL Server default: AUTOCOMMIT. `SET IMPLICIT_TRANSACTIONS ON` matches SQL2 behavior. Demo B5. |

---

**Summary for presentation:**
- SQL Server transactions implement the full **ACID** property set from Ch.4
- **Transaction states** (Active → Committed/Failed → Terminated) map directly to `XACT_STATE()` values (1, -1, 0)
- The **system log** (`sys.fn_dblog()`) is the practical implementation of the textbook's WAL protocol, with log operation types mapping 1:1 to theory
- **Conflict serializability** is guaranteed at SERIALIZABLE isolation via Strict 2PL; lower levels trade safety for concurrency
- **Recoverable schedules** are ensured by default (READ COMMITTED prevents dirty reads); cascadeless schedules come from holding write locks until commit
- SQL Server extends the SQL2 standard with **SNAPSHOT isolation** (MVCC) and **explicit BEGIN TRAN** syntax
- **Savepoints** provide the textbook's partial undo capability for fine-grained error recovery

---

## Concurrency Control 

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

## Report + Presentation (2 points)

**Deliverables:** Final report (PDF), presentation slides

| Task | Detail |
|------|--------|
| D1. Report structure | Title, Abstract, Introduction, Architecture, Methodology (per criterion), Results (screenshots + analysis), Theory vs. Practice comparison table, Conclusion. |
| D2. Collect demo outputs | Gather screenshots/outputs from A, B, C: execution plans, STATISTICS IO, lock DMVs, deadlock graphs, transaction logs. |
| D3. Theory vs. Practice table | For each of the 4 criteria, create a two-column comparison: "Textbook concept" vs. "SQL Server 2025 implementation". |
| D4. Presentation slides | ~15–20 slides for 30-min presentation. Architecture diagram, live demo flow, key findings, Q&A preparation. |
| D5. Q&A prep | Prepare answers for likely questions: Why SQL Server 2025? Why VECTOR type over application-side search? How does DiskANN compare to brute-force KNN? What isolation level would you use in production? |


## Files To Be Created

| File | Owner | Status |
|------|-------|--------|
| `sql/02_indexes.sql` | Member A | **Created** |
| `sql/03_query_processing.sql` | Member A | **Created** |
| `sql/04_transactions.sql` | Member B | Not started |
| `sql/05_concurrency.sql` | Member C | **Created** |
| `src/app_queries.py` | Member A | Not started |
| Report (PDF) | Member D | Not started |
| Slides | Member D | Not started |
