USE MRIDatabase;


-- Add some idiotic PK
ALTER TABLE MRIImages
ADD VectorID INT IDENTITY(1,1);

SELECT name
FROM sys.key_constraints
WHERE [type] = 'PK' AND [parent_object_id] = OBJECT_ID('dbo.MRIImages');

ALTER TABLE MRIImages
DROP CONSTRAINT PK__MRIImage__7516F4ECC66A50CB;

ALTER TABLE MRIImages
ADD CONSTRAINT PK_MRIImages
PRIMARY KEY CLUSTERED (VectorID);

CREATE UNIQUE INDEX UX_MRIImages_ImageID
ON MRIImages(ImageID);

-- Enable some idiotic configuration
ALTER DATABASE SCOPED CONFIGURATION SET PREVIEW_FEATURES = ON;
GO
EXEC sp_configure 'show advanced options', 1;
RECONFIGURE;

SELECT @@VERSION;

-- Create vector index

CREATE VECTOR INDEX IX_MRIImages_Embedding
ON MRIImages(Embedding)
WITH (
    TYPE = 'DiskANN',
    METRIC = 'cosine'
);




-- Use a specific GUID string here
DECLARE @TargetID UNIQUEIDENTIFIER = '60735DA0-2735-421D-87A5-D89DD0EF2B6C'; 

-- Assign the embedding to the vector variable
DECLARE @TargetVector VECTOR(512);
SELECT @TargetVector = Embedding FROM MRIImages WHERE ImageID = @TargetID;

-- Perform the Similarity Search
SELECT TOP 5 
    ImageID, 
    PatientID, 
    VECTOR_DISTANCE('cosine', Embedding, @TargetVector) AS Distance
FROM MRIImages
WHERE ImageID != @TargetID
ORDER BY Distance ASC; 


