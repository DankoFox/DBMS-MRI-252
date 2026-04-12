-- ============================================================
-- 05_concurrency.sql — Concurrency Control Demos (Member C)
-- DBMS: Microsoft SQL Server 2025
-- Dataset: MRIDatabase (500 patients)
-- ============================================================
-- INSTRUCTIONS:
--   Each demo requires TWO sessions (two SSMS query windows
--   connected to MRIDatabase). Run steps marked [Session 1]
--   and [Session 2] in the corresponding windows IN ORDER.
-- ============================================================

USE MRIDatabase; ddddd
GO

-- ************************************************************
-- C1. DIRTY READ DEMO
-- Theory: A dirty read occurs when T2 reads a value written
--         by T1 that has NOT been committed. If T1 rolls back,
--         T2 has read data that never officially existed.
-- Practice: SQL Server allows dirty reads ONLY under
--           READ UNCOMMITTED isolation level.
-- ************************************************************

-- [Session 1] — Writer (do NOT commit yet)
BEGIN TRAN;
    UPDATE Patients
    SET ClinicalNotes = 'DIRTY-WRITE: Temporary note for demo'
    WHERE PatientID = 1;
    -- DO NOT COMMIT — leave transaction open
    -- Now switch to Session 2

-- [Session 2] — Reader with READ UNCOMMITTED
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SELECT PatientID, ClinicalNotes
FROM Patients
WHERE PatientID = 1;
-- Result: sees 'DIRTY-WRITE: Temporary note for demo'
-- This is a DIRTY READ — data is uncommitted

-- [Session 1] — Roll back the change
ROLLBACK;

-- [Session 2] — Read again
SELECT PatientID, ClinicalNotes
FROM Patients
WHERE PatientID = 1;
-- Result: original value restored. Session 2 previously read
--         phantom data that was never committed.


-- ************************************************************
-- C2. BLOCKING (LOCK WAIT) DEMO
-- Theory: In 2PL, when T1 holds an exclusive (X) lock on item X,
--         T2 requesting a Shared (S) lock must WAIT until T1
--         releases the lock (mutual exclusion).
-- Practice: SQL Server's default READ COMMITTED uses S/X locks.
--           Session 2 blocks until Session 1 commits/rolls back.
-- ************************************************************

-- [Session 1] — Acquire exclusive lock
BEGIN TRAN;
    UPDATE Patients
    SET ClinicalNotes = 'Locked by Session 1'
    WHERE PatientID = 2;
    -- Transaction stays open → X lock held on row PatientID=2

-- [Session 2] — Try to read the locked row (will BLOCK)
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
SELECT PatientID, ClinicalNotes
FROM Patients
WHERE PatientID = 2;
-- This query HANGS — blocked by Session 1's X lock

-- [Monitor] — In a third window, inspect locks:
SELECT
    t.resource_type,
    t.resource_description,
    t.request_mode,
    t.request_status,
    s.session_id,
    s.login_name,
    q.text AS query_text
FROM sys.dm_tran_locks t
JOIN sys.dm_exec_sessions s ON t.request_session_id = s.session_id
OUTER APPLY sys.dm_exec_sql_text(s.most_recent_sql_handle) q
WHERE t.resource_database_id = DB_ID('MRIDatabase')
ORDER BY t.request_session_id;

-- You will see:
--   Session 1: request_mode = X, request_status = GRANT
--   Session 2: request_mode = S, request_status = WAIT

-- [Session 1] — Release lock
COMMIT;
-- Session 2 now unblocks and returns the result


-- ************************************************************
-- C3. DEADLOCK DEMO
-- Theory: Deadlock occurs when two transactions form a cycle
--         in the wait-for graph: T1 waits for T2, T2 waits for T1.
--         Resolution: abort one transaction (the victim).
-- Practice: SQL Server automatically detects deadlocks via its
--           internal wait-for graph. It selects a victim (least
--           cost to rollback) and raises error 1205.
-- ************************************************************

-- [Session 1] — Lock row PatientID=1, then request row PatientID=2
BEGIN TRAN;
    UPDATE Patients SET ClinicalNotes = 'S1 locks P1'
    WHERE PatientID = 1;
    -- Now pause and let Session 2 execute its first UPDATE
    
    WAITFOR DELAY '00:00:05';  -- 5 second delay for demo timing
    
    -- After Session 2 has locked PatientID=2, request it:
    UPDATE Patients SET ClinicalNotes = 'S1 wants P2'
    WHERE PatientID = 2;
    -- This will either succeed (if we win) or we get error 1205
COMMIT;

-- [Session 2] — Lock row PatientID=2, then request row PatientID=1
BEGIN TRAN;
    UPDATE Patients SET ClinicalNotes = 'S2 locks P2'
    WHERE PatientID = 2;
    
    WAITFOR DELAY '00:00:05';  -- 5 second delay for demo timing
    
    -- After Session 1 has locked PatientID=1, request it:
    UPDATE Patients SET ClinicalNotes = 'S2 wants P1'
    WHERE PatientID = 1;
    -- DEADLOCK: one session gets error 1205
COMMIT;

-- [After deadlock] — Capture the deadlock graph from Extended Events:
SELECT
    xdr.value('@timestamp', 'datetime2') AS deadlock_time,
    xdr.query('.') AS deadlock_graph_xml
FROM (
    SELECT CAST(target_data AS XML) AS target_data
    FROM sys.dm_xe_sessions s
    JOIN sys.dm_xe_session_targets t ON s.address = t.event_session_address
    WHERE s.name = 'system_health'
      AND t.target_name = 'ring_buffer'
) AS data
CROSS APPLY target_data.nodes('//RingBufferTarget/event[@name="xml_deadlock_report"]') AS xdr(xdr)
ORDER BY deadlock_time DESC;


-- ************************************************************
-- C4. ISOLATION LEVELS COMPARISON
-- Theory: SQL standard defines 4 isolation levels that control
--         which concurrency anomalies are permitted:
--         READ UNCOMMITTED → dirty reads allowed
--         READ COMMITTED   → no dirty reads
--         REPEATABLE READ  → no dirty reads, no non-repeatable reads
--         SERIALIZABLE     → no dirty reads, no non-repeatable reads,
--                            no phantom reads
-- Practice: SQL Server implements all 4 + SNAPSHOT isolation.
-- ************************************************************

-- Anomaly matrix (what each level PREVENTS):
-- +---------------------+----------+------------------+--------+
-- | Level               | Dirty Rd | Non-Repeatable   | Phantom|
-- +---------------------+----------+------------------+--------+
-- | READ UNCOMMITTED    |    No    |       No         |   No   |
-- | READ COMMITTED      |   Yes    |       No         |   No   |
-- | REPEATABLE READ     |   Yes    |      Yes         |   No   |
-- | SERIALIZABLE        |   Yes    |      Yes         |  Yes   |
-- | SNAPSHOT (SQL Srv)  |   Yes    |      Yes         |  Yes   |
-- +---------------------+----------+------------------+--------+

-- === C4a. Non-Repeatable Read demo ===

-- [Session 1] — Under READ COMMITTED
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
BEGIN TRAN;
    -- First read
    SELECT PatientID, ClinicalNotes FROM Patients WHERE PatientID = 3;
    -- Now let Session 2 update and commit

-- [Session 2]
UPDATE Patients SET ClinicalNotes = 'Updated by S2' WHERE PatientID = 3;

-- [Session 1] — Second read (within same transaction)
    SELECT PatientID, ClinicalNotes FROM Patients WHERE PatientID = 3;
    -- DIFFERENT result → non-repeatable read!
COMMIT;

-- === C4b. Repeatable Read prevents that ===

-- [Session 1]
SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;
BEGIN TRAN;
    SELECT PatientID, ClinicalNotes FROM Patients WHERE PatientID = 3;
    -- S lock held on the row until COMMIT

-- [Session 2]
UPDATE Patients SET ClinicalNotes = 'Try update by S2' WHERE PatientID = 3;
-- BLOCKED — cannot modify because Session 1 holds S lock

-- [Session 1]
    SELECT PatientID, ClinicalNotes FROM Patients WHERE PatientID = 3;
    -- SAME result → repeatable read guaranteed!
COMMIT;
-- Session 2 now unblocks

-- === C4c. Phantom Read demo ===

-- [Session 1] — Under REPEATABLE READ
SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;
BEGIN TRAN;
    SELECT COUNT(*) AS PatientCount FROM Patients WHERE PatientID BETWEEN 1 AND 10;
    -- Suppose returns 10

-- [Session 2]
INSERT INTO Patients (PatientID, ClinicalNotes) VALUES (11, 'Phantom patient');

-- [Session 1]
    SELECT COUNT(*) AS PatientCount FROM Patients WHERE PatientID BETWEEN 1 AND 11;
    -- Returns 11 — phantom row appeared!
COMMIT;

-- === C4d. SERIALIZABLE prevents phantoms ===

-- [Session 1]
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
BEGIN TRAN;
    SELECT COUNT(*) AS PatientCount FROM Patients WHERE PatientID BETWEEN 1 AND 10;
    -- Range lock placed on key range

-- [Session 2]
INSERT INTO Patients (PatientID, ClinicalNotes) VALUES (12, 'Blocked phantom');
-- BLOCKED — range lock prevents inserts into the locked range

-- [Session 1]
    SELECT COUNT(*) AS PatientCount FROM Patients WHERE PatientID BETWEEN 1 AND 10;
    -- Same count — no phantoms!
COMMIT;


-- ************************************************************
-- C5. RCSI (READ COMMITTED SNAPSHOT ISOLATION)
-- Theory: Multi-Version Concurrency Control (MVCC) maintains
--         multiple versions of data items so readers don't block
--         writers and writers don't block readers.
-- Practice: SQL Server implements MVCC via Row Versioning in
--           tempdb. Two modes:
--           1) READ_COMMITTED_SNAPSHOT ON → readers get versioned
--              snapshot under READ COMMITTED (replaces lock-based)
--           2) ALLOW_SNAPSHOT_ISOLATION ON → explicit SNAPSHOT level
-- ************************************************************

-- Enable RCSI (requires exclusive DB access, so close other connections or use):
ALTER DATABASE MRIDatabase SET READ_COMMITTED_SNAPSHOT ON WITH ROLLBACK IMMEDIATE;
GO

-- [Session 1] — Writer
BEGIN TRAN;
    UPDATE Patients SET ClinicalNotes = 'Updated by S1 - RCSI test'
    WHERE PatientID = 2;
    -- X lock held, but readers will get the OLD version

-- [Session 2] — Reader under READ COMMITTED (now uses row versioning)
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
SELECT PatientID, ClinicalNotes
FROM Patients
WHERE PatientID = 2;
-- NO BLOCKING! Returns the OLD committed version
-- (before Session 1's uncommitted update)

-- [Session 1]
COMMIT;

-- [Session 2] — Now reads the new committed version
SELECT PatientID, ClinicalNotes
FROM Patients
WHERE PatientID = 2;
-- Returns 'Updated by S1 - RCSI test'

-- Inspect version store usage in tempdb:
SELECT * FROM sys.dm_tran_version_store_space_usage;


-- ************************************************************
-- C6. LOCK MONITORING & LOCK TYPES
-- Theory: Locks come in various modes — S (shared), X (exclusive),
--         IS (intent shared), IX (intent exclusive), U (update).
--         Lock granularity: ROW, KEY, PAGE, TABLE, DATABASE.
-- Practice: SQL Server exposes all lock info via DMVs.
-- ************************************************************

-- Show all current locks in MRIDatabase:
SELECT
    t.resource_type,
    t.resource_subtype,
    t.resource_description,
    t.resource_associated_entity_id,
    t.request_mode,
    t.request_type,
    t.request_status,
    t.request_session_id
FROM sys.dm_tran_locks t
WHERE t.resource_database_id = DB_ID('MRIDatabase')
ORDER BY t.request_session_id, t.resource_type;

-- Lock escalation monitoring:
-- When SQL Server acquires too many row/page locks on a single
-- table (default threshold ~5000 locks), it escalates to a TABLE lock.
-- This is analogous to the theory's Multiple Granularity Locking.

-- Force a large update to trigger lock escalation:
BEGIN TRAN;
    UPDATE Patients SET StudyDate = GETDATE();
    -- Check locks — should see TABLE-level X lock instead of row locks
    SELECT resource_type, request_mode, COUNT(*) AS lock_count
    FROM sys.dm_tran_locks
    WHERE resource_database_id = DB_ID('MRIDatabase')
    GROUP BY resource_type, request_mode;
ROLLBACK;

-- Wait statistics for lock waits:
SELECT *
FROM sys.dm_os_wait_stats
WHERE wait_type LIKE 'LCK%'
ORDER BY waiting_tasks_count DESC;


-- ************************************************************
-- C7. THEORY VS PRACTICE — DETAILED COMPARISON
-- See the companion document in workload.md under
-- "Concurrency Control: Theory vs SQL Server Practice"
-- ************************************************************
