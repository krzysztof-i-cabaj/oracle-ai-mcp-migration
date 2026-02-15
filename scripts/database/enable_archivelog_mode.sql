-- =============================================================================
-- Script name: enable_archivelog_mode.sql
-- Author: KCB Kris
-- Description: 
-- [PL] Bezpieczne przełączenie instancji w tryb ARCHIVELOG i start ARCn.
-- [EN] Safely switching the instance to ARCHIVELOG mode and starting ARCn.
-- Oracle version: 26ai
-- =============================================================================

-- [PL] 1. Wyczyszczenie buforów i czyste zamknięcie bazy
-- [EN] 1. Buffer flush and clean database shutdown
SHUTDOWN IMMEDIATE;

-- [PL] 2. Uruchomienie do odczytu pliku kontrolnego (Control File)
-- [EN] 2. Startup to read the Control File
STARTUP MOUNT;

-- [PL] 3. Modyfikacja bitu archiwizacji w nagłówkach i Control File
-- [EN] 3. Modification of archivelog bit in headers and Control File
ALTER DATABASE ARCHIVELOG;

-- [PL] 4. Otwarcie plików danych
-- [EN] 4. Opening datafiles
ALTER DATABASE OPEN;

-- [PL] 5. Weryfikacja przydziału FRA (Fast Recovery Area)
-- [EN] 5. Verification of FRA allocation
ARCHIVE LOG LIST;

-- =============================================================================
-- Results interpretation:
-- [PL] Oczekujemy wyniku:
-- Database log mode: Archive Mode
-- Automatic archival: Enabled
-- Archive destination: USE_DB_RECOVERY_FILE_DEST
-- Co oznacza, że logi są bezpiecznie kierowane do FRA (12 GB), które 
-- skonfigurowaliśmy w skrypcie DBCA.
-- [EN] Expected result: Archive Mode, Enabled, USE_DB_RECOVERY_FILE_DEST.
-- =============================================================================
