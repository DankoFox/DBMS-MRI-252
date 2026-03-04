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

# Configuration
DB_CONN = "DRIVER={ODBC Driver 18 for SQL Server};SERVER=localhost;DATABASE=MRIDatabase;UID=sa;PWD=YourStrongPassword123!;Encrypt=no"

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
DATA_PATH = os.path.join(BASE_DIR, "..", "data", "01_MRI_Data")
EXCEL_PATH = os.path.join(BASE_DIR, "..", "data", "Radiologists Report.xlsx")

# Load AI Model (ResNet18) for Feature Extraction
# Using weights=ResNet18_Weights.DEFAULT is the modern way to load pretrained models
from torchvision.models import ResNet18_Weights

base_model = models.resnet18(weights=ResNet18_Weights.DEFAULT)
# We take everything EXCEPT the last fully connected layer (fc)
model = torch.nn.Sequential(*(list(base_model.children())[:-1]))
model.eval()

preprocess = transforms.Compose(
    [
        transforms.Resize(256),
        transforms.CenterCrop(224),
        transforms.ToTensor(),
        transforms.Normalize(mean=[0.485, 0.456, 0.406], std=[0.229, 0.224, 0.225]),
    ]
)


def get_vector(pixel_array):
    img = Image.fromarray(pixel_array).convert("RGB")
    tensor = preprocess(img).unsqueeze(0)
    with torch.no_grad():
        # output is [1, 512, 1, 1], so we flatten to [512]
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

    # Load Excel Reports
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

            # 2. FIXED MEMORY: Process in sub-batches of 25 slices
            image_batch = []
            for root, _, files in os.walk(p_path):
                ima_files = [f for f in files if f.endswith(".ima")]
                for f in ima_files:
                    ds = pydicom.dcmread(os.path.join(root, f))
                    vec_json = json.dumps(get_vector(ds.pixel_array))

                    image_batch.append(
                        (
                            p_id,
                            getattr(ds, "SeriesDescription", "Unknown"),
                            int(getattr(ds, "InstanceNumber", 0)),
                            ds.PixelData,
                            vec_json,
                        )
                    )

                    # Flush batch to DB and clear memory
                    if len(image_batch) >= 25:
                        cursor.executemany(
                            "INSERT INTO MRIImages (PatientID, SeriesType, SliceNumber, ImageData, Embedding) VALUES (?, ?, ?, ?, CAST(? AS VECTOR(512)))",
                            image_batch,
                        )
                        image_batch.clear()  # Free memory

            # Final flush for remaining slices
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
