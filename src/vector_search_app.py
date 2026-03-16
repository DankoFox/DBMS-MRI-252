import pyodbc
import numpy as np
import matplotlib.pyplot as plt
import os
from dotenv import load_dotenv

# Load connection settings
load_dotenv()
DB_DRIVER = os.getenv('DB_DRIVER', 'ODBC Driver 18 for SQL Server')
DB_SERVER = os.getenv('DB_SERVER', 'localhost')
DB_NAME = os.getenv('DB_NAME', 'MRIDatabase')
DB_USER = os.getenv('DB_USER', 'sa')
DB_PWD = os.getenv('DB_PWD', 'YourStrongPassword123!')

def get_conn():
    conn_str = f"DRIVER={{{DB_DRIVER}}};SERVER={DB_SERVER};DATABASE={DB_NAME};UID={DB_USER};PWD={DB_PWD};Encrypt=no;TrustServerCertificate=yes"
    return pyodbc.connect(conn_str)

def plot_mri(ax, binary_data, title):
    # Standard DICOM size for this project (320x320)
    # Note: Adjust reshape if your DICOMs vary in resolution
    try:
        img = np.frombuffer(binary_data, dtype=np.uint16)
        # Handle cases where pixel data might be slightly different lengths
        side = int(np.sqrt(img.size))
        img = img[:side*side].reshape((side, side))
        ax.imshow(img, cmap="gray")
    except Exception as e:
        ax.text(0.5, 0.5, f"Error: {e}", ha='center')
    ax.set_title(title, fontsize=10)
    ax.axis("off")

def run_visual_demo():
    print("🔍 Connecting to DBMS for Visual Similarity Search...")
    conn = get_conn()
    cursor = conn.cursor()

    # 1. Select a random slice to act as our "Query"
    cursor.execute("SELECT TOP 1 ImageID, ImageData, SeriesType, PatientID FROM MRIImages WHERE Embedding IS NOT NULL ORDER BY NEWID()")
    query_row = cursor.fetchone()
    if not query_row:
        print("❌ No images found with embeddings. Did you run ingest.py?")
        return

    query_id, query_img, query_series, query_pid = query_row
    print(f"✅ Target Selected: Patient {query_pid} | Series: {query_series}")

    # 2. Perform Native Vector Similarity Search (The Query Processing Demo)
    # We use a CTE to get the vector and then join for results
    search_sql = """
    DECLARE @TargetVector VECTOR(512);
    SELECT @TargetVector = Embedding FROM MRIImages WHERE ImageID = ?;

    SELECT TOP 3 
        ImageID, 
        ImageData, 
        SeriesType, 
        PatientID,
        VECTOR_DISTANCE('cosine', Embedding, @TargetVector) AS Distance
    FROM MRIImages
    WHERE ImageID != ?
    ORDER BY Distance ASC;
    """
    
    cursor.execute(search_sql, query_id, query_id)
    results = cursor.fetchall()

    # 3. Visualization
    fig, axes = plt.subplots(1, 4, figsize=(16, 4))
    
    # Plot Query Image
    plot_mri(axes[0], query_img, f"QUERY IMAGE\n(Patient {query_pid})")
    axes[0].patch.set_edgecolor('red')  
    axes[0].patch.set_linewidth(3)  

    # Plot Matches
    for i, res in enumerate(results):
        res_id, res_img, res_series, res_pid, dist = res
        plot_mri(axes[i+1], res_img, f"MATCH #{i+1} (Dist: {dist:.4f})\nPatient {res_pid}")

    plt.tight_layout()
    print("📈 Displaying similarity results. Close the window to finish.")
    plt.show()

if __name__ == "__main__":
    run_visual_demo()
