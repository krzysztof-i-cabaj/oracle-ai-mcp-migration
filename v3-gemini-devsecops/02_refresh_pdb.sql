-- ==============================================================================
-- Tytuł:        02_refresh_pdb.sql
-- Opis/Description:  
--       [PL] Klonuje HR_PDB z CDB2 do CDB1. Nadpisuje istniejącą PDB.
--            Po sklonowaniu tworzy dedykowany serwis hr_pdb_cdb1.
--            Bezpieczne przy pierwszym uruchomieniu (brak HR_PDB na CDB1)
--            i przy kolejnych (nadpisanie istniejącej).
--       [EN] Clones HR_PDB from CDB2 to CDB1. Overwrites existing PDB.
--            Creates dedicated service hr_pdb_cdb1 after cloning.
--            Safe on first run (no HR_PDB on CDB1) and on re-runs.
--
-- Autor:        KCB Kris
-- Data:         2026-02-22
-- Wersja/Version:       1.3
--
-- Wymagania/Requirements:    - Wykonywane na CDB1 (jako SYSDBA)
--               - Istniejący DB_LINK CLONE_LINK wskazujący na CDB2
--
-- Użycie/Usage:        @02_refresh_pdb.sql
-- ==============================================================================

-- [PL] Zatrzymanie i usunięcie starej bazy HR_PDB na CDB1 (jeśli istnieje)
-- [EN] Stop and drop old HR_PDB on CDB1 (if exists)
DECLARE
    v_count NUMBER;
BEGIN
    SELECT COUNT(*) INTO v_count
    FROM cdb_pdbs
    WHERE pdb_name = 'HR_PDB';

    IF v_count > 0 THEN
        EXECUTE IMMEDIATE 'ALTER PLUGGABLE DATABASE hr_pdb CLOSE IMMEDIATE';
        EXECUTE IMMEDIATE 'DROP PLUGGABLE DATABASE hr_pdb INCLUDING DATAFILES';
        DBMS_OUTPUT.PUT_LINE('[OK] HR_PDB usunieta.');
    ELSE
        DBMS_OUTPUT.PUT_LINE('[INFO] HR_PDB nie istnieje - pomijam DROP.');
    END IF;
END;
/

-- [PL] Utworzenie nowej bazy jako klon z CDB2 przez DB Link (Hot Clone)
-- [EN] Create new database as a clone from CDB2 via DB Link (Hot Clone)
CREATE PLUGGABLE DATABASE hr_pdb FROM hr_pdb@clone_link;

-- [PL] Otwarcie nowej bazy
-- [EN] Open the new database
ALTER PLUGGABLE DATABASE hr_pdb OPEN;

-- [PL] Przejście do kontekstu sklonowanej PDB i utworzenie dedykowanego serwisu
-- [EN] Switch to cloned PDB context and create dedicated service
ALTER SESSION SET CONTAINER = hr_pdb;

BEGIN
    BEGIN
        DBMS_SERVICE.STOP_SERVICE('hr_pdb_cdb1');
        DBMS_SERVICE.DELETE_SERVICE('hr_pdb_cdb1');
    EXCEPTION
        WHEN OTHERS THEN NULL;
    END;

    DBMS_SERVICE.CREATE_SERVICE('hr_pdb_cdb1', 'hr_pdb_cdb1');
    DBMS_SERVICE.START_SERVICE('hr_pdb_cdb1');
    DBMS_OUTPUT.PUT_LINE('[OK] Serwis hr_pdb_cdb1 uruchomiony.');
END;
/

-- [PL] Powrót do CDB1 root i zapisanie stanu PDB
-- [EN] Return to CDB1 root and save PDB state
ALTER SESSION SET CONTAINER = CDB$ROOT;

ALTER PLUGGABLE DATABASE hr_pdb SAVE STATE;

PROMPT ============================================================
PROMPT [OK] Klonowanie zakonczone. Polacz sie przez:
PROMPT      sqlplus system/haslo@HR_PDB_CDB1
PROMPT      lub: localhost:1521/hr_pdb_cdb1
PROMPT ============================================================
