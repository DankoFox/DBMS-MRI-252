# Technical Report: Transaction Processing & ACID Compliance
**Project:** DBMS MRI Management System  
**Date:** April 15, 2026  

---

## 1. Introduction & Environment
This report evaluates the transaction processing capabilities of SQL Server 2025 as applied to the MRI DBMS project. The goal is to verify that the system adheres to the theoretical **ACID properties** (Atomicity, Consistency, Isolation, Durability) and the **Write-Ahead Logging (WAL)** protocol defined in *Elmasri & Navathe (Chapter 4)*.

**Environment Setup:**
- **DBMS:** Microsoft SQL Server 2025
- **Driver:** mssql-tools18 (sqlcmd)
- **Tables:** `Patients` (Primary), `MRIImages` (Secondary/FK)

---

## 2. Methodology & Demos

### B1. Basic Transaction — COMMIT (Durability)
**Objective:** Verify that a committed transaction survives system restarts and is permanently stored.

**Query (Demo 1):**
```sql
BEGIN TRANSACTION;
    INSERT INTO Patients (PatientID, ClinicalNotes)
    VALUES (9999, N'Demo transaction: disc herniation at L4-L5');
    INSERT INTO MRIImages (PatientID, SeriesType, SliceNumber, ImageData)
    VALUES (9999, N't2_tse_sag', 1, 0x00);
COMMIT TRANSACTION;
```

**Result:**
| RecordType | PatientID | ClinicalNotes |
| :--- | :--- | :--- |
| Patient | 9999 | Demo transaction: disc herniation at L4-L5 |

**Theory Analysis:** Transition from **Active** to **Committed**. Durability is guaranteed because SQL Server ensures log records are on disk before acknowledging the commit.

---

### B2. ROLLBACK — Atomicity
**Objective:** Prove the "All-or-Nothing" property.

**Query (Demo 2):**
```sql
BEGIN TRANSACTION;
    INSERT INTO Patients (PatientID, ClinicalNotes)
    VALUES (8888, N'This patient should NOT exist after rollback');
ROLLBACK TRANSACTION;
```

**Result:**
- **Inside Transaction:** Row 8881 is found (Visible)
- **After Rollback:** 0 Rows Found (Atomicity Proven)

**Theory Analysis:** The transaction transitioned **Active → Failed → Terminated**. Atomicity ensures that zero partial data remains in the database.

---

### B3. SAVEPOINT — Partial Rollback
**Objective:** Demonstrate the ability to undo specific operations without aborting the entire transaction.

**Query (Demo 3):**
```sql
BEGIN TRANSACTION;
    INSERT INTO Patients (PatientID, ClinicalNotes) VALUES (7777, N'Savepoint demo...');
    SAVE TRANSACTION SP_AfterPatient;
    INSERT INTO MRIImages (PatientID, SeriesType, SliceNumber, ImageData) VALUES (7777, N't2...', 1, 0x00);
    ROLLBACK TRANSACTION SP_AfterPatient; 
COMMIT;
```

**Result:**
- **Patients Table:** Row 7777 persists.
- **MRIImages Table:** 0 rows (successfully rolled back to savepoint).

**Theory Analysis:** Maps to the textbook concept of "Partial Undo." Allows for flexible error recovery in application logic.

---

### B4. Error Handling (XACT_STATE)
**Objective:** Observe the transition to an "Uncommittable" state during a constraint violation.

**Query (Demo 4):**
```sql
BEGIN TRY
    BEGIN TRANSACTION;
        -- 9999 already exists from Demo 1
        INSERT INTO Patients (PatientID, ClinicalNotes) VALUES (9999, N'Duplicate!');
    COMMIT;
END TRY
BEGIN CATCH
    SELECT XACT_STATE() AS State, ERROR_MESSAGE() AS Msg;
    IF XACT_STATE() = -1 ROLLBACK TRANSACTION;
END CATCH;
```

**Result:**
| State | Msg |
| :--- | :--- |
| -1 | Violation of PRIMARY KEY constraint 'PK__Patients...' |

**Theory Analysis:** State `-1` maps to the **Failed** state in theory. The DBMS protects consistency by prohibiting any further writes until a rollback occurs.

---

### B5. Implicit vs. Explicit Transactions
**Objective:** Contrast the SQL2 standard (Implicit) with the SQL Server extension (Explicit).

**Query (Demo 5):**
```sql
SET IMPLICIT_TRANSACTIONS ON;
INSERT INTO Patients (PatientID, ClinicalNotes) VALUES (5555, N'Implicit demo');
SELECT @@TRANCOUNT AS [TranCount]; -- Auto-starts transaction
ROLLBACK;
SET IMPLICIT_TRANSACTIONS OFF;
```

**Result:**
| TranCount | Mode |
| :--- | :--- |
| 1 | Implicit |

---

### B6. Transaction Log — WAL in Practice
**Objective:** Use surgical log inspection to trace the precise lifecycle of a single transaction.

**Query (Demo 6):**
```sql
-- Filtering the log by the specific Transaction ID of a fresh insert
SELECT Operation, TheoryMapping 
FROM sys.fn_dblog(NULL, NULL) 
WHERE [Transaction ID] = @MyTranID;
```

**Result (Lifecycle):**
1. `LOP_BEGIN_XACT` &rarr; `[start_transaction, T]`
2. `LOP_INSERT_ROWS` &rarr; `[write_item, T, X]`
3. `LOP_COMMIT_XACT` &rarr; `[commit, T]`

**Theory Analysis:** Direct evidence of the **Write-Ahead Logging (WAL)** protocol. The log maintains a sequence of events that allows for both Undo (rollback) and Redo (recovery).

---

### B7. Transaction States Mapping
**Objective:** Map runtime `XACT_STATE()` values to the theoretical state diagram (Elmasri Ch 4, Slide 17).

**Result:**
| XACT_STATE() | Theoretical State | SQL Server Status |
| :--- | :--- | :--- |
| **1** | **ACTIVE** | Committable transaction. |
| **-1** | **FAILED** | Doomed transaction (error encountered). |
| **0** | **TERMINATED** | No active transaction context. |

---

### B8. Isolation Levels & Read Phenomena
**Objective:** Empirically demonstrate how isolation levels prevent or allow concurrency anomalies.

**Simulation Results:**
| Isolation Level | Phenomenon | Result |
| :--- | :--- | :--- |
| **READ UNCOMMITTED** | Dirty Read | **Allowed** (sees uncommitted data) |
| **READ COMMITTED** | Dirty Read | **Prevented** (Reader blocks/waits for commit) |
| **REPEATABLE READ** | Non-repeatable Read | **Prevented** (Holds row locks until commit) |
| **SERIALIZABLE** | Phantom Read | **Prevented** (Range locks block new inserts) |

---

## 3. Final Comparison: Theory vs. Practice

| Aspect | Theory (Elmasri Ch. 4) | SQL Server 2025 Practice |
| :--- | :--- | :--- |
| **Transaction Definition** | Logical unit of DB processing. | `BEGIN TRAN` ... `COMMIT/ROLLBACK`. |
| **ACID - Atomicity** | All or nothing execution. | `ROLLBACK` / `XACT_ABORT` + `TRY/CATCH`. |
| **ACID - Consistency** | DB moves between valid states. | PK/FK/Check Constraints. |
| **ACID - Isolation** | Appearance of serial execution. | 5 Levels (READ UNCOMMITTED -> SERIALIZABLE). |
| **ACID - Durability** | Committed changes are permanent. | WAL (.ldf file) ensures persistence. |
| **System Log** | `[write_item, T, X, old, new]` | `sys.fn_dblog()`: `LOP_MODIFY_ROW`, etc. |
| **Recovery** | Undo/Redo Log analysis. | ARIES-based recovery (Analysis/Redo/Undo). |

---
## 4. Conclusion
The experimental results confirm that SQL Server 2025 provides robust transaction support that aligns perfectly with the relational database theory. The implementation of **Write-Ahead Logging** and the **Strict 2-Phase Locking** (implied by higher isolation levels) ensures data integrity for the MRI DBMS dataset.
