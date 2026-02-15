# =============================================================================
# Script name: create_cdb_26ai_v3.sh
# Author: KCB Kris
# Description: 
# [PL] Skrypt tworzący struktury CDB1 i CDB2 z poprawnym balansem pamięci 
# dla SGA i wektorów oraz dostosowanym hasłem bezpieczeństwa.
# [EN] Script creating CDB1 and CDB2 structures with correct memory balance 
# for SGA and vectors, and adjusted security password.
# Oracle version: 26ai
# =============================================================================

export ORACLE_HOME=/u01/app/oracle/product/26.0.0/dbhome_1
export PATH=$ORACLE_HOME/bin:$PATH

# [PL] Hasło zgodne ze ścisłą polityką (bez słów 'oracle', 'sys', min 8 znaków)
# [EN] Password compliant with strict policy
DB_PASS="Kcb_Str0ng_Db_Pass_2026!"

echo "=========================================================================="
echo "--- [PL] Tworzenie bazy: CDB1 z HR_PDB / Creating: CDB1 with HR_PDB ---"
echo "=========================================================================="

dbca -silent -createDatabase \
    -templateName General_Purpose.dbc \
    -gdbname CDB1 \
    -sid CDB1 \
    -sysPassword "${DB_PASS}" \
    -systemPassword "${DB_PASS}" \
    -createAsContainerDatabase true \
    -numberOfPDBs 1 \
    -pdbName HR_PDB \
    -pdbAdminPassword "${DB_PASS}" \
    -databaseType MULTIPURPOSE \
    -totalMemory 2560 \
    -useOMF true \
    -storageType FS \
    -datafileDestination "/u01/app/oracle/oradata" \
    -recoveryAreaDestination "/u01/app/oracle/fast_recovery_area" \
    -recoveryAreaSize 12288 \
    -initParams vector_memory_size=256M,optimizer_adaptive_plans=true \
    -ignorePreReqs

echo "=========================================================================="
echo "--- [PL] Tworzenie bazy: CDB2 (Pusta) / Creating: CDB2 (Empty) ---"
echo "=========================================================================="

dbca -silent -createDatabase \
    -templateName General_Purpose.dbc \
    -gdbname CDB2 \
    -sid CDB2 \
    -sysPassword "${DB_PASS}" \
    -systemPassword "${DB_PASS}" \
    -createAsContainerDatabase true \
    -numberOfPDBs 0 \
    -databaseType MULTIPURPOSE \
    -totalMemory 2560 \
    -useOMF true \
    -storageType FS \
    -datafileDestination "/u01/app/oracle/oradata" \
    -recoveryAreaDestination "/u01/app/oracle/fast_recovery_area" \
    -recoveryAreaSize 12288 \
    -initParams vector_memory_size=256M,optimizer_adaptive_plans=true \
    -ignorePreReqs

echo "[SUKCES] Zakończono proces powoływania architektur CDB."

# =============================================================================
# Results interpretation:
# [PL] Wprowadzone zmiany:
# 1. '-totalMemory 2560': Przeszliśmy na twardą alokację 2.5 GB RAM zamiast 
#    procentów. Dzięki temu mechanizm AMM ma gwarancję, że pomieści wektory.
# 2. 'vector_memory_size=256M': Zmniejszyliśmy tymczasowo rozmiar wektorów
#    na czas instalacji, aby dać więcej przestrzeni procesom kategorycznym DBCA.
# 3. '-recoveryAreaSize 12288': Ustawiono FRA na 12 GB, co likwiduje ostrzeżenie [DBT-06801].
# [EN] Implemented changes: hard limit on memory (2560MB), lowered vector memory 
# temporarily to 256M to ensure DBCA completion, and increased FRA to 12GB.
# =============================================================================
