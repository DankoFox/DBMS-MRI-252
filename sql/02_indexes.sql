-- ============================================================
-- 02_indexes.sql — Indexing Demos (Member A)
-- DBMS: Microsoft SQL Server 2025
-- Dataset: MRIDatabase (500 patients)
-- ============================================================

USE MRIDatabase;
GO

-- ************************************************************
-- A1. PRIMARY INDEX (CLUSTERED INDEX)
-- Theory: Primary index on ordering key. Sparse, one per file.
-- SQL Server: Clustered index = data IS the leaf level.
-- ************************************************************

-- Show existing clustered index on Patients (PK)
EXEC sp_helpindex 'Patients';
GO

SET STATISTICS IO ON;
SET STATISTICS TIME ON;

-- Point query on clustering key → Clustered Index Seek
SELECT * FROM Patients WHERE PatientID = 250;

-- Range query → Clustered Index Seek (range scan)
SELECT * FROM Patients WHERE PatientID BETWEEN 100 AND 200;

-- Check index structure: depth, page counts, fragmentation
SELECT
    index_id,
    index_type_desc,
    index_depth,
    index_level,
    page_count,
    record_count,
    avg_fragmentation_in_percent
FROM sys.dm_db_index_physical_stats(
    DB_ID('MRIDatabase'),
    OBJECT_ID('Patients'),
    NULL, NULL, 'DETAILED'
);


-- ************************************************************
-- A2. SECONDARY INDEX (NON-CLUSTERED INDEX)
-- Theory: Dense index on non-ordering field. Multiple allowed.
-- SQL Server: Non-clustered = leaf has key + bookmark (RID/CK).
-- ************************************************************

-- BEFORE: Query without index (Table Scan / Clustered Index Scan)
SELECT * FROM MRIImages WHERE SeriesType = 'T1';
-- Note the logical reads from STATISTICS IO → high (full scan)

-- Create non-clustered index
CREATE NONCLUSTERED INDEX idx_series
ON MRIImages(SeriesType);
GO

-- AFTER: Same query with index (Index Seek + Key Lookup)
SELECT * FROM MRIImages WHERE SeriesType = 'T1';
-- Note logical reads → much lower

-- Show index details
EXEC sp_helpindex 'MRIImages';
GO


-- ************************************************************
-- A3. CLUSTERING INDEX BEHAVIOR
-- Theory: Index on non-key ordering field (duplicates).
-- SQL Server: Clustered index on non-unique col → uniquifier.
-- ************************************************************

-- Show how many distinct SeriesType values exist
SELECT SeriesType, COUNT(*) AS cnt
FROM MRIImages
GROUP BY SeriesType
ORDER BY cnt DESC;

-- If we were to create a clustered index on SeriesType (non-unique):
-- CREATE CLUSTERED INDEX idx_series_clustered ON MRIImages(SeriesType);
-- SQL Server would add a hidden 4-byte uniquifier for duplicate keys.
-- (We don't do this since MRIImages already has a PK clustered index)


-- ************************************************************
-- A4. COMPOSITE (MULTI-COLUMN) INDEX
-- Theory: Multilevel index concept — column order matters.
-- ************************************************************

CREATE NONCLUSTERED INDEX idx_patient_slice
ON MRIImages(PatientID, SliceNumber);
GO

-- Both columns in WHERE → Index Seek (leftmost prefix used)
SELECT * FROM MRIImages
WHERE PatientID = 100 AND SliceNumber = 5;

-- Only second column → Index Scan (leading column missing)
SELECT * FROM MRIImages
WHERE SliceNumber = 5;

-- Covering index: all requested columns in index → no Key Lookup
SELECT PatientID, SliceNumber
FROM MRIImages
WHERE PatientID = 100;

-- Include columns to make a wider covering index
CREATE NONCLUSTERED INDEX idx_patient_slice_covering
ON MRIImages(PatientID, SliceNumber)
INCLUDE (SeriesType);
GO

-- Now this query is fully covered:
SELECT PatientID, SliceNumber, SeriesType
FROM MRIImages
WHERE PatientID = 100;


-- ************************************************************
-- A5. B+-TREE STRUCTURE INSPECTION
-- Theory: B+-Tree: data at leaves, internal nodes = keys only.
-- ************************************************************

-- Index physical stats for MRIImages (all indexes)
SELECT
    i.name AS index_name,
    i.type_desc,
    ps.index_depth,
    ps.index_level,
    ps.page_count,
    ps.record_count,
    ps.avg_page_space_used_in_percent,
    ps.avg_fragmentation_in_percent
FROM sys.dm_db_index_physical_stats(
    DB_ID('MRIDatabase'),
    OBJECT_ID('MRIImages'),
    NULL, NULL, 'DETAILED'
) ps
JOIN sys.indexes i
    ON ps.object_id = i.object_id AND ps.index_id = i.index_id
ORDER BY i.name, ps.index_level;

-- Show page chain (advanced — requires trace flag or DBCC)
-- DBCC IND('MRIDatabase', 'MRIImages', 1);  -- index_id 1 = clustered

-- Show fragmentation and when to rebuild
-- Rule of thumb: >30% fragmentation → REBUILD, 5-30% → REORGANIZE
-- ALTER INDEX idx_series ON MRIImages REBUILD;
-- ALTER INDEX idx_series ON MRIImages REORGANIZE;


-- ************************************************************
-- A6. DISKANN VECTOR INDEX
-- Theory: Beyond textbook — graph-based ANN for high-dim vectors.
-- ************************************************************

-- BEFORE: Brute-force vector search (full scan)
DECLARE @query_vec VECTOR(512);
-- In practice, set @query_vec from Python or a known embedding
-- SELECT @query_vec = Embedding FROM MRIImages WHERE ImageID = '...';

-- Without vector index: scans all rows
SELECT TOP 5
    ImageID,
    PatientID,
    SeriesType,
    VECTOR_DISTANCE('cosine', Embedding, @query_vec) AS distance
FROM MRIImages
ORDER BY VECTOR_DISTANCE('cosine', Embedding, @query_vec);

-- Create DiskANN vector index
CREATE VECTOR INDEX idx_mri_embeddings
ON MRIImages(Embedding)
WITH (DISTANCE_METRIC = 'COSINE');
GO

-- AFTER: Same query now uses approximate nearest neighbor
SELECT TOP 5
    ImageID,
    PatientID,
    SeriesType,
    VECTOR_DISTANCE('cosine', Embedding, @query_vec) AS distance
FROM MRIImages
ORDER BY VECTOR_DISTANCE('cosine', Embedding, @query_vec);

-- Compare execution plans: look for Vector Index Scan operator


-- ************************************************************
-- CLEANUP (optional — run only if you want to reset)
-- ************************************************************
-- DROP INDEX idx_series ON MRIImages;
-- DROP INDEX idx_patient_slice ON MRIImages;
-- DROP INDEX idx_patient_slice_covering ON MRIImages;
-- DROP INDEX idx_mri_embeddings ON MRIImages;

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
