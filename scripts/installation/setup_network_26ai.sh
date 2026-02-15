# =============================================================================
# Script name: setup_network_26ai.sh
# Author: KCB Kris
# Description: 
# [PL] Skrypt generujący pliki konfiguracyjne warstwy sieciowej (listener.ora, 
# tnsnames.ora) i uruchamiający proces Listenera dla architektury Multitenant.
# [EN] Script generating network configuration files (listener.ora, tnsnames.ora) 
# and starting the Listener process for Multitenant architecture.
# Oracle version: 26ai
# =============================================================================

export ORACLE_HOME=/u01/app/oracle/product/26.0.0/dbhome_1
export PATH=$ORACLE_HOME/bin:$PATH
export TNS_ADMIN=$ORACLE_HOME/network/admin

echo "--- [PL] Generowanie plików sieciowych / Generating network files ---"

# 1. Konfiguracja Listenera (Proces nasłuchujący)
cat > $TNS_ADMIN/listener.ora <<EOF
LISTENER =
  (DESCRIPTION_LIST =
    (DESCRIPTION =
      (ADDRESS = (PROTOCOL = TCP)(HOST = $(hostname))(PORT = 1521))
      (ADDRESS = (PROTOCOL = IPC)(KEY = EXTPROC1521))
    )
  )
EOF

# 2. Konfiguracja TNS (Rozwiązywanie nazw)
cat > $TNS_ADMIN/tnsnames.ora <<EOF
CDB1 =
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL = TCP)(HOST = $(hostname))(PORT = 1521))
    (CONNECT_DATA = (SERVER = DEDICATED) (SERVICE_NAME = CDB1))
  )

CDB2 =
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL = TCP)(HOST = $(hostname))(PORT = 1521))
    (CONNECT_DATA = (SERVER = DEDICATED) (SERVICE_NAME = CDB2))
  )

HR_PDB =
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL = TCP)(HOST = $(hostname))(PORT = 1521))
    (CONNECT_DATA = (SERVER = DEDICATED) (SERVICE_NAME = HR_PDB))
  )
EOF

echo "--- [PL] Restart Listenera / Restarting Listener ---"
lsnrctl stop
lsnrctl start

echo "[SUKCES] Sieć skonfigurowana. Proces LREG w ciągu ~60 sekund zarejestruje bazy."

# Usage example:
# oracle@linux9:~$ bash setup_network_26ai.sh
# =============================================================================
# Results interpretation:
# [PL] Po uruchomieniu tego skryptu, proces nasłuchujący otworzy port 1521. 
# Wewnętrzny proces bazy (LREG) automatycznie skontaktuje się z Listenerem 
# i zgłosi mu istnienie CDB1, CDB2 oraz HR_PDB. Od tego momentu Twój alias 'hr' 
# zadziała poprawnie.
# [EN] Listener opens port 1521. Internal LREG process will automatically 
# contact the Listener to register CDB1, CDB2, and HR_PDB.
# =============================================================================
