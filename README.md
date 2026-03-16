# 🏥 MRI DBMS: Intelligent Medical Imaging System

This project demonstrates a high-performance database architecture using **SQL Server 2025** to handle both relational clinical data and high-dimensional AI vector embeddings natively.

---

## 1. Architectural Blueprint

To maximize technical depth, this stack moves beyond simple storage. It leverages **Native Vector Search** to make the database the "intelligent" core of the application.

* **ETL Tier:** Python extracts metadata (`pydicom`) and visual features (`ResNet-18`).
* **Storage Tier:** Images are stored as `VARBINARY(MAX)`; visual features use the new native `VECTOR(512)` type.
* **Logic Tier:** Retrieval and Similarity are handled via **T-SQL**, demonstrating high-level server-side processing.

---

## 2. Repository Structure

```text
MRI_DBMS/
├── data/                # (Git Ignored) MRI folders & Radiologist Excel
├── sql/
│   ├── 01_schema.sql      # Tables & Native Vector definitions
│   ├── 02_indexes.sql     # B-Tree & DiskANN Vector Index demos
│   └── 03_dbms_demos.sql  # Transactions & Concurrency scripts
├── src/
│   ├── ingest.py          # Master ETL (Excel + DICOM + AI)
│   └── app_queries.py     # Python wrappers for Case Studies
├── docker-compose.yml     # SQL Server 2025 Preview Config
├── requirements.txt       # pydicom, pyodbc, torch, torchvision
└── README.md              # Setup & Presentation Guide

```

---

## 3. Infrastructure (Docker & SQL)

### 🐳 docker-compose.yml

The 2025-preview image is required for the native `VECTOR` data type.

```yaml
services:
  sqlserver:
    image: mcr.microsoft.com/mssql/server:2025-preview-latest
    container_name: mri_dbms_sql
    ports:
      - "1433:1433"
    environment:
      - ACCEPT_EULA=Y
      - MSSQL_SA_PASSWORD=YourStrongPassword123!
    volumes:
      - mssql_data:/var/opt/mssql
volumes:
  mssql_data:

```

### 📜 sql/01_schema.sql

```sql
CREATE DATABASE MRIDatabase;
GO
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
    FilePath NVARCHAR(MAX),
    ImageData VARBINARY(MAX),
    -- Native Vector Support (SQL Server 2025)
    Embedding VECTOR(512), 
    CONSTRAINT FK_Patient FOREIGN KEY (PatientID) REFERENCES Patients(PatientID)
);

```

---

## 4. Ingestion Tier (`src/ingest.py`)

This script handles the heavy lifting: parsing Excel, reading DICOM, and generating AI embeddings.

```python
import os
import pydicom
import pyodbc
import openpyxl
import torch
import json
import time
import torchvision.models as models
import torchvision.transforms as transforms
from PIL import Image

DB_CONN = "DRIVER={ODBC Driver 18 for SQL Server};SERVER=localhost;DATABASE=MRIDatabase;UID=sa;PWD=YourStrongPassword123!;Encrypt=no"

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
DATA_PATH = os.path.join(BASE_DIR, "..", "data", "01_MRI_Data")
EXCEL_PATH = os.path.join(BASE_DIR, "..", "data", "Radiologists Report.xlsx")

from torchvision.models import ResNet18_Weights

base_model = models.resnet18(weights=ResNet18_Weights.DEFAULT)
model = torch.nn.Sequential(*(list(base_model.children())[:-1]))
model.eval()

preprocess = transforms.Compose([
    transforms.Resize(256),
    transforms.CenterCrop(224),
    transforms.ToTensor(),
    transforms.Normalize(mean=[0.485, 0.456, 0.406], std=[0.229, 0.224, 0.225]),
])

def get_vector(pixel_array):
    img = Image.fromarray(pixel_array).convert("RGB")
    tensor = preprocess(img).unsqueeze(0)
    with torch.no_grad():
        return model(tensor).flatten().tolist()

def run_etl():
    start_time = time.time()
    print("🚀 Starting Optimized ETL Process...")

    try:
        conn = pyodbc.connect(DB_CONN)
        cursor = conn.cursor()
        cursor.fast_executemany = True
        print("🔗 Database connection established.")
    except Exception as e:
        print(f"❌ Connection failed: {e}")
        return

    wb = openpyxl.load_workbook(EXCEL_PATH)
    notes = {row[0]: row[1] for row in wb.active.iter_rows(min_row=2, values_only=True)}

    patient_folders = [
        f for f in os.listdir(DATA_PATH) if os.path.isdir(os.path.join(DATA_PATH, f))
    ]

    for i, p_folder in enumerate(patient_folders, 1):
        try:
            p_id = int(p_folder)
            print(f"\n--- [{i}/{len(patient_folders)}] Patient ID: {p_id} ---")

            cursor.execute(
                "INSERT INTO Patients (PatientID, ClinicalNotes) VALUES (?, ?)",
                p_id,
                notes.get(p_id),
            )

            p_path = os.path.join(DATA_PATH, p_folder)
            image_batch = []
            for root, _, files in os.walk(p_path):
                ima_files = [f for f in files if f.endswith(".ima")]
                for f in ima_files:
                    ds = pydicom.dcmread(os.path.join(root, f))
                    vec_json = json.dumps(get_vector(ds.pixel_array))

                    image_batch.append((
                        p_id,
                        getattr(ds, "SeriesDescription", "Unknown"),
                        int(getattr(ds, "InstanceNumber", 0)),
                        ds.PixelData,
                        vec_json,
                    ))

                    if len(image_batch) >= 25:
                        cursor.executemany(
                            "INSERT INTO MRIImages (PatientID, SeriesType, SliceNumber, ImageData, Embedding) VALUES (?, ?, ?, ?, CAST(? AS VECTOR(512)))",
                            image_batch,
                        )
                        image_batch.clear()

            if image_batch:
                cursor.executemany(
                    "INSERT INTO MRIImages (PatientID, SeriesType, SliceNumber, ImageData, Embedding) VALUES (?, ?, ?, ?, CAST(? AS VECTOR(512)))",
                    image_batch,
                )

            conn.commit()
            print(f"✅ Patient {p_id} complete.")

        except Exception as e:
            conn.rollback()
            print(f"⚠️ Error: {e}")

    print(f"\n✨ ETL FINISHED in {round((time.time() - start_time) / 60, 2)} minutes.")
    conn.close()

if __name__ == "__main__":
    run_etl()
```

---

## 5. Case Study Demo Scripts

### Case 1 & 2: Relational Retrieval

> Find images for patients with a diagnosed pathology.

```sql
SELECT p.PatientID, i.SeriesType, i.ImageData
FROM Patients p
JOIN MRIImages i ON p.PatientID = i.PatientID
WHERE p.ClinicalNotes LIKE '%herniation%'
  AND i.SeriesType LIKE '%t2_tse_sag%';
```

### Case 3: Native Vector Similarity

> Find the top 5 images visually similar to a specific slice using Cosine Similarity.

```sql
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
```

---

## 6. DBMS Core Criteria Scenarios

| Criterion | Demo Action | SQL / Outcome |
| --- | --- | --- |
| **Indexing** | Search for `SeriesType` without index, then add index. | Compare `SET STATISTICS IO ON` (Table Scan vs. Index Seek). |
| **Query Processing** | View Execution Plan for Case 3. | Show the **Vector Distance** operator in the visual plan. |
| **Transactions** | Rollback a patient ingestion mid-way. | `BEGIN TRAN... ROLLBACK`. Prove no "partial" patient records exist. |
| **Concurrency** | Lock a Patient row in Window A, read in Window B. | Demonstrate blocking, then enable `RCSI` to solve it. |

---

## 7. Presentation & Setup

### Setup Steps

1. **Configure Environment:** Create a `.env` file in the root directory (see `.env` for template) with your SQL Server credentials.
2. **Prepare Data:** Place your MRI DICOM files (`.ima`) in `data/01_MRI_Data/<PatientID>/` folders and the radiologist report Excel file at `data/Radiologists Report.xlsx`.
3. **Start Database:** `docker-compose up -d`
4. **Install Dependencies:** `pip install -r requirements.txt`
5. **Initialize Schema:** Execute `sql/schema.sql` and `sql/indexing.sql` in SSMS or Azure Data Studio.
6. **Load Data:** Run `python src/ingest.py`
7. **Visual Demo:** Run `python src/vector_search_app.py` to see the AI similarity results.

### Presentation Talking Points

* **The "Why" of SQL 2025:** "We aren't just using the DB as storage; we've moved the AI logic into the data layer, reducing the need for heavy application-side math."
* **ACID Compliance:** "By storing images in `VARBINARY`, a `ROLLBACK` removes both metadata and the binary file simultaneously—preventing 'orphaned' image files."
* **Multi-Modal Querying:** "We are combining Clinical Notes (Text) with Visual Embeddings (AI) in a single, high-performance JOIN."
* **Visual Verification:** "The `vector_search_app.py` proves that the DBMS isn't just returning random data; it's returning clinically similar visual slices based on DiskANN vector indexing."

---

### 🛠️ Troubleshooting (Common Errors)

* **Driver Error:** Ensure [Microsoft ODBC Driver 18](https://learn.microsoft.com/en-us/sql/connect/odbc/download-odbc-driver-for-sql-server) is installed.
* **Memory Issues:** SQL Server in Docker requires at least **2GB of RAM**.
* **Ingestion Speed:** ResNet-18 runs on the CPU by default. For demo purposes, keep the dataset small (~5-10 patient folders).

