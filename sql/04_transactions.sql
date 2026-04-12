/*=============================================================================
  04_transactions.sql — Transaction Processing Demos for MRI DBMS Project
  SQL Server 2025 | MRIDatabase
  
  Purpose: Demonstrate transaction concepts and compare textbook theory 
           (Elmasri Ch.4) with SQL Server implementation in practice.
  
  Structure:
    DEMO 1: Basic Transaction — COMMIT (ACID Atomicity + Durability)
    DEMO 2: ROLLBACK — Proving Atomicity (all-or-nothing)
    DEMO 3: SAVEPOINT — Partial Rollback
    DEMO 4: TRY/CATCH Error Handling with XACT_STATE()
    DEMO 5: Implicit vs Explicit Transactions
    DEMO 6: Transaction Log Inspection — sys.fn_dblog() (WAL in practice)
    DEMO 7: Transaction States — XACT_STATE() mapping to theory
    DEMO 8: Isolation Levels — Dirty Read / Nonrepeatable Read / Phantom
    DEMO 9: Theory vs Practice Comparison (comments + queries)
=============================================================================*/

USE MRIDatabase;
GO

/*=============================================================================
  DEMO 1: Basic Transaction — COMMIT
  
  THEORY (Elmasri Ch.4, Slide 4):
    "A Transaction is a logical unit of database processing that includes 
     one or more access operations (read, write, delete)."
    "Transaction boundaries: Begin and End transaction."
  
  THEORY (Slide 27 — ACID):
    Atomicity:    performed in entirety or not at all
    Consistency:  takes DB from one consistent state to another
    Isolation:    appears as if executing in isolation
    Durability:   once committed, changes must never be lost
  
  SQL SERVER PRACTICE:
    - BEGIN TRAN marks the start (≈ begin_transaction)
    - COMMIT marks successful end (≈ commit_transaction)
    - SQL Server uses Write-Ahead Logging (WAL) to guarantee durability
    - FK constraint (FK_Patient) enforces consistency automatically
=============================================================================*/

PRINT '========== DEMO 1: Basic Transaction — COMMIT ==========';

-- Step 1: Verify that test patient does NOT exist
SELECT COUNT(*) AS PatientExists FROM Patients WHERE PatientID = 9999;

-- Step 2: Begin transaction, insert patient + image, commit
BEGIN TRANSACTION;

    INSERT INTO Patients (PatientID, ClinicalNotes)
    VALUES (9999, N'Demo transaction: disc herniation at L4-L5');

    INSERT INTO MRIImages (PatientID, SeriesType, SliceNumber, ImageData)
    VALUES (9999, N't2_tse_sag', 1, 0x00);

    -- At this point: transaction is in ACTIVE state (theory: Slide 17)
    PRINT 'XACT_STATE inside transaction: ' + CAST(XACT_STATE() AS VARCHAR);

COMMIT TRANSACTION;
-- Now: transaction has reached COMMITTED state

-- Step 3: Verify data persists (Durability)
SELECT 'Patient' AS RecordType, PatientID, ClinicalNotes 
FROM Patients WHERE PatientID = 9999;

SELECT 'Image' AS RecordType, ImageID, PatientID, SeriesType, SliceNumber 
FROM MRIImages WHERE PatientID = 9999;

PRINT 'DEMO 1 COMPLETE: Transaction committed. Both rows persist (Atomicity + Durability).';
GO


/*=============================================================================
  DEMO 2: ROLLBACK — Proving Atomicity
  
  THEORY (Elmasri Ch.4, Slide 20):
    "rollback (or abort): signals that the transaction has ended 
     unsuccessfully, so that any changes or effects that the transaction 
     may have applied to the database must be undone."
  
  THEORY (Slide 17):
    Transaction states: ACTIVE → FAILED → TERMINATED
    When ABORT occurs from Active or Partially Committed state → FAILED
  
  SQL SERVER PRACTICE:
    - ROLLBACK undoes ALL operations within the transaction
    - SQL Server traces backward through the log to undo writes
    - The per-patient commit in ingest.py uses this: on error → rollback
      ensures no "partial patient" records (metadata without images)
=============================================================================*/

PRINT '========== DEMO 2: ROLLBACK — Proving Atomicity ==========';

-- Step 1: Check current state
SELECT COUNT(*) AS PatientsBefore FROM Patients;
SELECT COUNT(*) AS ImagesBefore FROM MRIImages;

-- Step 2: Begin transaction, insert, then ROLLBACK
BEGIN TRANSACTION;

    INSERT INTO Patients (PatientID, ClinicalNotes)
    VALUES (8888, N'This patient should NOT exist after rollback');

    INSERT INTO MRIImages (PatientID, SeriesType, SliceNumber, ImageData)
    VALUES (8888, N't1_tse_sag', 1, 0x00);

    -- Verify rows exist INSIDE the transaction (Active state)
    SELECT 'INSIDE TRAN' AS Context, COUNT(*) AS Patient8888Exists 
    FROM Patients WHERE PatientID = 8888;

ROLLBACK TRANSACTION;
-- Transaction is now in TERMINATED state via FAILED path

-- Step 3: Verify NOTHING persists — Atomicity proven
SELECT 'AFTER ROLLBACK' AS Context, COUNT(*) AS Patient8888Exists 
FROM Patients WHERE PatientID = 8888;

SELECT 'AFTER ROLLBACK' AS Context, COUNT(*) AS Image8888Exists 
FROM MRIImages WHERE PatientID = 8888;

PRINT 'DEMO 2 COMPLETE: Rollback undid ALL operations. Zero partial records (Atomicity).';
GO


/*=============================================================================
  DEMO 3: SAVEPOINT — Partial Rollback
  
  THEORY (Elmasri Ch.4, Slide 21):
    "undo: Similar to rollback except that it applies to a single operation 
     rather than to a whole transaction."
  
  SQL SERVER PRACTICE:
    - SAVE TRANSACTION <name> creates a savepoint
    - ROLLBACK TRANSACTION <name> rolls back to that savepoint only
    - The outer transaction can still COMMIT
    - Use case: insert patient metadata, then attempt image batch; 
      if image batch fails, keep the patient but discard images
=============================================================================*/

PRINT '========== DEMO 3: SAVEPOINT — Partial Rollback ==========';

BEGIN TRANSACTION;

    -- Phase 1: Insert patient (we want to KEEP this)
    INSERT INTO Patients (PatientID, ClinicalNotes)
    VALUES (7777, N'Savepoint demo: patient should survive');

    -- Create savepoint AFTER patient insert
    SAVE TRANSACTION SP_AfterPatient;

    -- Phase 2: Insert images (we will UNDO this)
    INSERT INTO MRIImages (PatientID, SeriesType, SliceNumber, ImageData)
    VALUES (7777, N't2_tse_sag', 1, 0x00);

    INSERT INTO MRIImages (PatientID, SeriesType, SliceNumber, ImageData)
    VALUES (7777, N't2_tse_sag', 2, 0x00);

    -- Simulate: something went wrong with images → rollback to savepoint
    ROLLBACK TRANSACTION SP_AfterPatient;

    -- Patient still exists inside the transaction, images do not
    SELECT 'After partial rollback' AS Context,
        (SELECT COUNT(*) FROM Patients WHERE PatientID = 7777) AS PatientExists,
        (SELECT COUNT(*) FROM MRIImages WHERE PatientID = 7777) AS ImagesExist;

COMMIT TRANSACTION;

-- Verify final state
SELECT 'FINAL' AS Context, PatientID, ClinicalNotes 
FROM Patients WHERE PatientID = 7777;

SELECT 'FINAL' AS Context, COUNT(*) AS ImageCount 
FROM MRIImages WHERE PatientID = 7777;

PRINT 'DEMO 3 COMPLETE: Patient persists, images rolled back. Partial undo achieved.';
GO


/*=============================================================================
  DEMO 4: TRY/CATCH Error Handling with XACT_STATE()
  
  THEORY (Elmasri Ch.4, Slides 14-16):
    Why recovery is needed:
    - Transaction or system error (division by zero, overflow)
    - Local errors or exception conditions
    - Concurrency control enforcement (deadlock)
  
  THEORY (Slide 17 — Transaction States):
    ACTIVE → PARTIALLY COMMITTED → COMMITTED   (success path)
    ACTIVE → FAILED → TERMINATED               (failure path)
    PARTIALLY COMMITTED → FAILED → TERMINATED   (failure at commit)
  
  SQL SERVER PRACTICE:
    - TRY/CATCH blocks catch errors during transaction execution
    - XACT_STATE() maps directly to theory states:
        1  = committable  (≈ Partially Committed, can go to Committed)
       -1  = uncommittable (≈ Failed, must ROLLBACK)
        0  = no active transaction (≈ Terminated)
    - SET XACT_ABORT ON: any error automatically makes tran uncommittable
=============================================================================*/

PRINT '========== DEMO 4: TRY/CATCH with XACT_STATE() ==========';

-- Scenario: Try to insert a duplicate PatientID (violates PK)
SET XACT_ABORT ON;
BEGIN TRY
    BEGIN TRANSACTION;

        -- This should succeed (patient 9999 already exists from Demo 1)
        INSERT INTO Patients (PatientID, ClinicalNotes)
        VALUES (6666, N'TRY/CATCH demo patient');

        -- This will FAIL: duplicate PK violation (9999 already exists)
        INSERT INTO Patients (PatientID, ClinicalNotes)
        VALUES (9999, N'Duplicate! This will cause an error');

    COMMIT TRANSACTION;
    PRINT 'Transaction committed successfully.';

END TRY
BEGIN CATCH
    PRINT 'ERROR caught: ' + ERROR_MESSAGE();
    PRINT 'XACT_STATE() = ' + CAST(XACT_STATE() AS VARCHAR);
    PRINT 'Error Number  = ' + CAST(ERROR_NUMBER() AS VARCHAR);
    PRINT 'Error Line    = ' + CAST(ERROR_LINE() AS VARCHAR);

    IF XACT_STATE() = -1
    BEGIN
        -- Transaction is uncommittable (≈ FAILED state in theory)
        ROLLBACK TRANSACTION;
        PRINT 'Transaction rolled back (FAILED → TERMINATED).';
    END
    ELSE IF XACT_STATE() = 1
    BEGIN
        -- Transaction is still committable
        COMMIT TRANSACTION;
        PRINT 'Transaction committed despite error (partial success).';
    END
END CATCH;
SET XACT_ABORT OFF;

-- Verify: patient 6666 should NOT exist (whole transaction rolled back)
SELECT 'After TRY/CATCH' AS Context, COUNT(*) AS Patient6666Exists 
FROM Patients WHERE PatientID = 6666;

PRINT 'DEMO 4 COMPLETE: Error handling with XACT_STATE() demonstrated.';
GO


/*=============================================================================
  DEMO 5: Implicit vs Explicit Transactions
  
  THEORY (Elmasri Ch.4, Slide 59):
    "With SQL, there is no explicit Begin Transaction statement. 
     Transaction initiation is done implicitly when particular SQL 
     statements are encountered."
    "Every transaction must have an explicit end statement, which is 
     either a COMMIT or ROLLBACK."
  
  SQL SERVER PRACTICE:
    - Default: AUTOCOMMIT mode — each statement is its own transaction
    - SET IMPLICIT_TRANSACTIONS ON: SQL Server auto-begins a transaction 
      when DML is encountered, but you must manually COMMIT/ROLLBACK
    - Explicit: BEGIN TRAN ... COMMIT (most common in application code)
    
  COMPARISON:
    SQL Standard (SQL2) says no explicit BEGIN — SQL Server ADDS it.
    The theory's begin_transaction maps to SQL Server's BEGIN TRAN.
=============================================================================*/

PRINT '========== DEMO 5: Implicit vs Explicit Transactions ==========';

-- Part A: AUTOCOMMIT mode (default)
-- Each statement auto-commits. No explicit BEGIN TRAN needed.
PRINT '--- Part A: Autocommit Mode ---';
PRINT 'XACT_STATE before any DML: ' + CAST(XACT_STATE() AS VARCHAR);
-- (Should be 0 — no active transaction)

-- Part B: IMPLICIT_TRANSACTIONS mode
PRINT '--- Part B: Implicit Transactions Mode ---';
SET IMPLICIT_TRANSACTIONS ON;

-- This INSERT auto-begins a transaction
INSERT INTO Patients (PatientID, ClinicalNotes)
VALUES (5555, N'Implicit transaction demo');

-- Transaction is now active automatically!
PRINT 'XACT_STATE after INSERT (implicit): ' + CAST(XACT_STATE() AS VARCHAR);
PRINT '@@TRANCOUNT: ' + CAST(@@TRANCOUNT AS VARCHAR);

-- Must explicitly commit or rollback
ROLLBACK;
PRINT 'Rolled back implicit transaction.';

SET IMPLICIT_TRANSACTIONS OFF;

-- Part C: Explicit mode (recommended for applications like ingest.py)
PRINT '--- Part C: Explicit Transaction (Best Practice) ---';
BEGIN TRANSACTION;
    PRINT '@@TRANCOUNT after BEGIN TRAN: ' + CAST(@@TRANCOUNT AS VARCHAR);
    -- Application logic here...
ROLLBACK;
PRINT '@@TRANCOUNT after ROLLBACK: ' + CAST(@@TRANCOUNT AS VARCHAR);

PRINT 'DEMO 5 COMPLETE: Three transaction modes demonstrated.';
GO


/*=============================================================================
  DEMO 6: Transaction Log Inspection — WAL in Practice
  
  THEORY (Elmasri Ch.4, Slides 22-25):
    "The log keeps track of all transaction operations that affect 
     the values of database items."
    Log record types:
      [start_transaction, T]
      [write_item, T, X, old_value, new_value]
      [read_item, T, X]
      [commit, T]
      [abort, T]
    "The log is kept on disk → not affected by any type of failure 
     except for disk or catastrophic failure."
  
  THEORY (Slide 25 — Recovery using log records):
    "undo the effect by tracing backward through the log"
    "redo the effect by tracing forward through the log"
  
  SQL SERVER PRACTICE:
    - Transaction log (.ldf file) implements WAL
    - sys.fn_dblog(NULL, NULL) reads the active log
    - Log operations map to theory:
        LOP_BEGIN_XACT     → [start_transaction, T]
        LOP_MODIFY_ROW     → [write_item, T, X, old, new]
        LOP_COMMIT_XACT    → [commit, T]
        LOP_ABORT_XACT     → [abort, T]
    - SQL Server crash recovery uses ARIES algorithm:
        Phase 1: Analysis (scan log to find active transactions)
        Phase 2: Redo     (replay committed ops not yet on disk)
        Phase 3: Undo     (rollback uncommitted transactions)
=============================================================================*/

PRINT '========== DEMO 6: Transaction Log — WAL in Practice ==========';

-- Step 1: Insert a checkpoint to have a clean starting point
CHECKPOINT;

-- Step 2: Perform a transaction that we can trace in the log
BEGIN TRANSACTION;

    INSERT INTO Patients (PatientID, ClinicalNotes)
    VALUES (4444, N'WAL demo: this write is logged before data page flush');

COMMIT TRANSACTION;

-- Step 3: Read the transaction log to see the log records
-- Theory mapping: each row here corresponds to a log record type
SELECT TOP 20
    [Current LSN],
    [Transaction ID],
    [Operation],           -- Maps to theory: LOP_BEGIN_XACT, LOP_MODIFY_ROW, etc.
    [Context],
    [Transaction Name],
    [Description],
    [AllocUnitName]        -- Shows which table was affected
FROM sys.fn_dblog(NULL, NULL)
WHERE [Transaction Name] IS NOT NULL 
   OR [AllocUnitName] LIKE '%Patient%'
ORDER BY [Current LSN] DESC;

-- Step 4: Show a more focused view — just the transaction lifecycle
PRINT 'Transaction lifecycle in the log (theory → practice mapping):';
SELECT 
    [Current LSN],
    [Operation],
    CASE [Operation]
        WHEN 'LOP_BEGIN_XACT'   THEN '→ Theory: [start_transaction, T]'
        WHEN 'LOP_COMMIT_XACT'  THEN '→ Theory: [commit, T]'
        WHEN 'LOP_ABORT_XACT'   THEN '→ Theory: [abort, T]'
        WHEN 'LOP_MODIFY_ROW'   THEN '→ Theory: [write_item, T, X, old, new]'
        WHEN 'LOP_INSERT_ROWS'  THEN '→ Theory: [write_item, T, X, _, new]'
        WHEN 'LOP_DELETE_ROWS'  THEN '→ Theory: [write_item, T, X, old, _]'
        ELSE '→ Internal operation'
    END AS TheoryMapping,
    [Transaction Name],
    [AllocUnitName]
FROM sys.fn_dblog(NULL, NULL)
WHERE [Operation] IN (
    'LOP_BEGIN_XACT', 'LOP_COMMIT_XACT', 'LOP_ABORT_XACT',
    'LOP_MODIFY_ROW', 'LOP_INSERT_ROWS', 'LOP_DELETE_ROWS'
)
ORDER BY [Current LSN] DESC;

PRINT 'DEMO 6 COMPLETE: Transaction log records shown. WAL principle verified.';
GO


/*=============================================================================
  DEMO 7: Transaction States — Mapping Theory to XACT_STATE()
  
  THEORY (Elmasri Ch.4, Slide 17-18):
    State diagram:
    BEGIN TRANSACTION → ACTIVE ←(READ,WRITE)
                          ↓ END TRANSACTION
                    PARTIALLY COMMITTED → COMMIT → COMMITTED → TERMINATED
                          ↓ ABORT                              ↑
                        FAILED ─────────────────────────────────┘
  
  SQL SERVER PRACTICE:
    @@TRANCOUNT: number of active transactions (nesting level)
    XACT_STATE():
       0  → no active transaction (TERMINATED or never started)
       1  → active & committable (ACTIVE or PARTIALLY COMMITTED)
      -1  → active but doomed/uncommittable (FAILED — must rollback)
=============================================================================*/

PRINT '========== DEMO 7: Transaction States ==========';

-- State: No transaction (TERMINATED / not started)
PRINT 'State 0 - No transaction:';
PRINT '  @@TRANCOUNT = ' + CAST(@@TRANCOUNT AS VARCHAR);
PRINT '  XACT_STATE() = ' + CAST(XACT_STATE() AS VARCHAR);

-- State: ACTIVE (committable)
BEGIN TRANSACTION;
PRINT 'State 1 - ACTIVE (committable):';
PRINT '  @@TRANCOUNT = ' + CAST(@@TRANCOUNT AS VARCHAR);
PRINT '  XACT_STATE() = ' + CAST(XACT_STATE() AS VARCHAR);
COMMIT;

-- State: FAILED (uncommittable) — trigger with XACT_ABORT
SET XACT_ABORT ON;
BEGIN TRY
    BEGIN TRANSACTION;
    -- Force an error to make transaction uncommittable
    SELECT 1/0 AS ForcedError;
END TRY
BEGIN CATCH
    PRINT 'State -1 - FAILED (uncommittable):';
    PRINT '  @@TRANCOUNT = ' + CAST(@@TRANCOUNT AS VARCHAR);
    PRINT '  XACT_STATE() = ' + CAST(XACT_STATE() AS VARCHAR);
    PRINT '  ERROR: ' + ERROR_MESSAGE();
    ROLLBACK;
END CATCH;
SET XACT_ABORT OFF;

-- Back to State 0 after rollback
PRINT 'Back to State 0 - TERMINATED:';
PRINT '  @@TRANCOUNT = ' + CAST(@@TRANCOUNT AS VARCHAR);
PRINT '  XACT_STATE() = ' + CAST(XACT_STATE() AS VARCHAR);

PRINT 'DEMO 7 COMPLETE: All three transaction states demonstrated.';
GO


/*=============================================================================
  DEMO 8: Isolation Levels and Read Phenomena
  
  THEORY (Elmasri Ch.4, Slides 61-65):
    SQL2 Isolation Levels and their violations:
    
    | Isolation Level    | Dirty Read | Nonrepeatable Read | Phantom |
    |--------------------|------------|--------------------|---------| 
    | READ UNCOMMITTED   | Yes        | Yes                | Yes     |
    | READ COMMITTED     | No         | Yes                | Yes     |
    | REPEATABLE READ    | No         | No                 | Yes     |
    | SERIALIZABLE       | No         | No                 | No      |
  
  THEORY (Slides 9, 12 — Concurrency problems):
    - Lost Update: two transactions interleave writes → one lost
    - Dirty Read: read uncommitted data from failed transaction
    - Incorrect Summary: aggregate reads mix of old/new values  
    - Unrepeatable Read: same read returns different values
  
  SQL SERVER PRACTICE:
    - Same 4 levels as SQL2, PLUS: SNAPSHOT (MVCC via row versioning)
    - Default isolation: READ COMMITTED
    - SET TRANSACTION ISOLATION LEVEL <level> changes for the session
    - Below: single-session demos showing the CONCEPT of each level
      (multi-session demos require two SSMS windows — see comments)
=============================================================================*/

PRINT '========== DEMO 8: Isolation Levels ==========';

-- Show current isolation level
DBCC USEROPTIONS;

/*-- 8a. READ UNCOMMITTED — Allows Dirty Reads
-- ============================================
-- This requires TWO sessions. Instructions:

-- SESSION 1 (run this):
    BEGIN TRANSACTION;
    UPDATE Patients SET ClinicalNotes = N'DIRTY VALUE - uncommitted!' 
    WHERE PatientID = 9999;
    -- DO NOT COMMIT YET. Switch to Session 2.

-- SESSION 2 (run this in another window):
    SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
    SELECT PatientID, ClinicalNotes FROM Patients WHERE PatientID = 9999;
    -- ^^^ Will see 'DIRTY VALUE - uncommitted!' even though Session 1 
    -- hasn't committed. This is a DIRTY READ.

-- SESSION 1 (come back and run):
    ROLLBACK;
    -- The dirty value is gone. Session 2 read data that never existed.
*/

-- 8b. Single-session demonstration of isolation level syntax
PRINT '--- Setting READ UNCOMMITTED ---';
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SELECT 'READ UNCOMMITTED' AS IsolationLevel, PatientID, ClinicalNotes 
FROM Patients WHERE PatientID = 9999;

PRINT '--- Setting READ COMMITTED (default) ---';
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
SELECT 'READ COMMITTED' AS IsolationLevel, PatientID, ClinicalNotes 
FROM Patients WHERE PatientID = 9999;

PRINT '--- Setting REPEATABLE READ ---';
SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;
BEGIN TRANSACTION;
    SELECT 'REPEATABLE READ - 1st read' AS IsolationLevel, PatientID, ClinicalNotes 
    FROM Patients WHERE PatientID = 9999;
    -- Between these two reads, no other transaction can UPDATE this row
    SELECT 'REPEATABLE READ - 2nd read' AS IsolationLevel, PatientID, ClinicalNotes 
    FROM Patients WHERE PatientID = 9999;
    -- Both reads return the same value (guaranteed)
COMMIT;

PRINT '--- Setting SERIALIZABLE ---';
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
BEGIN TRANSACTION;
    -- Under SERIALIZABLE, range locks prevent phantom inserts
    SELECT 'SERIALIZABLE' AS IsolationLevel, COUNT(*) AS PatientCount 
    FROM Patients WHERE PatientID BETWEEN 9000 AND 9999;
    -- No other transaction can INSERT a PatientID in [9000, 9999] range
COMMIT;

-- Reset to default
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;

PRINT 'DEMO 8 COMPLETE: All isolation levels demonstrated.';
GO


/*=============================================================================
  DEMO 9: Theory vs Practice — Summary Comparison
  
  This section provides a structured comparison between the textbook 
  (Elmasri Ch.4) and SQL Server 2025 implementation. Use this for the 
  report and presentation.
=============================================================================*/

PRINT '========== DEMO 9: Theory vs Practice Summary ==========';

SELECT 'Theory vs Practice' AS Section, Concept, Theory, SQLServerPractice
FROM (VALUES
    ('Transaction Definition',
     'Logical unit of DB processing with read/write ops, bounded by Begin/End',
     'BEGIN TRAN...COMMIT/ROLLBACK. Each SQL statement is also atomic on its own.'),
    
    ('ACID - Atomicity', 
     'All operations execute or none do',
     'ROLLBACK undoes all; XACT_ABORT + TRY/CATCH enforces. Demo 2 proved zero partial records.'),
    
    ('ACID - Consistency',
     'Transaction takes DB from consistent state to consistent state',
     'PK/FK/CHECK constraints enforced at statement level. FK_Patient prevents orphan images.'),
    
    ('ACID - Isolation',
     'Transaction appears to execute in isolation from others',
     '5 isolation levels (READ UNCOMMITTED → SNAPSHOT). Default: READ COMMITTED.'),
    
    ('ACID - Durability',
     'Committed changes must never be lost',
     'WAL ensures log records written to disk BEFORE commit returns. .ldf file on persistent storage.'),
    
    ('Transaction States',
     'Active → Partially Committed → Committed, or Active/PartCommit → Failed → Terminated',
     'XACT_STATE(): 1=committable, -1=uncommittable(failed), 0=no transaction. Demo 7.'),
    
    ('System Log',
     '[start_transaction,T], [write_item,T,X,old,new], [commit,T], [abort,T]',
     'sys.fn_dblog(): LOP_BEGIN_XACT, LOP_MODIFY_ROW, LOP_COMMIT_XACT, LOP_ABORT_XACT. Demo 6.'),
    
    ('Recovery (Undo/Redo)',
     'Undo: trace backward, restore old values. Redo: trace forward, apply new values.',
     'ARIES-based recovery: Analysis → Redo → Undo phases on crash restart. Automatic.'),
    
    ('Schedules & Serializability',
     'Serial: all ops of T consecutive. Serializable: equivalent to some serial schedule.',
     'SQL Server uses Strict 2PL (locks held until commit) to guarantee serializability at SERIALIZABLE level.'),
    
    ('Conflict Operations',
     'Different transactions, same item, at least one write',
     'Lock compatibility matrix: S-S compatible, S-X conflict, X-X conflict. sys.dm_tran_locks.'),
    
    ('Isolation Levels (SQL2)',
     'READ UNCOMMITTED, READ COMMITTED, REPEATABLE READ, SERIALIZABLE',
     'Same 4 levels + SNAPSHOT (MVCC via row versioning in tempdb). SET TRANSACTION ISOLATION LEVEL.'),
    
    ('Dirty/NonRepeatable/Phantom',
     'Violation table (Slide 65): each level prevents progressively more anomalies',
     'Same behavior in SQL Server. SNAPSHOT additionally prevents all 3 via row versioning without blocking.'),
    
    ('Savepoint / Partial Undo',
     'undo applies to single operation rather than whole transaction',
     'SAVE TRANSACTION <name> + ROLLBACK TRANSACTION <name>. Demo 3.'),
    
    ('Implicit vs Explicit',
     'SQL2: no explicit BEGIN, transactions start implicitly',
     'SQL Server default: AUTOCOMMIT. SET IMPLICIT_TRANSACTIONS ON matches SQL2 behavior. Demo 5.')
    
) AS T(Concept, Theory, SQLServerPractice);

PRINT 'DEMO 9 COMPLETE: Theory-practice comparison table generated.';
GO


/*=============================================================================
  CLEANUP: Remove demo data
  Uncomment and run after demos are complete and screenshots are taken.
=============================================================================*/

/*
DELETE FROM MRIImages WHERE PatientID IN (9999, 8888, 7777, 6666, 5555, 4444);
DELETE FROM Patients  WHERE PatientID IN (9999, 8888, 7777, 6666, 5555, 4444);
PRINT 'Cleanup complete: all demo patients removed.';
*/
