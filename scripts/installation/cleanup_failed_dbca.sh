# =============================================================================
# Script name: cleanup_failed_dbca.sh
# Author: KCB Kris
# Description: 
# [PL] Skrypt usuwający pozostałości po nieudanej instalacji DBCA.
# [EN] Script removing remnants of a failed DBCA installation.
# Oracle version: 23ai/26ai
# =============================================================================
# Script purpose:
# [PL] Usunięcie osieroconych plików danych, logów i wpisów z oratab.
# [EN] Removal of orphaned datafiles, logs, and oratab entries.
# =============================================================================

echo "--- [PL] Rozpoczynam czyszczenie środowiska / Starting environment cleanup ---"

# [PL] 1. Usunięcie wpisów z /etc/oratab (wymaga praw zapisu, często oracle je ma dla tego pliku)
# [EN] 1. Removing entries from /etc/oratab
sed -i '/^CDB1:/d' /etc/oratab
sed -i '/^CDB2:/d' /etc/oratab

# [PL] 2. Usunięcie osieroconych plików na dysku
# [EN] 2. Removing orphaned files on disk
rm -rf /u01/app/oracle/oradata/CDB1
rm -rf /u01/app/oracle/fast_recovery_area/CDB1
rm -rf /u01/app/oracle/admin/CDB1

# [PL] 3. Usunięcie pozostałości w dbs
# [EN] 3. Removing remnants in dbs
rm -f /u01/app/oracle/product/26.0.0/dbhome_1/dbs/*CDB1*
rm -f /u01/app/oracle/product/26.0.0/dbhome_1/dbs/*CDB2*

echo "--- [SUKCES] Środowisko czyste. Gotowe do ponownej instalacji. ---"
