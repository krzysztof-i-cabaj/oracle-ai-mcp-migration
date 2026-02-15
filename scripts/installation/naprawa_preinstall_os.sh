# =============================================================================
# Nazwa skryptu / Script name: naprawa_preinstall_os.sh
# Autor / Author: KCB Kris
# Opis / Description: 
# [PL] Ręczna konfiguracja parametrów jądra i limitów ulimit dla Oracle 26ai.
# Zastępuje brakujący pakiet oracle-database-preinstall-26ai.
# [EN] Manual configuration of kernel parameters and ulimits for Oracle 26ai.
# Replaces the missing oracle-database-preinstall-26ai package.
# Wersja Oracle / Oracle version: 23ai/26ai
# =============================================================================
# Cel skryptu / Script purpose:
# [PL] Ochrona przed błędem ORA-27102 i umożliwienie alokacji dużego SGA dla AI.
# [EN] Protection against ORA-27102 error and enabling large SGA allocation for AI.
# =============================================================================

# [PL] 1. Konfiguracja parametrów jądra (sysctl)
# [EN] 1. Kernel parameters configuration (sysctl)
cat > /etc/sysctl.d/99-oracle-database.conf <<EOF
fs.file-max = 6815744
kernel.sem = 250 32000 100 128
kernel.shmmni = 4096
kernel.shmall = 1073741824
kernel.shmmax = 4398046511104
kernel.panic_on_oops = 1
net.core.rmem_default = 262144
net.core.rmem_max = 4194304
net.core.wmem_default = 262144
net.core.wmem_max = 1048576
net.ipv4.conf.all.rp_filter = 2
net.ipv4.conf.default.rp_filter = 2
fs.aio-max-nr = 1048576
EOF

# [PL] Aplikowanie zmian w locie bez restartu serwera
# [EN] Applying changes on the fly without server reboot
sysctl --system

# [PL] 2. Konfiguracja limitów zasobów (limits.conf)
# [EN] 2. Resource limits configuration (limits.conf)
cat > /etc/security/limits.d/oracle-database.conf <<EOF
oracle   soft   nofile    1024
oracle   hard   nofile    65536
oracle   soft   nproc     2047
oracle   hard   nproc     16384
oracle   soft   stack     10240
oracle   hard   stack     32768
oracle   soft   memlock   3145728
oracle   hard   memlock   3145728
EOF

echo "[OK] Parametry OS dla Oracle 26ai zostały zoptymalizowane."

# Przykład użycia / Usage example:
# root@linux9:~# bash naprawa_preinstall_os.sh
# =============================================================================
# Interpretacja wyników / Results interpretation:
# [PL] Skrypt modyfikuje na stałe jądro. `fs.aio-max-nr` jest kluczowe dla
# asynchronicznego I/O procesów DBW0 (Database Writer). Jeśli Asynchronous I/O 
# przestanie działać, Oracle przejdzie w tryb synchroniczny, co drastycznie 
# obniży wydajność dyskową. Limit `memlock` umożliwia użycie HugePages.
# [EN] `fs.aio-max-nr` is crucial for asynchronous I/O of DBW0 processes. 
# `memlock` allows the use of HugePages.
# =============================================================================
