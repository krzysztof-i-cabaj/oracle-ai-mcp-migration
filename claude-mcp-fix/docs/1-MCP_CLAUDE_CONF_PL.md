# Konfiguracja MCP Serwerów Oracle dla Claude Code

**Data:** 2026-02-17
**Środowisko:** Oracle 26ai, SQLcl 25.4, Linux OEL9
**Cel:** Dwa serwery MCP (CDB1, CDB2) z uwierzytelnianiem przez Oracle Wallet (SEPS)

---

## Odkryte zasoby środowiska

| Zasób | Ścieżka / Wartość |
|---|---|
| Oracle Home | `/u01/app/oracle/product/26.0.0/dbhome_1` |
| SQLcl | `$ORACLE_HOME/bin/sql` (wersja 25.4.0.0) |
| TNS Admin | `$ORACLE_HOME/network/admin` |
| Oracle Wallet | `/home/oracle/wallet/` (cwallet.sso + ewallet.p12) |
| Java 11 (domyślna) | `$ORACLE_HOME/jdk/bin/java` — **za stara dla SQLcl -mcp** |
| Java 21 (wymagana) | `/usr/lib/jvm/java-21-openjdk-21.0.10.0.7-1.0.1.el9.x86_64` |

### Poświadczenia w portfelu (`mkstore -listCredential`)

```
4: CDB2       c##mcp_ai
3: CDB1       c##mcp_ai
2: CDB2_SYS   SYS
1: CDB1_SYS   SYS
```

### Aliasy TNS (`tnsnames.ora`) użyte dla MCP

```
CDB1 = (DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=ora26ai)(PORT=1521))
         (CONNECT_DATA=(SERVER=DEDICATED)(SERVICE_NAME=CDB1)))

CDB2 = (DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=ora26ai)(PORT=1521))
         (CONNECT_DATA=(SERVER=DEDICATED)(SERVICE_NAME=CDB2)))
```

### Konfiguracja portfela (`sqlnet.ora`)

```ini
WALLET_LOCATION =
  (SOURCE = (METHOD = FILE)(METHOD_DATA=(DIRECTORY=/home/oracle/wallet)))
SQLNET.WALLET_OVERRIDE = TRUE
```

---

## Wykonane zmiany

### 1. Modyfikacja `/home/oracle/mcp_sqlcl_wrapper.sh`

**Powód:** SQLcl `-mcp` wymaga Java 17 lub nowszej. Domyślna Java w `ORACLE_HOME` to wersja 11.
Dodano jeden eksport po bloku inicjalizacji środowiska (linia ~17):

```diff
  export ORACLE_HOME=/u01/app/oracle/product/26.0.0/dbhome_1
  export TNS_ADMIN=$ORACLE_HOME/network/admin
  export PATH=$ORACLE_HOME/bin:$PATH
+
+ # Java 21 wymagana przez SQLcl -mcp (minimum Java 17)
+ export JAVA_HOME=/usr/lib/jvm/java-21-openjdk-21.0.10.0.7-1.0.1.el9.x86_64

  export NLS_LANG=AMERICAN_AMERICA.AL32UTF8
```

**Plik po zmianie:**
```bash
#!/bin/bash
unset SQLPATH
unset ORACLE_PATH

export ORACLE_HOME=/u01/app/oracle/product/26.0.0/dbhome_1
export TNS_ADMIN=$ORACLE_HOME/network/admin
export PATH=$ORACLE_HOME/bin:$PATH

# Java 21 wymagana przez SQLcl -mcp (minimum Java 17)
export JAVA_HOME=/usr/lib/jvm/java-21-openjdk-21.0.10.0.7-1.0.1.el9.x86_64

export NLS_LANG=AMERICAN_AMERICA.AL32UTF8

$ORACLE_HOME/bin/sql "$@"
```

---

### 2. Modyfikacja `/home/oracle/.claude.json`

**Powód:** Plik jest aktywnie modyfikowany przez działający proces Claude Code,
dlatego bezpośrednia edycja narzędziem tekstowym była niemożliwa.
Użyto skryptu Python do atomicznego odczytu i zapisu JSON.

**Wykonana komenda:**
```bash
python3 -c "
import json

with open('/home/oracle/.claude.json', 'r') as f:
    config = json.load(f)

config['mcpServers'] = {
    'oracle-cdb1': {
        'command': '/home/oracle/mcp_sqlcl_wrapper.sh',
        'args': ['/@CDB1', '-mcp'],
        'env': {
            'WALLET_LOCATION': '/home/oracle/wallet'
        }
    },
    'oracle-cdb2': {
        'command': '/home/oracle/mcp_sqlcl_wrapper.sh',
        'args': ['/@CDB2', '-mcp'],
        'env': {
            'WALLET_LOCATION': '/home/oracle/wallet'
        }
    }
}

with open('/home/oracle/.claude.json', 'w') as f:
    json.dump(config, f, indent=2)
"
```

**Dodana sekcja w `.claude.json`:**
```json
"mcpServers": {
  "oracle-cdb1": {
    "command": "/home/oracle/mcp_sqlcl_wrapper.sh",
    "args": ["/@CDB1", "-mcp"],
    "env": {
      "WALLET_LOCATION": "/home/oracle/wallet"
    }
  },
  "oracle-cdb2": {
    "command": "/home/oracle/mcp_sqlcl_wrapper.sh",
    "args": ["/@CDB2", "-mcp"],
    "env": {
      "WALLET_LOCATION": "/home/oracle/wallet"
    }
  }
}
```

---

## Komendy diagnostyczne użyte w trakcie konfiguracji

```bash
# Znalezienie plików portfela
find /home/oracle -name "cwallet.sso" -o -name "ewallet.p12"

# Sprawdzenie zawartości portfela (lista poświadczeń)
ORACLE_HOME=/u01/app/oracle/product/26.0.0/dbhome_1
$ORACLE_HOME/bin/mkstore -wrl /home/oracle/wallet -listCredential

# Znalezienie dostępnych wersji Java
find /usr /opt /u01 -name "java" -type f 2>/dev/null | xargs -I{} sh -c '{} -version 2>&1 | head -1; echo {}'

# Test startu SQLcl MCP z Java 21
JAVA_HOME=/usr/lib/jvm/java-21-openjdk-21.0.10.0.7-1.0.1.el9.x86_64 \
  /u01/app/oracle/product/26.0.0/dbhome_1/bin/sql -mcp --help

# Weryfikacja konfiguracji MCP w .claude.json
python3 -c "import json; d=json.load(open('/home/oracle/.claude.json')); print(json.dumps(d.get('mcpServers','BRAK'), indent=2))"

# Test end-to-end: uruchomienie wrappera z wallet
timeout 3 /home/oracle/mcp_sqlcl_wrapper.sh "/@CDB1" "-mcp"
# Oczekiwany wynik: "MCP Server started successfully"
```

---

## Architektura połączenia

```
Claude Code
    │
    ├─► MCP Server: oracle-cdb1
    │       └─ mcp_sqlcl_wrapper.sh "/@CDB1" "-mcp"
    │               ├─ JAVA_HOME  → Java 21
    │               ├─ ORACLE_HOME → /u01/app/oracle/product/26.0.0/dbhome_1
    │               ├─ TNS_ADMIN  → .../network/admin
    │               └─ sql /@CDB1 -mcp
    │                       └─ wallet cwallet.sso → user: c##mcp_ai @ CDB1
    │
    └─► MCP Server: oracle-cdb2
            └─ mcp_sqlcl_wrapper.sh "/@CDB2" "-mcp"
                    └─ sql /@CDB2 -mcp
                            └─ wallet cwallet.sso → user: c##mcp_ai @ CDB2
```

---

## Wymagany restart

Aby Claude Code wykrył nowe serwery MCP, należy **zrestartować sesję**:
- zamknąć aktualne okno VSCode / terminal z Claude Code
- otworzyć nową sesję — serwery `oracle-cdb1` i `oracle-cdb2` zostaną załadowane automatycznie

---

## Potencjalne problemy i rozwiązania

| Problem | Przyczyna | Rozwiązanie |
|---|---|---|
| `SQLcl -mcp requires Java 17` | `JAVA_HOME` wskazuje na Java 11 | Dodano `JAVA_HOME` do wrappera |
| `ORA-01017: invalid credentials` | Brak wpisu w portfelu dla aliasu | `mkstore -createCredential ALIAS user pass` |
| `TNS-03505: Failed to resolve name` | Brak aliasu w `tnsnames.ora` | Dodać wpis do `$TNS_ADMIN/tnsnames.ora` |
| `ORA-28759: failure to open file` | Portfel niedostępny | Sprawdzić uprawnienia `/home/oracle/wallet/` (`chmod 700`) |
