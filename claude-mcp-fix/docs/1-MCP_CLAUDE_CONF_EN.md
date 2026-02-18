# Oracle MCP Servers Configuration for Claude Code

**Date:** 2026-02-17
**Environment:** Oracle 26ai, SQLcl 25.4, Linux OEL9
**Goal:** Two MCP servers (CDB1, CDB2) authenticated via Oracle Wallet (SEPS)

---

## Discovered Environment Resources

| Resource | Path / Value |
|---|---|
| Oracle Home | `/u01/app/oracle/product/26.0.0/dbhome_1` |
| SQLcl | `$ORACLE_HOME/bin/sql` (version 25.4.0.0) |
| TNS Admin | `$ORACLE_HOME/network/admin` |
| Oracle Wallet | `/home/oracle/wallet/` (cwallet.sso + ewallet.p12) |
| Java 11 (default) | `$ORACLE_HOME/jdk/bin/java` — **too old for SQLcl -mcp** |
| Java 21 (required) | `/usr/lib/jvm/java-21-openjdk-21.0.10.0.7-1.0.1.el9.x86_64` |

### Wallet Credentials (`mkstore -listCredential`)

```
4: CDB2       c##mcp_ai
3: CDB1       c##mcp_ai
2: CDB2_SYS   SYS
1: CDB1_SYS   SYS
```

### TNS Aliases (`tnsnames.ora`) Used for MCP

```
CDB1 = (DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=ora26ai)(PORT=1521))
         (CONNECT_DATA=(SERVER=DEDICATED)(SERVICE_NAME=CDB1)))

CDB2 = (DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=ora26ai)(PORT=1521))
         (CONNECT_DATA=(SERVER=DEDICATED)(SERVICE_NAME=CDB2)))
```

### Wallet Configuration (`sqlnet.ora`)

```ini
WALLET_LOCATION =
  (SOURCE = (METHOD = FILE)(METHOD_DATA=(DIRECTORY=/home/oracle/wallet)))
SQLNET.WALLET_OVERRIDE = TRUE
```

---

## Changes Made

### 1. Modified `/home/oracle/mcp_sqlcl_wrapper.sh`

**Reason:** SQLcl `-mcp` requires Java 17 or higher. The default Java bundled with `ORACLE_HOME` is version 11.
One export was added after the environment initialization block (around line 17):

```diff
  export ORACLE_HOME=/u01/app/oracle/product/26.0.0/dbhome_1
  export TNS_ADMIN=$ORACLE_HOME/network/admin
  export PATH=$ORACLE_HOME/bin:$PATH
+
+ # Java 21 required by SQLcl -mcp (minimum Java 17)
+ export JAVA_HOME=/usr/lib/jvm/java-21-openjdk-21.0.10.0.7-1.0.1.el9.x86_64

  export NLS_LANG=AMERICAN_AMERICA.AL32UTF8
```

**File after change:**
```bash
#!/bin/bash
unset SQLPATH
unset ORACLE_PATH

export ORACLE_HOME=/u01/app/oracle/product/26.0.0/dbhome_1
export TNS_ADMIN=$ORACLE_HOME/network/admin
export PATH=$ORACLE_HOME/bin:$PATH

# Java 21 required by SQLcl -mcp (minimum Java 17)
export JAVA_HOME=/usr/lib/jvm/java-21-openjdk-21.0.10.0.7-1.0.1.el9.x86_64

export NLS_LANG=AMERICAN_AMERICA.AL32UTF8

$ORACLE_HOME/bin/sql "$@"
```

---

### 2. Modified `/home/oracle/.claude.json`

**Reason:** The file is actively modified by the running Claude Code process,
making direct text-based editing impossible (file changes between read and write).
A Python script was used to atomically read and write the JSON.

**Command executed:**
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

**Section added to `.claude.json`:**
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

## Diagnostic Commands Used During Setup

```bash
# Locate wallet files
find /home/oracle -name "cwallet.sso" -o -name "ewallet.p12"

# List wallet credentials
ORACLE_HOME=/u01/app/oracle/product/26.0.0/dbhome_1
$ORACLE_HOME/bin/mkstore -wrl /home/oracle/wallet -listCredential

# Find all available Java installations and versions
find /usr /opt /u01 -name "java" -type f 2>/dev/null | xargs -I{} sh -c '{} -version 2>&1 | head -1; echo {}'

# Test SQLcl MCP startup with Java 21
JAVA_HOME=/usr/lib/jvm/java-21-openjdk-21.0.10.0.7-1.0.1.el9.x86_64 \
  /u01/app/oracle/product/26.0.0/dbhome_1/bin/sql -mcp --help

# Verify MCP configuration in .claude.json
python3 -c "import json; d=json.load(open('/home/oracle/.claude.json')); print(json.dumps(d.get('mcpServers','MISSING'), indent=2))"

# End-to-end test: start wrapper with wallet (3 second timeout)
timeout 3 /home/oracle/mcp_sqlcl_wrapper.sh "/@CDB1" "-mcp"
# Expected output: "MCP Server started successfully"
```

---

## Connection Architecture

```
Claude Code
    │
    ├─► MCP Server: oracle-cdb1
    │       └─ mcp_sqlcl_wrapper.sh "/@CDB1" "-mcp"
    │               ├─ JAVA_HOME   → Java 21
    │               ├─ ORACLE_HOME → /u01/app/oracle/product/26.0.0/dbhome_1
    │               ├─ TNS_ADMIN   → .../network/admin
    │               └─ sql /@CDB1 -mcp
    │                       └─ wallet cwallet.sso → user: c##mcp_ai @ CDB1
    │
    └─► MCP Server: oracle-cdb2
            └─ mcp_sqlcl_wrapper.sh "/@CDB2" "-mcp"
                    └─ sql /@CDB2 -mcp
                            └─ wallet cwallet.sso → user: c##mcp_ai @ CDB2
```

---

## Required Restart

For Claude Code to detect the new MCP servers, a **session restart is required**:
- close the current VSCode window / Claude Code terminal
- open a new session — `oracle-cdb1` and `oracle-cdb2` servers will be loaded automatically

---

## Potential Issues and Solutions

| Problem | Cause | Solution |
|---|---|---|
| `SQLcl -mcp requires Java 17` | `JAVA_HOME` points to Java 11 | Added `JAVA_HOME` to the wrapper script |
| `ORA-01017: invalid credentials` | No wallet entry for the TNS alias | `mkstore -createCredential ALIAS user pass` |
| `TNS-03505: Failed to resolve name` | Missing alias in `tnsnames.ora` | Add entry to `$TNS_ADMIN/tnsnames.ora` |
| `ORA-28759: failure to open file` | Wallet not accessible | Check permissions on `/home/oracle/wallet/` (`chmod 700`) |
