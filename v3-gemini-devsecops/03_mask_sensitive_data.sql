-- ==============================================================================
-- Tytuł:        03_mask_sensitive_data.sql
-- Opis/Description:  
--       [PL] Anonimizuje i maskuje dane wrażliwe w HR_PDB w środowisku testowym.
--       [EN] Anonymizes and masks sensitive data in HR_PDB in test environment.
--
-- Autor:        KCB Kris
-- Data:         2026-02-22
-- Wersja/Version:       1.1
--
-- Wymagania/Requirements:    - Wykonywane na CDB1 / HR_PDB (klon z CDB2)
--               - Użytkownik z uprawnieniami UPDATE na hr.employees
--
-- Użycie/Usage:        @03_mask_sensitive_data.sql
-- ==============================================================================

DECLARE
    v_start_time NUMBER;
    v_count      NUMBER;
BEGIN
    v_start_time := DBMS_UTILITY.GET_TIME;

    -- [PL] Anonimizacja tabeli employees (klon CDB2 -> CDB1/HR_PDB)
    -- [EN] Anonymization of employees table (clone CDB2 -> CDB1/HR_PDB)
    UPDATE hr.employees e
    SET
        -- 1. Imię i nazwisko
        first_name   = INITCAP(DBMS_RANDOM.STRING('L', 6)),
        last_name    = INITCAP(DBMS_RANDOM.STRING('L', 8)),

        -- 2. E-mail (lowercase + domena testowa)
        email        = LOWER(DBMS_RANDOM.STRING('A', 8)) || '@masked-hr.com',

        -- 3. Numer telefonu (zachowanie prefiksu, maskowanie końcówki)
        phone_number = SUBSTR(phone_number, 1, 4) || '***.****',

        -- 4. Zarobki: perturbacja +/-15%, ograniczona do zakresu min/max z jobs
        salary       = GREATEST(
                           j.min_salary,
                           LEAST(
                               j.max_salary,
                               ROUND(e.salary * DBMS_RANDOM.VALUE(0.85, 1.15))
                           )
                       )
    FROM hr.jobs j
    WHERE e.job_id = j.job_id;

    v_count := SQL%ROWCOUNT;
    COMMIT;

    DBMS_OUTPUT.PUT_LINE('[PL] Maskowanie zakonczone.');
    DBMS_OUTPUT.PUT_LINE('[PL] Wierszy przetworzonych : ' || v_count);
    DBMS_OUTPUT.PUT_LINE('[PL] Czas                  : ' || (DBMS_UTILITY.GET_TIME - v_start_time)/100 || ' sek.');
    DBMS_OUTPUT.PUT_LINE('[EN] Masking completed.');
    DBMS_OUTPUT.PUT_LINE('[EN] Rows processed        : ' || v_count);
    DBMS_OUTPUT.PUT_LINE('[EN] Time                  : ' || (DBMS_UTILITY.GET_TIME - v_start_time)/100 || ' sec.');
END;
/

-- [PL] Przebudowa indeksu na kolumnie email (istnieje w standardowym schemacie HR)
-- [EN] Rebuild index on email column (exists in standard HR schema)
ALTER INDEX hr.emp_email_uk REBUILD;