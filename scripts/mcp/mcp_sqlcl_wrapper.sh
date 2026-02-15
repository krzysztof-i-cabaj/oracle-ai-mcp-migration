#!/bin/bash
# ==============================================================
# OCM Wrapper dla SQLcl dedykowany dla Model Context Protocol (AI)
# ==============================================================

# 1. Czyszczenie lokalnych skryptów (Izolacja od login.sql)
unset SQLPATH
unset ORACLE_PATH

# 2. TWARDA INICJALIZACJA ŚRODOWISKA DLA PROCESÓW W TLE
# Gwarantuje, że AI zawsze wie, gdzie są pliki konfiguracyjne TNS/Wallet
export ORACLE_HOME=/u01/app/oracle/product/26.0.0/dbhome_1
export TNS_ADMIN=$ORACLE_HOME/network/admin
export PATH=$ORACLE_HOME/bin:$PATH

# Wymuszenie kodowania UTF-8 dla AI, by zapobiec halucynacjom
export NLS_LANG=AMERICAN_AMERICA.AL32UTF8

# 3. Uruchomienie natywnego SQLcl z przekazaniem argumentów
$ORACLE_HOME/bin/sql "$@"
