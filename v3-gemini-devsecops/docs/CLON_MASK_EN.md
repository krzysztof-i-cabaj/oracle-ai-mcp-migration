# 📋 Action Plan: Cloning and Masking HR_PDB

![Oracle Version](https://img.shields.io/badge/Oracle-26ai%2023.26.1.0.0-red)
![Source](https://img.shields.io/badge/Source-CDB2%20→%20CDB1-blue)
![PDB](https://img.shields.io/badge/PDB-HR__PDB-orange)
![Security](https://img.shields.io/badge/GDPR-Data%20Masking%20PII-brightgreen)
![Status](https://img.shields.io/badge/Status-AI%20Agent%20Plan-blueviolet)

---

Exact SQL command sequence to clone the `HR_PDB` database from instance `CDB2` to `CDB1`, create a service, and mask sensitive data.

> 📝 **Document generated autonomously by the AI Agent (Gemini 3 Pro / Antigravity)**
> prior to taking any action on the database.
> Execution commenced after user approval with the command: `wykonaj`

---

## 🗑️ Step 1 — Remove existing HR_PDB on CDB1 (if exists)

Connect to instance `CDB1` (user SYS / SYSTEM):

```sql
DECLARE
  v_count NUMBER;
BEGIN
  SELECT count(*) INTO v_count FROM dba_pdbs WHERE pdb_name = 'HR_PDB';
  IF v_count > 0 THEN
    EXECUTE IMMEDIATE 'ALTER PLUGGABLE DATABASE HR_PDB CLOSE IMMEDIATE';
    EXECUTE IMMEDIATE 'DROP PLUGGABLE DATABASE HR_PDB INCLUDING DATAFILES';
  END IF;
END;
/
```

---

## 🔁 Step 2 — Clone database from CDB2 to CDB1

A Database Link from `CDB1` to `CDB2` is required for cloning. Assuming the presence of an authorized dblink named `clone_link_cdb2` (if not present, it will first be created with the appropriate SYSTEM / C##CLONE_USER password):

```sql
-- If dblink is missing (requires actual password):
-- CREATE DATABASE LINK clone_link_cdb2 CONNECT TO system IDENTIFIED BY <password> USING 'cdb2';

CREATE PLUGGABLE DATABASE HR_PDB FROM HR_PDB@clone_link_cdb2;
```

---

## 🔓 Step 3 — Open database and persist state on CDB1

The database must be started and saved in `OPEN` state so that it automatically reopens after any server/CDB1 restart:

```sql
ALTER PLUGGABLE DATABASE HR_PDB OPEN;
ALTER PLUGGABLE DATABASE HR_PDB SAVE STATE;
```

---

## 🛠️ Step 4 — Create and enable service `hr_pdb_cdb1`

Commands are executed inside the PDB for the newly created service on CDB1:

```sql
ALTER SESSION SET CONTAINER = HR_PDB;

EXEC DBMS_SERVICE.CREATE_SERVICE(
    service_name => 'hr_pdb_cdb1',
    network_name => 'hr_pdb_cdb1'
);
EXEC DBMS_SERVICE.START_SERVICE('hr_pdb_cdb1');

-- Trigger to ensure automatic service start on every PDB startup
CREATE OR REPLACE TRIGGER hr_pdb_service_trg
  AFTER STARTUP ON DATABASE
BEGIN
  DBMS_SERVICE.START_SERVICE('hr_pdb_cdb1');
END;
/
```

---

## 🛡️ Step 5 — Mask sensitive data in HR schema

The `HR.EMPLOYEES` table has been identified as containing Personal Identifiable Information (PII) and financial data.

**🔒 Sensitive columns to be masked:**

| Column | Data Type | Masking Method |
|---|---|---|
| 📧 `EMAIL` | VARCHAR2 | Random 10-char string + `@example.com` |
| 📞 `PHONE_NUMBER` | VARCHAR2 | Fixed prefix `555-` + random 7 digits |
| 💰 `SALARY` | NUMBER | Random value in range 3,000–15,000 |
| 📊 `COMMISSION_PCT` | NUMBER | Replaced with `NULL` |
| 👤 `FIRST_NAME` | VARCHAR2 | Random 6-character alphanumeric string |
| 👤 `LAST_NAME` | VARCHAR2 | Random 7-character alphanumeric string |

```sql
ALTER SESSION SET CONTAINER = HR_PDB;

-- 📞 Phone number masking: Format 555-XXXXXXX
UPDATE HR.EMPLOYEES
SET PHONE_NUMBER = '555-' || TRUNC(DBMS_RANDOM.VALUE(1000000, 9999999));

-- 📧 Email masking: random 10-char string with valid domain
UPDATE HR.EMPLOYEES
SET EMAIL = DBMS_RANDOM.STRING('U', 10) || '@example.com';

-- 💰 Salary masking: range 3,000–15,000
UPDATE HR.EMPLOYEES
SET SALARY = ROUND(DBMS_RANDOM.VALUE(3000, 15000), 2);

-- 📊 Commission masking: hide value as NULL
UPDATE HR.EMPLOYEES
SET COMMISSION_PCT = NULL;

-- 👤 First and last name masking: prevent real-world identification
UPDATE HR.EMPLOYEES
SET FIRST_NAME = DBMS_RANDOM.STRING('U', 1) || DBMS_RANDOM.STRING('L', 5),
    LAST_NAME  = DBMS_RANDOM.STRING('U', 1) || DBMS_RANDOM.STRING('L', 6);

COMMIT;
```

---

## ✅ Structure confirmation before execution

> 👤 Upon user approval, the Agent will proceed to execute the above sequence
> of steps on the target environment using MCP tools.
