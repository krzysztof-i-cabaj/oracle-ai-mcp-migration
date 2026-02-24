#!/bin/bash
# ==============================================================================
# Tytuł:         01_install_oracle_github_hr.sh
# Opis/Description:  
#        [PL] Skrypt Bash automatyzujący pobranie i instalację oficjalnego schematu HR.
#        [EN] Bash script automating the download and installation of official HR schema.
#
# Autor:         KCB Kris
# Data:          2026-02-22
# Wersja/Version:        1.5
#
# Wymagania/Requirements:    - System Linux z dostępem do internetu (wget/curl, unzip)
#                - Użytkownik OS: oracle (wymagane ustawione zmienne ORACLE_HOME, ORACLE_SID)
#                - Baza CDB2 i otwarta PDB: HR_PDB
#
# Użycie/Usage:         ./01_install_oracle_github_hr.sh
# ==============================================================================

# [PL] Konfiguracja zmiennych - dostosuj do swojego środowiska!
# [EN] Variables configuration - adjust to your environment!
SYS_PASSWORD="ajka123"             # Hasło użytkownika SYS
HR_PASSWORD="ajka123"              # Przyszłe hasło użytkownika HR
PDB_CONNECT_STRING="localhost:1521/HR_PDB" # EZConnect do bazy docelowej (host:port/service_name)
WORK_DIR="$(pwd)/oracle_sample_schemas"    # Katalog roboczy - lokalnie obok skryptu
HR_DIR="${WORK_DIR}/db-sample-schemas-main/human_resources"

echo "====================================================="
echo "[PL] Rozpoczęcie wdrażania oficjalnego schematu HR..."
echo "====================================================="

# 1. [PL] Czyszczenie i przygotowanie katalogu roboczego
mkdir -p "${WORK_DIR}"
cd "${WORK_DIR}"
rm -rf db-sample-schemas* main.zip

# 2. [PL] Pobieranie repozytorium Oracle z GitHuba
echo "[PL] Pobieranie schematów z Oracle GitHub..."
wget -q -O main.zip https://github.com/oracle/db-sample-schemas/archive/refs/heads/main.zip

if [ $? -ne 0 ]; then
    echo "[BŁĄD] Nie udało się pobrać pliku z GitHub. Sprawdź dostęp do Internetu."
    exit 1
fi

unzip -q main.zip

if [ ! -f "${HR_DIR}/hr_install.sql" ]; then
    echo "[BŁĄD] Nie znaleziono pliku hr_install.sql w: ${HR_DIR}"
    echo "[INFO] Zawartość katalogu:"
    ls -l "${HR_DIR}"
    exit 1
fi

# 3. [PL] Podmiana ACCEPT na DEFINE w kopii skryptu
# ACCEPT z opcją HIDE blokuje odczyt ze stdin przy nieinteraktywnym wywołaniu.
# Zamiast modyfikować oryginał, tworzymy kopię z podstawionymi wartościami.
echo "[PL] Przygotowywanie skryptu instalacyjnego..."

HR_INSTALL_PATCHED="${HR_DIR}/hr_install_auto.sql"
cp "${HR_DIR}/hr_install.sql" "${HR_INSTALL_PATCHED}"

sed -i "s/^ACCEPT pass.*$/DEFINE pass = ${HR_PASSWORD}/"         "${HR_INSTALL_PATCHED}"
sed -i "s/^ACCEPT tbs.*$/DEFINE tbs = USERS/"                    "${HR_INSTALL_PATCHED}"
sed -i "s/^ACCEPT overwrite_schema.*$/DEFINE overwrite_schema = YES/" "${HR_INSTALL_PATCHED}"

# 4. [PL] Uruchomienie instalacji przez SQL*Plus
echo "[PL] Uruchamianie hr_install_auto.sql via SQL*Plus..."

sqlplus -s /nolog <<EOF
CONNECT sys/${SYS_PASSWORD}@${PDB_CONNECT_STRING} AS SYSDBA
@${HR_INSTALL_PATCHED}
EXIT;
EOF

echo "====================================================="
echo "[PL] Instalacja zakończona. Sprawdź logi w: ${WORK_DIR}"
echo "[PL] Możesz teraz zalogować się jako: sqlplus hr/${HR_PASSWORD}@${PDB_CONNECT_STRING}"
echo "====================================================="

