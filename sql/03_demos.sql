/* 
   DBMS-MRI-252: ASSESSMENT DEMOS 
   Targeting SQL Server 2025 Core Functionalities
*/

USE MRIDatabase;
GO

---------------------------------------------------------
-- 1. INDEXING (Showing Table Scan vs. Index Seek)
---------------------------------------------------------
-- Turn on statistics to see the "Logical Reads" difference
SET STATISTICS IO ON;
SET STATISTICS TIME ON;

-- Step A: Search on a column without a non-clustered index (SeriesType)
-- Note: SeriesType is currently indexed only if it's part of the PK or if you added one.
-- Let's check for a specific series type.
SELECT PatientID, SliceNumber FROM MRIImages WHERE SeriesType = 't2_tse_sag';

-- Step B: Create an index and run again
CREATE INDEX IX_MRIImages_SeriesType ON MRIImages(SeriesType);

SELECT PatientID, SliceNumber FROM MRIImages WHERE SeriesType = 't2_tse_sag';

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
GO

---------------------------------------------------------
-- 2. QUERY PROCESSING (Execution Plan Analysis)
---------------------------------------------------------
-- In SSMS, press Ctrl+L (Display Estimated Execution Plan) or Ctrl+M (Include Actual Plan)
-- Highlight the query below to show "Vector Distance" operator and "Index Seek"

DECLARE @TargetVector VECTOR(512);
SELECT TOP 1 @TargetVector = Embedding FROM MRIImages;

SELECT TOP 10 
    ImageID, 
    VECTOR_DISTANCE('cosine', Embedding, @TargetVector) AS Distance
FROM MRIImages
ORDER BY Distance ASC;
GO

---------------------------------------------------------
-- 3. TRANSACTIONS (ACID Compliance Demo)
---------------------------------------------------------
-- Prove that the DB stays consistent even if an error occurs mid-process.

BEGIN TRANSACTION;

-- Insert a new patient
INSERT INTO Patients (PatientID, ClinicalNotes) VALUES (999, 'Test Transaction Patient');

-- Insert an image for that patient
INSERT INTO MRIImages (PatientID, SeriesType, SliceNumber, ImageData) 
VALUES (999, 'Test_Series', 1, 0x010203);

-- Verify they exist in this transaction scope
SELECT * FROM Patients WHERE PatientID = 999;

-- Simulate a failure or explicit ROLLBACK
ROLLBACK;

-- Prove that the data is GONE (no partial records)
SELECT * FROM Patients WHERE PatientID = 999;
GO

---------------------------------------------------------
-- 4. CONCURRENCY CONTROL (Locking & Blocking)
---------------------------------------------------------
-- SESSION 1 (Run this first):
/*
BEGIN TRANSACTION;
UPDATE Patients SET ClinicalNotes = 'Updating...' WHERE PatientID = 1;
-- DO NOT COMMIT YET
*/

-- SESSION 2 (Run this while Session 1 is open):
/*
SELECT * FROM Patients WHERE PatientID = 1; 
-- Notice: This query HANGS/WAITING because Session 1 has an X-Lock.
*/

-- RESOLUTION: Show Read Committed Snapshot Isolation (RCSI)
/*
ALTER DATABASE MRIDatabase SET READ_COMMITTED_SNAPSHOT ON;
-- Now run the SELECT in Session 2 again. It returns the OLD value immediately!
*/
