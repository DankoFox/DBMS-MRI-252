import pyodbc
import numpy as np
import matplotlib.pyplot as plt
import os
from dotenv import load_dotenv

load_dotenv()
conn = pyodbc.connect(
    f"DRIVER={{{os.getenv('DB_DRIVER')}}};"
    f"SERVER={os.getenv('DB_SERVER')};"
    f"DATABASE={os.getenv('DB_NAME')};"
    f"Trusted_Connection={os.getenv('DB_TRUSTED')};"
    f"TrustServerCertificate={os.getenv('DB_CERT')};"
)

cursor = conn.cursor()

cursor.execute("""
SELECT TOP 1 ImageData  FROM MRIImages;
""")

row = cursor.fetchone()
dicom_bytes = row[0]

# reconstruct image
img = np.frombuffer(dicom_bytes, dtype=np.uint16)
img = img.reshape((320, 320))

plt.imshow(img, cmap="gray")
plt.title("MRI Slice from SQL Server")
plt.axis("off")
plt.show()