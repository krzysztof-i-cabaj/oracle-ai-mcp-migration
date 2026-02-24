# 📋 Plan Działania: Klonowanie i Maskowanie Bazy HR_PDB

![Oracle Version](https://img.shields.io/badge/Oracle-26ai%2023.26.1.0.0-red)
![Source](https://img.shields.io/badge/Źródło-CDB2%20→%20CDB1-blue)
![PDB](https://img.shields.io/badge/PDB-HR__PDB-orange)
![Security](https://img.shields.io/badge/GDPR-Data%20Masking%20PII-brightgreen)
![Status](https://img.shields.io/badge/Status-Plan%20Agenta%20AI-blueviolet)

---

Dokładna sekwencja komend SQL do wykonania w celu sklonowania bazy `HR_PDB` z instancji `CDB2` do `CDB1`, utworzenia serwisu i zmaskowania wrażliwych danych.

> 📝 **Dokument wygenerowany autonomicznie przez Agenta AI (Gemini 3 Pro / Antigravity)**
> przed przystąpieniem do jakichkolwiek działań na bazie danych.
> Wykonanie nastąpiło po zatwierdzeniu przez użytkownika komendą: `wykonaj`

---

## 🗑️ Krok 1 — Usunięcie istniejącej bazy HR_PDB na CDB1 (jeśli istnieje)

Połącz się z instancją `CDB1` (użytkownik SYS / SYSTEM):

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

## 🔁 Krok 2 — Klonowanie bazy z CDB2 do CDB1

Do klonowania konieczny jest Database Link z `CDB1` do `CDB2`. Zakładając obecność autoryzowanego dblink o nazwie `clone_link_cdb2` (jeśli go nie ma, zostanie on najpierw wygenerowany z odpowiednim hasłem usera SYSTEM / C##CLONE_USER):

```sql
-- Jeśli brak dblink (wymaga uzupełnienia o prawdziwe hasło SYSTEM):
-- CREATE DATABASE LINK clone_link_cdb2 CONNECT TO system IDENTIFIED BY <hasło> USING 'cdb2';

CREATE PLUGGABLE DATABASE HR_PDB FROM HR_PDB@clone_link_cdb2;
```

---

## 🔓 Krok 3 — Otwarcie bazy i zachowanie stanu w CDB1

Baza musi zostać uruchomiona i zapisana w stanie `OPEN`, tak by po ewentualnym restarcie całego serwera/CDB1 podnosiła się powtórnie:

```sql
ALTER PLUGGABLE DATABASE HR_PDB OPEN;
ALTER PLUGGABLE DATABASE HR_PDB SAVE STATE;
```

---

## 🛠️ Krok 4 — Utworzenie i włączenie serwisu `hr_pdb_cdb1`

Komendy wykonujemy wewnątrz PDB dla nowo powstałego serwisu na CDB1:

```sql
ALTER SESSION SET CONTAINER = HR_PDB;

EXEC DBMS_SERVICE.CREATE_SERVICE(
    service_name => 'hr_pdb_cdb1',
    network_name => 'hr_pdb_cdb1'
);
EXEC DBMS_SERVICE.START_SERVICE('hr_pdb_cdb1');

-- Wyzwalacz zapewniający automatyczny start serwisu przy każdym uruchomieniu PDB
CREATE OR REPLACE TRIGGER hr_pdb_service_trg
  AFTER STARTUP ON DATABASE
BEGIN
  DBMS_SERVICE.START_SERVICE('hr_pdb_cdb1');
END;
/
```

---

## 🛡️ Krok 5 — Maskowanie wrażliwych danych w schemacie HR

Zidentyfikowano tabelę `HR.EMPLOYEES` zawierającą dane Personal Identifiable Information (PII) oraz finansowe.

**🔒 Wrażliwe kolumny do zamaskowania:**

| Kolumna | Typ danych | Metoda maskowania |
|---|---|---|
| 📧 `EMAIL` | VARCHAR2 | Losowy 10-znakowy ciąg + `@example.com` |
| 📞 `PHONE_NUMBER` | VARCHAR2 | Stały prefix `555-` + losowe 7 cyfr |
| 💰 `SALARY` | NUMBER | Losowa wartość z zakresu 3 000–15 000 |
| 📊 `COMMISSION_PCT` | NUMBER | Zastąpione wartością `NULL` |
| 👤 `FIRST_NAME` | VARCHAR2 | Losowy 6-znakowy ciąg alfanumeryczny |
| 👤 `LAST_NAME` | VARCHAR2 | Losowy 7-znakowy ciąg alfanumeryczny |

```sql
ALTER SESSION SET CONTAINER = HR_PDB;

-- 📞 Maskowanie numeru telefonu: Format 555-XXXXXXX
UPDATE HR.EMPLOYEES
SET PHONE_NUMBER = '555-' || TRUNC(DBMS_RANDOM.VALUE(1000000, 9999999));

-- 📧 Maskowanie adresu e-mail: losowy 10-znakowy ciąg z poprawną domeną
UPDATE HR.EMPLOYEES
SET EMAIL = DBMS_RANDOM.STRING('U', 10) || '@example.com';

-- 💰 Maskowanie wynagrodzenia: zakres 3 000–15 000
UPDATE HR.EMPLOYEES
SET SALARY = ROUND(DBMS_RANDOM.VALUE(3000, 15000), 2);

-- 📊 Maskowanie premii: ukrycie wartości jako NULL
UPDATE HR.EMPLOYEES
SET COMMISSION_PCT = NULL;

-- 👤 Maskowanie imion i nazwisk: uniemożliwienie identyfikacji osób
UPDATE HR.EMPLOYEES
SET FIRST_NAME = DBMS_RANDOM.STRING('U', 1) || DBMS_RANDOM.STRING('L', 5),
    LAST_NAME  = DBMS_RANDOM.STRING('U', 1) || DBMS_RANDOM.STRING('L', 6);

COMMIT;
```

---

## ✅ Potwierdzenie struktury przed uruchomieniem

> 👤 Po zatwierdzeniu tego planu przez użytkownika Agent przystąpi do wykonania
> powyższej sekwencji kroków na środowisku produkcyjnym przy użyciu narzędzi MCP.
