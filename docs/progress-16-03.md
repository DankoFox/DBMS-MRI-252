### Member 1: The Performance Architect (Indexing & Query Processing)
**Focus:** Criteria 1 & 2 - Khang
*   **Tasks:**
    *   Run the `Indexing` section of `sql/03_demos.sql`. Capture screenshots of "Logical Reads" (Theory: I/O cost) to prove the index works.
    *   Open the **Actual Execution Plan** in SSMS for the Vector Search.
    *   **Theory vs. Practice:** Compare standard B-Tree indexing (class theory) with the **DiskANN** vector index used in SQL Server 2025. Explain how "Cost-Based Optimization" works when the "cost" involves high-dimensional vector math.

### Member 2: The Reliability Engineer (Transactions & Concurrency)
**Focus:** Criteria 3 & 4 - Khánh
*   **Tasks:**
    *   Prepare the `Transaction` demo. Be ready to explain how `ROLLBACK` ensures Atomicity in a medical context (no partial uploads).
    *   Set up the **Concurrency** demo. You will need to manage two simultaneous SSMS windows to show "Blocking" vs. "Snapshot Isolation (RCSI)."
    *   **Theory vs. Practice:** Compare the "Strict Two-Phase Locking" (Theory) with SQL Server's **Row-level Versioning/RCSI** (Practice). Explain why a hospital cannot afford to have a "Read" blocked by a "Write."

### Member 3: The Technical Lead & Integration Specialist (App & Visuals)
**Focus:** Visual Demo & Technical Integration - Khoa
*   **Tasks:**
    *   Own the `src/vector_search_app.py`. Ensure it runs smoothly on the presentation laptop.
    *   Verify the `.env` configuration and ensure the `ingest.py` has loaded enough data to make the "Distinct Patients" logic look impressive.
    *   **Theory vs. Practice:** Explain the bridge between the **Relational Model** (Patient metadata) and the **Vector Model** (Image embeddings) and how SQL Server 2025 treats vectors as a "First Class" data type.

### Member 4: The Communications Lead & Editor (Report & Presentation)
**Focus:** Criteria 5 & 6 - Ngô Nhật Tuấn
*   **Tasks:**
    *   **Final Report:** Consolidate the screenshots and findings from Members 1 & 2 into the final document.
    *   **Presentation Slides:** Create a 30-minute slide deck. (Suggestion: 5 mins Intro, 15 mins Live Demos, 5 mins Theory vs. Practice, 5 mins Q&A).
    *   **Q&A Preparation:** Anticipate questions like "Why use SQL Server for vectors instead of Pinecone/Milvus?" (Answer: ACID compliance and joining with clinical data).

---

### What needs to be done from this stage (Action Plan):

1.  **Dry Run (Crucial):** 30 minutes is a *long* time for a demo. You need to practice the transition between the Python Visualizer and the SQL Server Management Studio (SSMS) scripts.
2.  **Theory vs. Practice Document:** Create a table for your report and slides that looks like this:

| DBMS Concept | Theory (Class) | Practice (This Project) |
| :--- | :--- | :--- |
| **Indexing** | B-Trees for sorted values. | **DiskANN** for high-dimensional proximity search. |
| **Optimization** | Selectivity/Cardinality. | **Vector Distance** operators in the Execution Plan. |
| **Concurrency** | Locking (Wait for lock). | **RCSI (Snapshot)** - Reads never block Writes. |
| **Storage** | Fixed-size records. | `VARBINARY(MAX)` for blobs + `VECTOR(512)` for AI features. |

3.  **Visual Polish:** Ensure the `vector_search_app.py` has a few "different" patient results ready to show. If all results look too similar, the demo is less impressive.
4.  **Final Report:** Use the `docs/assessment_guide.md` I created as your outline. Expand each section with the "Theory vs. Practice" comparison mentioned above.
