-- ============================================================
-- 03_query_processing.sql — Query Processing Demos (Member A)
-- DBMS: Microsoft SQL Server 2025
-- Dataset: MRIDatabase (500 patients)
-- ============================================================

USE MRIDatabase;
GO

SET STATISTICS IO ON;
SET STATISTICS TIME ON;

-- ************************************************************
-- A7. EXECUTION PLAN ANALYSIS
-- Theory: Query processing = Parse → Optimize → Execute
-- SQL Server: Parse → Algebrize → Optimize → Execute
-- ************************************************************

-- Enable actual execution plan (in SSMS: Ctrl+M)
-- Or use SET SHOWPLAN_ALL for text-based plans:
-- SET SHOWPLAN_ALL ON;

-- (a) Simple point query → Clustered Index Seek
SELECT * FROM Patients WHERE PatientID = 100;

-- (b) JOIN query → Nested Loops or Hash Match
SELECT
    p.PatientID,
    p.ClinicalNotes,
    m.SeriesType,
    m.SliceNumber
FROM Patients p
JOIN MRIImages m ON p.PatientID = m.PatientID
WHERE p.PatientID = 100;

-- (c) Aggregation → Stream Aggregate or Hash Aggregate
SELECT PatientID, COUNT(*) AS ImageCount
FROM MRIImages
GROUP BY PatientID;

-- (d) Subquery → optimizer may transform to JOIN
SELECT *
FROM Patients
WHERE PatientID IN (
    SELECT DISTINCT PatientID
    FROM MRIImages
    WHERE SeriesType = 'T1'
);

-- (e) Vector similarity query
DECLARE @qvec VECTOR(512);
-- SET @qvec = (SELECT Embedding FROM MRIImages WHERE ...);
SELECT TOP 5 ImageID, VECTOR_DISTANCE('cosine', Embedding, @qvec) AS dist
FROM MRIImages
ORDER BY VECTOR_DISTANCE('cosine', Embedding, @qvec);


-- ************************************************************
-- A8. EXTERNAL SORTING
-- Theory: Sort-merge algorithm — create sorted runs, merge.
-- SQL Server: Sort operator, may spill to tempdb.
-- ************************************************************

-- Without index on SeriesType: Sort operator required
-- (Drop index first if it exists from 02_indexes.sql)
-- DROP INDEX IF EXISTS idx_series ON MRIImages;
SELECT * FROM MRIImages ORDER BY SeriesType;
-- Execution plan shows: Clustered Index Scan → Sort

-- With index: no Sort needed
-- CREATE NONCLUSTERED INDEX idx_series ON MRIImages(SeriesType);
SELECT SeriesType, ImageID FROM MRIImages ORDER BY SeriesType;
-- Execution plan shows: Index Scan (ordered) — no Sort operator

-- Check for sort spills (memory grant exceeded)
-- In execution plan XML, look for: <SpillToTempDb>
-- Or use Extended Events: sort_warning


-- ************************************************************
-- A9. SELECT ALGORITHMS
-- Theory: S1=linear, S2=binary, S3=primary index,
--         S4=primary range, S6=secondary index
-- ************************************************************

-- S1: Linear search (Table Scan / Clustered Index Scan)
-- No usable index on ClinicalNotes (NVARCHAR(MAX))
SELECT * FROM Patients WHERE ClinicalNotes LIKE '%tumor%';
-- Plan: Clustered Index Scan with predicate filter

-- S3 equivalent: Primary index search (Clustered Index Seek)
SELECT * FROM Patients WHERE PatientID = 42;
-- Plan: Clustered Index Seek

-- S4 equivalent: Primary index range (Clustered Seek with range)
SELECT * FROM Patients WHERE PatientID BETWEEN 50 AND 100;
-- Plan: Clustered Index Seek (range)

-- S6 equivalent: Secondary index (Non-Clustered Index Seek)
SELECT * FROM MRIImages WHERE SeriesType = 'T2';
-- Plan: Index Seek (idx_series) + Key Lookup (to get remaining cols)

-- Conjunction: AND condition with composite or index intersection
SELECT * FROM MRIImages
WHERE PatientID = 100 AND SeriesType = 'T1';
-- Optimizer may use idx_patient_slice or idx_series, or intersect both


-- ************************************************************
-- A10. JOIN ALGORITHMS
-- Theory: J1=Nested Loop, J3=Sort-Merge, J4=Hash Join
-- SQL Server: Nested Loops, Merge Join, Hash Match
-- ************************************************************

-- (a) Nested Loops — typically for small outer input + indexed inner
SELECT p.PatientID, m.SeriesType
FROM Patients p
JOIN MRIImages m ON p.PatientID = m.PatientID
WHERE p.PatientID = 100;
-- Plan: Nested Loops (outer=Patients seek, inner=MRIImages seek)

-- (b) Hash Match — for larger unsorted inputs
SELECT p.PatientID, COUNT(*) AS img_count
FROM Patients p
JOIN MRIImages m ON p.PatientID = m.PatientID
GROUP BY p.PatientID;
-- Plan likely: Hash Match Join + Hash Match Aggregate

-- (c) Merge Join — both inputs sorted on join key
-- Force with hint if needed:
SELECT p.PatientID, m.SeriesType
FROM Patients p
JOIN MRIImages m ON p.PatientID = m.PatientID
OPTION (MERGE JOIN);
-- Plan: Merge Join (requires both inputs sorted on PatientID)

-- Compare costs of all three:
-- Nested Loop: best for small outer, indexed inner
-- Hash Match: best for large unsorted inputs, no index
-- Merge Join: best for large pre-sorted inputs


-- ************************************************************
-- A11. HEURISTIC & COST-BASED OPTIMIZATION
-- Theory: Push selections down, reorder joins, use selectivity.
-- SQL Server: Cost-based with heuristic pruning.
-- ************************************************************

-- Show how optimizer reorders operations:
-- Complex query:
SELECT p.PatientID, p.ClinicalNotes, m.SeriesType, COUNT(*) AS cnt
FROM Patients p
JOIN MRIImages m ON p.PatientID = m.PatientID
WHERE p.StudyDate > '2024-01-01'
  AND m.SeriesType = 'T1'
GROUP BY p.PatientID, p.ClinicalNotes, m.SeriesType
HAVING COUNT(*) > 2
ORDER BY cnt DESC;
-- Check plan: optimizer pushes WHERE filters down before JOIN

-- Force join order (disable heuristic reordering):
SELECT p.PatientID, m.SeriesType
FROM Patients p
JOIN MRIImages m ON p.PatientID = m.PatientID
WHERE m.SeriesType = 'T1'
OPTION (FORCE ORDER);
-- Compare cost with vs without FORCE ORDER

-- Show statistics that drive cost estimation:
DBCC SHOW_STATISTICS('MRIImages', 'idx_series');
-- Output: histogram (up to 200 steps), density vector, header
-- avg_rows_per_range = selectivity estimate

-- Update statistics (recalculates after data changes):
UPDATE STATISTICS MRIImages;

-- Show estimated vs actual row counts in execution plan:
-- In SSMS actual plan: hover over each operator to see
-- "Estimated Number of Rows" vs "Actual Number of Rows"
-- Large discrepancies indicate stale statistics


-- ************************************************************
-- A12. PIPELINING (Iterator Model)
-- Theory: Pass tuples between ops without materializing.
-- SQL Server: Open/GetNext/Close iterator model.
-- ************************************************************

-- This query pipelines: Index Seek → Nested Loop → Output
-- No intermediate materialization needed
SELECT p.PatientID, m.SeriesType
FROM Patients p
JOIN MRIImages m ON p.PatientID = m.PatientID
WHERE p.PatientID BETWEEN 1 AND 10;

-- This query requires materialization (blocking operator):
SELECT PatientID, COUNT(*) AS cnt
FROM MRIImages
GROUP BY PatientID
ORDER BY cnt DESC;
-- Hash Aggregate = blocking (must see all rows before output)
-- Sort = blocking (must see all rows before outputting sorted)

-- In execution plan, blocking operators have a "thick arrow" 
-- (many rows buffered) going IN but output starts only after
-- all input is consumed.


SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
