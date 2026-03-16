# 🧠 Developer Context Guide: DBMS-MRI-252

## 1. Data Patterns
*   **PatientID:** Integer (`INT`), primary key for the `Patients` table. Corresponds to the numerical folder names in `data/01_MRI_Data/`.
*   **ImageID:** Globally Unique Identifier (`UNIQUEIDENTIFIER/GUID`), primary key for `MRIImages`. Generated via `NEWID()` or assigned during ingestion.
*   **Clinical Dates:** `StudyDate` follows the `YYYY-MM-DD` format (`DATE` type), defaulting to the current system date.

## 2. Clinical Metadata
Medical findings are stored as multiline free-text in the `ClinicalNotes` column. Common patterns and pathology keywords include:
*   **Spinal Levels:** L4-5, L5-S1, C5-6.
*   **Pathology Keywords:** `herniation`, `bulge`, `spinal stenosis`, `spondylolisthesis`, `protrusion`, `degenerative`.
*   **Search Logic:** Typically queried using `LIKE '%keyword%'` for relational filtering.

## 3. Series Vocabulary
The `SeriesType` column (derived from DICOM `SeriesDescription`) contains specific MRI sequence nomenclature:
*   `t2_tse_sag`: T2-weighted turbo spin echo, sagittal plane (standard for spinal discs).
*   `t2_tse_tra`: T2-weighted turbo spin echo, transverse/axial plane.
*   `t1_tse_sag`: T1-weighted turbo spin echo, sagittal plane.
*   `t2_tse_cor`: T2-weighted turbo spin echo, coronal plane.

## 4. Vector Logic
Visual features are extracted via ResNet-18 and stored in the native `VECTOR(512)` type. 
*   **Distance Metric:** `cosine` (Cosine Similarity).
*   **Syntax:** Use `VECTOR_DISTANCE` for similarity ranking.
*   **Query Template:**
    ```sql
    DECLARE @TargetVector VECTOR(512);
    SELECT @TargetVector = Embedding FROM MRIImages WHERE ImageID = 'GUID_HERE';

    SELECT TOP 5 ImageID, VECTOR_DISTANCE('cosine', Embedding, @TargetVector) AS Distance
    FROM MRIImages
    ORDER BY Distance ASC;
    ```
*   **Implementation Note:** Ingestion requires casting JSON arrays: `CAST(? AS VECTOR(512))`.

## 5. Join Patterns
To link clinical findings with visual similarity results, use the `PatientID` foreign key:
```sql
SELECT 
    p.PatientID, 
    p.ClinicalNotes, 
    i.SeriesType, 
    i.ImageID
FROM Patients p
INNER JOIN MRIImages i ON p.PatientID = i.PatientID
WHERE p.ClinicalNotes LIKE '%herniation%'
  AND i.SeriesType = 't2_tse_sag';
```

## 6. Edge Case Handling
*   **Multiline Text:** `ClinicalNotes` is `NVARCHAR(MAX)` and may contain line breaks or non-standard characters from radiologist reports.
*   **One-to-Many Relationship:** A single `PatientID` is associated with hundreds of `ImageID` entries (slices), often across different `SeriesType` groups.
*   **Binary Storage:** `ImageData` contains raw `VARBINARY(MAX)` DICOM pixel data; ensure proper buffer handling when reconstructing images in Python.
