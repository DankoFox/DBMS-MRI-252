import pyodbc
import numpy as np
import matplotlib.pyplot as plt
from matplotlib.widgets import Button
import os
from dotenv import load_dotenv

# Load connection settings
load_dotenv()
DB_DRIVER = os.getenv('DB_DRIVER', 'ODBC Driver 18 for SQL Server')
DB_SERVER = os.getenv('DB_SERVER', 'localhost')
DB_NAME = os.getenv('DB_NAME', 'MRIDatabase')
DB_USER = os.getenv('DB_USER', 'sa')
DB_PWD = os.getenv('DB_PWD', 'YourStrongPassword123!')

class MRIVisualizer:
    def __init__(self):
        self.conn = self.get_conn()
        self.cursor = self.conn.cursor()
        self.fig, self.axes = plt.subplots(1, 4, figsize=(16, 5))
        plt.subplots_adjust(bottom=0.2)  # Make room for the button
        
        # Add "Next" Button
        ax_next = plt.axes([0.45, 0.05, 0.1, 0.075])
        self.btn_next = Button(ax_next, 'Next ➡️', color='lightblue', hovercolor='skyblue')
        self.btn_next.on_clicked(self.refresh)
        
        self.refresh(None)

    def get_conn(self):
        conn_str = f"DRIVER={{{DB_DRIVER}}};SERVER={DB_SERVER};DATABASE={DB_NAME};UID={DB_USER};PWD={DB_PWD};Encrypt=no;TrustServerCertificate=yes"
        return pyodbc.connect(conn_str)

    def plot_mri(self, ax, binary_data, title, is_query=False):
        ax.clear()
        try:
            img = np.frombuffer(binary_data, dtype=np.uint16)
            side = int(np.sqrt(img.size))
            img = img[:side*side].reshape((side, side))
            ax.imshow(img, cmap="gray")
            if is_query:
                for spine in ax.spines.values():
                    spine.set_edgecolor('red')
                    spine.set_linewidth(3)
        except Exception as e:
            ax.text(0.5, 0.5, f"Error: {e}", ha='center', va='center')
        
        ax.set_title(title, fontsize=9)
        ax.axis("off")

    def refresh(self, event):
        print("🔄 Fetching new random query and distinct matches...")
        
        # 1. Select random query image
        self.cursor.execute("SELECT TOP 1 ImageID, ImageData, SeriesType, PatientID FROM MRIImages WHERE Embedding IS NOT NULL ORDER BY NEWID()")
        query_row = self.cursor.fetchone()
        
        if not query_row:
            print("❌ No data found.")
            return

        q_id, q_img, q_series, q_pid = query_row

        # 2. SQL for DISTINCT PATIENT similarity search
        # We use ROW_NUMBER() to pick only the best (closest) slice for each unique patient
        search_sql = """
        DECLARE @TargetVector VECTOR(512);
        SELECT @TargetVector = Embedding FROM MRIImages WHERE ImageID = ?;

        WITH PatientMatches AS (
            SELECT 
                ImageID, 
                ImageData, 
                SeriesType, 
                PatientID,
                VECTOR_DISTANCE('cosine', Embedding, @TargetVector) AS Distance,
                ROW_NUMBER() OVER (PARTITION BY PatientID ORDER BY VECTOR_DISTANCE('cosine', Embedding, @TargetVector) ASC) as BestSliceRank
            FROM MRIImages
            WHERE PatientID != ? -- Ensure matches are NOT the query patient
              AND Embedding IS NOT NULL
        )
        SELECT TOP 3 
            ImageID, ImageData, SeriesType, PatientID, Distance
        FROM PatientMatches
        WHERE BestSliceRank = 1 -- Only one slice per patient
        ORDER BY Distance ASC;
        """
        
        self.cursor.execute(search_sql, q_id, q_pid)
        results = self.cursor.fetchall()

        # 3. Update Plots
        self.plot_mri(self.axes[0], q_img, f"QUERY: Patient {q_pid}\n({q_series})", is_query=True)
        
        for i in range(3):
            ax = self.axes[i+1]
            if i < len(results):
                res_id, res_img, res_series, res_pid, dist = results[i]
                self.plot_mri(ax, res_img, f"MATCH #{i+1}: Patient {res_pid}\nDist: {dist:.4f}")
            else:
                ax.clear()
                ax.axis("off")
                ax.set_title("No more matches")

        self.fig.canvas.draw_idle()
        print(f"✅ Displaying similarities for Patient {q_pid}")

def run_visual_demo():
    visualizer = MRIVisualizer()
    plt.show()

if __name__ == "__main__":
    run_visual_demo()
