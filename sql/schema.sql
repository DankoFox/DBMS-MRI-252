CREATE DATABASE MRIDatabase;
USE MRIDatabase;

CREATE TABLE Patients (
    PatientID INT PRIMARY KEY,
    ClinicalNotes NVARCHAR(MAX),
    StudyDate DATE DEFAULT GETDATE()
);

CREATE TABLE MRIImages (
    ImageID UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
    PatientID INT NOT NULL,
    SeriesType NVARCHAR(100),
    SliceNumber INT,
    ImageData VARBINARY(MAX),
    Embedding VECTOR(512), 
    CONSTRAINT FK_Patient FOREIGN KEY (PatientID) REFERENCES Patients(PatientID)
);

-- OPTIMAL: Create a DiskANN Vector Index for fast similarity searching
-- CREATE VECTOR INDEX idx_mri_embeddings ON MRIImages(Embedding) 
-- WITH (DISTANCE_METRIC = 'COSINE');
-- GO
