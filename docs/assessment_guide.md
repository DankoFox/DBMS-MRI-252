# 📋 Assessment Strategy & Demo Guide: DBMS-MRI-252

This document outlines the strategy for satisfying the 6 assessment criteria. All SQL scripts for these demos are located in `sql/03_demos.sql`.

---

## 0. Initial Setup
*   **Environment Variables:** Ensure your `.env` file is configured. The Python scripts (`ingest.py` and `vector_search_app.py`) use these to connect to SQL Server.
*   **Data Ingestion:** Run `src/ingest.py` first to populate the database with images and ResNet-18 embeddings.

## 1. Indexing (2 Points)
*   **Goal:** Demonstrate the performance gain of using indexes.
*   **Demo Action:** 
    1.  Run a query on `SeriesType` without an index.
    2.  Show the "Logical Reads" in the Messages tab (`SET STATISTICS IO ON`).
    3.  Create an index on `SeriesType`.
    4.  Run the query again and show the drastic reduction in Logical Reads (e.g., from 1000+ reads to < 10).
*   **Key Talking Point:** "Indexes transform an $O(n)$ Table Scan into an $O(\log n)$ Index Seek, significantly reducing I/O costs."

## 2. Query Processing (2 Points)
*   **Goal:** Show how the DBMS parses and executes complex queries (Vector + Relational).
*   **Demo Action:** 
    1.  Execute the Similarity Search query in SQL Server Management Studio (SSMS).
    2.  Enable the **Actual Execution Plan** (Ctrl+M).
    3.  Highlight the `Vector Distance` operator and show how the SQL Optimizer chooses between a scan or a vector index seek (DiskANN).
    4.  **Visual Proof:** Run `python src/vector_search_app.py` to show the application-layer result of the same SQL query.
*   **Key Talking Point:** "SQL Server's Query Optimizer builds an execution plan that balances CPU cost for vector math with I/O cost for fetching image metadata."

## 3. Transactions (2 Points)
*   **Goal:** Demonstrate ACID compliance (specifically Atomicity and Consistency).
*   **Demo Action:** 
    1.  Open a `BEGIN TRANSACTION`.
    2.  Insert a dummy Patient and Image.
    3.  Show they exist in the current session.
    4.  Execute `ROLLBACK`.
    5.  Show that both the Patient and Image records are gone, proving no "partial" data was saved.
*   **Key Talking Point:** "Transactions ensure that if a medical record fails to upload mid-way, we don't end up with 'orphaned' image slices without a patient record."

## 4. Concurrency Control (2 Points)
*   **Goal:** Demonstrate how the DBMS handles simultaneous users (Locking vs. Snapshot Isolation).
*   **Demo Action:** 
    1.  **Session A:** Update a Patient record but do *not* commit.
    2.  **Session B:** Try to read the same Patient record. It will block (wait).
    3.  **Resolution:** Enable `READ_COMMITTED_SNAPSHOT` (RCSI) on the database.
    4.  **Session B:** Run the read again. It now returns the *previous* consistent version without waiting for Session A.
*   **Key Talking Point:** "We use Snapshot Isolation to prevent read/write blocking, allowing radiologists to read old data while new data is being ingested."

---

## 5. Do we need a Frontend?
**Short Answer: No, but a small one helps.**
For a **DBMS assessment**, the examiners care about the *SQL engine*. You should spend 90% of your time in SSMS or Azure Data Studio showing SQL scripts and execution plans.
*   **Keep your Python script:** Use it to show the *result* (e.g., "Look, the top 5 similar images are indeed visually similar").
*   **Frontend Recommendation:** If you want to impress, a 10-line **Streamlit** app to display the SQL query results + images is enough. Don't waste time on a complex UI; focus on the SQL performance.

## 6. Final Report & Presentation Tips
*   **Report:** Include screenshots of the **Execution Plans** and the **Statistics IO** output. This is concrete proof of your DBMS knowledge.
*   **Presentation:** Start with the "Why" (Scaling MRI data for AI). Then, quickly move to the 4 technical demos. End with the Python image viewer to make it "real."
