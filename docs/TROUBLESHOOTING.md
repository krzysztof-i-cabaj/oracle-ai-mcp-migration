# Troubleshooting Guide - Oracle AI MCP Migration

Comprehensive troubleshooting guide for common issues and their solutions.

---

## Table of Contents

1. [Wallet Authentication Issues](#wallet-authentication-issues)
2. [Network Connectivity Problems](#network-connectivity-problems)
3. [MCP Server Issues](#mcp-server-issues)
4. [PDB Migration Failures](#pdb-migration-failures)
5. [Performance Problems](#performance-problems)
6. [AI Agent Behavior Issues](#ai-agent-behavior-issues)
7. [Security and Permissions](#security-and-permissions)
8. [Database Compatibility](#database-compatibility)

---

## Wallet Authentication Issues

### Problem 1: ORA-01017: invalid username/password; logon denied

**Symptoms:**
```
$ sql /@CDB1_SYS as sysdba
ORA-01017: invalid username/password; logon denied
```

**Diagnosis Steps:**

1. **Verify wallet location in sqlnet.ora:**
```bash
grep WALLET_LOCATION $TNS_ADMIN/sqlnet.ora
```

Expected output:
```
WALLET_LOCATION = (SOURCE = (METHOD = FILE) (METHOD_DATA = (DIRECTORY = /home/oracle/wallet)))
```

2. **Check wallet file permissions:**
```bash
ls -la /home/oracle/wallet/
```

Expected permissions:
```
drwx------  2 oracle oinstall 4096 Feb 15 10:00 .
-rw-------  1 oracle oinstall 5467 Feb 15 10:00 cwallet.sso
-rw-------  1 oracle oinstall   0  Feb 15 10:00 cwallet.sso.lck
```

3. **List credentials in wallet:**
```bash
mkstore -wrl /home/oracle/wallet -listCredential
```

4. **Verify TNS alias exists:**
```bash
grep CDB1_SYS $TNS_ADMIN/tnsnames.ora
```

**Solutions:**

**Solution A: Recreate credential**
```bash
# Remove existing credential
mkstore -wrl /home/oracle/wallet -deleteCredential CDB1_SYS

# Re-add with correct password
mkstore -wrl /home/oracle/wallet -createCredential CDB1_SYS SYS "YourActualPassword!"

# Test
sql /@CDB1_SYS as sysdba
```

**Solution B: Fix permissions**
```bash
chmod 700 /home/oracle/wallet
chmod 600 /home/oracle/wallet/*
chown oracle:oinstall /home/oracle/wallet/*
```

**Solution C: Verify SQLNET.WALLET_OVERRIDE**
```bash
# Add to sqlnet.ora if missing
echo "SQLNET.WALLET_OVERRIDE = TRUE" >> $TNS_ADMIN/sqlnet.ora
```

---

### Problem 2: Wallet password forgotten

**Symptoms:**
```
$ mkstore -wrl /home/oracle/wallet -listCredential
Enter wallet password:
Error: Invalid password
```

**Solutions:**

**Solution A: Create new wallet (DESTRUCTIVE - requires re-adding all credentials)**
```bash
# Backup old wallet
mv /home/oracle/wallet /home/oracle/wallet.old.$(date +%Y%m%d)

# Create new wallet
mkdir -p /home/oracle/wallet
mkstore -wrl /home/oracle/wallet -create

# Re-add all credentials
mkstore -wrl /home/oracle/wallet -createCredential CDB1_SYS SYS "password1"
mkstore -wrl /home/oracle/wallet -createCredential CDB2_SYS SYS "password2"
# ... etc
```

**Solution B: Use external password store (if enabled)**
```bash
# Check if using auto-login wallet
ls -la /home/oracle/wallet/cwallet.sso

# Auto-login wallets don't require password
# If present, you can list credentials without password
```

---

## Network Connectivity Problems

### Problem 3: TNS-12541: No listener

**Symptoms:**
```
$ sql /@CDB1_SYS
ORA-12541: TNS:no listener
```

**Diagnosis:**

```bash
# Check listener status
lsnrctl status

# Check if port 1521 is listening
netstat -tuln | grep 1521

# Check listener configuration
cat $TNS_ADMIN/listener.ora
```

**Solutions:**

**Solution A: Start listener**
```bash
lsnrctl start

# Wait 60 seconds for service registration
sleep 60

# Verify services are registered
lsnrctl services
```

**Solution B: Fix listener.ora**
```bash
# Ensure listener.ora has correct hostname
cat > $TNS_ADMIN/listener.ora <<EOF
LISTENER =
  (DESCRIPTION_LIST =
    (DESCRIPTION =
      (ADDRESS = (PROTOCOL = TCP)(HOST = $(hostname))(PORT = 1521))
    )
  )
EOF

# Restart listener
lsnrctl stop
lsnrctl start
```

**Solution C: Manual service registration**
```sql
-- If LREG not auto-registering
sqlplus / as sysdba <<EOF
ALTER SYSTEM REGISTER;
EXIT;
EOF

# Check again
lsnrctl services
```

---

### Problem 4: TNS-12514: Operation timed out

**Symptoms:**
```
$ tnsping CDB1
TNS-12514: TNS:listener does not currently know of service requested in connect descriptor
```

**Diagnosis:**

```bash
# Check if database is running
ps -ef | grep pmon

# Check listener services
lsnrctl services | grep -i cdb1

# Check service names in database
sqlplus / as sysdba <<EOF
SELECT name, value FROM v\$parameter WHERE name = 'service_names';
EXIT;
EOF
```

**Solutions:**

**Solution A: Force service registration**
```sql
sqlplus / as sysdba <<EOF
ALTER SYSTEM SET local_listener='(ADDRESS=(PROTOCOL=TCP)(HOST=$(hostname))(PORT=1521))' SCOPE=MEMORY;
ALTER SYSTEM REGISTER;
EXIT;
EOF
```

**Solution B: Add static service**
```bash
# Edit listener.ora to add static service
cat >> $TNS_ADMIN/listener.ora <<EOF

SID_LIST_LISTENER =
  (SID_LIST =
    (SID_DESC =
      (GLOBAL_DBNAME = CDB1)
      (ORACLE_HOME = $ORACLE_HOME)
      (SID_NAME = CDB1)
    )
  )
EOF

# Restart listener
lsnrctl reload
```

---

## MCP Server Issues

### Problem 5: MCP server not responding in VSCode

**Symptoms:**
- AI agent says "Cannot connect to Oracle MCP server"
- VSCode shows MCP server as "disconnected"
- No database context available

**Diagnosis:**

1. **Test SQLcl manually:**
```bash
$ORACLE_HOME/bin/sql -mcp /@CDB1_AI

# Expected: MCP server starts and waits for JSON-RPC commands
```

2. **Check wrapper script:**
```bash
bash -x /home/oracle/scripts/mcp/mcp_sqlcl_wrapper.sh -mcp /@CDB1_AI

# Look for errors in environment setup
```

3. **Verify environment variables:**
```bash
env | grep -E 'ORACLE_HOME|TNS_ADMIN|PATH|NLS_LANG'
```

4. **Check VSCode MCP configuration:**
```bash
# On macOS:
cat "$HOME/Library/Application Support/Code/User/settings.json" | grep -A 20 mcpServers

# On Linux:
cat "$HOME/.config/Code/User/settings.json" | grep -A 20 mcpServers
```

**Solutions:**

**Solution A: Fix SQLcl version**
```bash
# Check SQLcl version
sql -version

# Expected: SQLcl: Release 25.2 or higher

# If version too old, download latest:
# https://www.oracle.com/database/sqldeveloper/technologies/sqlcl/download/
```

**Solution B: Fix wrapper script paths**
```bash
# Edit mcp_sqlcl_wrapper.sh
cat > /home/oracle/scripts/mcp/mcp_sqlcl_wrapper.sh <<'EOF'
#!/bin/bash

# Clear any conflicting settings
unset SQLPATH
unset ORACLE_PATH

# Set required environment
export ORACLE_HOME=/u01/app/oracle/product/26.0.0/dbhome_1
export TNS_ADMIN=$ORACLE_HOME/network/admin
export PATH=$ORACLE_HOME/bin:$PATH
export NLS_LANG=AMERICAN_AMERICA.AL32UTF8

# Execute SQLcl with all arguments
exec $ORACLE_HOME/bin/sql "$@"
EOF

chmod +x /home/oracle/scripts/mcp/mcp_sqlcl_wrapper.sh
```

**Solution C: Test MCP protocol manually**
```bash
# Start SQLcl in MCP mode
$ORACLE_HOME/bin/sql -mcp /@CDB1_AI

# In another terminal, send test JSON-RPC request:
echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":{}}}' | nc localhost <port>
```

---

### Problem 6: AI makes incorrect SQL queries

**Symptoms:**
- AI generates syntactically correct but logically wrong queries
- AI doesn't understand Oracle-specific syntax
- AI uses generic SQL instead of Oracle SQL

**Solutions:**

**Solution A: Improve system prompt**

Add Oracle-specific context to your MCP configuration:

```json
{
  "mcpServers": {
    "oracle-dba": {
      "command": "/home/oracle/scripts/mcp/mcp_sqlcl_wrapper.sh",
      "args": ["-mcp", "/@CDB1_AI"],
      "systemPrompt": "You are an expert Oracle DBA with deep knowledge of Oracle Database 26ai, Multitenant architecture, and PL/SQL. Always use Oracle-specific syntax and best practices. Verify table and column names before querying. Use dynamic performance views (v$, gv$) for monitoring. Follow Oracle naming conventions."
    }
  }
}
```

**Solution B: Provide schema context**

**Prompt to AI:**
```
Before answering my question, first query these views to understand the database structure:
- DBA_TABLES (for table list)
- DBA_TAB_COLUMNS (for column details)
- DBA_CONSTRAINTS (for constraints)

Then formulate your query based on actual schema.
```

**Solution C: Use explicit examples**

**Prompt:**
```
Query the HR schema to find all employees in department 50.

Example of correct Oracle syntax:
SELECT 
    employee_id,
    first_name,
    last_name,
    department_id
FROM 
    hr.employees
WHERE 
    department_id = 50
ORDER BY 
    employee_id;

Use this style for your queries.
```

---

## PDB Migration Failures

### Problem 7: ORA-65011: Pluggable database does not exist

**Symptoms:**
```
SQL> ALTER PLUGGABLE DATABASE HR_PDB CLOSE;
ORA-65011: Pluggable database HR_PDB does not exist.
```

**Diagnosis:**

```sql
-- List all PDBs
SELECT pdb_name, pdb_id, status FROM cdb_pdbs ORDER BY pdb_name;

-- Case-sensitive check
SELECT name FROM v$pdbs;
```

**Solutions:**

**Solution A: Use correct case**
```sql
-- Oracle is case-sensitive for PDB names
ALTER PLUGGABLE DATABASE "hr_pdb" CLOSE;  -- lowercase
-- or
ALTER PLUGGABLE DATABASE HR_PDB CLOSE;     -- uppercase (if created as uppercase)
```

**Solution B: Check PDB location**
```sql
-- Ensure you're in the CDB root
SHOW CON_NAME;
-- Expected: CDB$ROOT

-- If in wrong container:
ALTER SESSION SET CONTAINER=CDB$ROOT;
```

---

### Problem 8: ORA-65090: operation only valid in CDB$ROOT

**Symptoms:**
```
SQL> CREATE PLUGGABLE DATABASE TEST_PDB ...
ORA-65090: operation only valid in CDB$ROOT
```

**Diagnosis:**
```sql
SELECT SYS_CONTEXT('USERENV', 'CON_NAME') AS current_container FROM dual;
```

**Solution:**
```sql
-- Switch to root container
ALTER SESSION SET CONTAINER=CDB$ROOT;

-- Then retry operation
CREATE PLUGGABLE DATABASE TEST_PDB ...
```

---

### Problem 9: PDB plug-in violations prevent opening

**Symptoms:**
```
SQL> ALTER PLUGGABLE DATABASE HR_PDB OPEN;
Warning: PDB altered with errors.

SQL> SELECT name, open_mode FROM v$pdbs WHERE name = 'HR_PDB';
NAME       OPEN_MODE
---------- ----------
HR_PDB     MIGRATE
```

**Diagnosis:**

```sql
-- Check violations
SELECT 
    name,
    cause,
    type,
    message,
    status,
    action
FROM 
    pdb_plug_in_violations
WHERE 
    name = 'HR_PDB'
AND 
    status != 'RESOLVED'
ORDER BY 
    time;
```

**Common Violations and Fixes:**

**Violation 1: Missing patches**
```
MESSAGE: PDB's patch level (19.3.0.0.0) < CDB's patch level (19.21.0.0.0)
ACTION: Apply same patches to PDB
```

**Fix:**
```bash
# Download and apply missing patches
cd $ORACLE_HOME/OPatch
./opatch lspatches

# Apply to PDB
sqlplus / as sysdba <<EOF
ALTER SESSION SET CONTAINER=HR_PDB;
@?/rdbms/admin/catbundle.sql psu apply
EXIT;
EOF
```

**Violation 2: Version mismatch**
```
MESSAGE: PDB's version (23.0.0.0.0) < CDB's version (26.0.0.0.0)
```

**Fix:**
```sql
ALTER SESSION SET CONTAINER=HR_PDB;

-- Run upgrade script
@?/rdbms/admin/catuppdb.sql

-- Recompile invalid objects
@?/rdbms/admin/utlrp.sql

-- Restart PDB
ALTER PLUGGABLE DATABASE HR_PDB CLOSE;
ALTER PLUGGABLE DATABASE HR_PDB OPEN;
```

**Violation 3: Tablespace encryption mismatch**
```
MESSAGE: Tablespace 'USERS' is encrypted but wallet is not available
```

**Fix:**
```bash
# Copy wallet from source CDB
scp source_server:/opt/oracle/admin/CDB1/wallet/* /opt/oracle/admin/CDB2/wallet/

# Update sqlnet.ora on target
echo "ENCRYPTION_WALLET_LOCATION=(SOURCE=(METHOD=FILE)(METHOD_DATA=(DIRECTORY=/opt/oracle/admin/CDB2/wallet)))" >> $TNS_ADMIN/sqlnet.ora

# Open wallet
sqlplus / as sysdba <<EOF
ADMINISTER KEY MANAGEMENT SET KEYSTORE OPEN IDENTIFIED BY "wallet_password";
EXIT;
EOF
```

---

## Performance Problems

### Problem 10: Migration taking too long

**Symptoms:**
- UNPLUG or PLUG operation running for hours
- Large PDB (>1TB) migration very slow

**Diagnosis:**

```sql
-- Monitor long operations
SELECT 
    opname,
    target,
    sofar,
    totalwork,
    ROUND(sofar/totalwork*100,2) AS pct_complete,
    time_remaining,
    elapsed_seconds
FROM 
    v$session_longops
WHERE 
    username = 'C##MCP_AI'
AND 
    time_remaining > 0;
```

**Solutions:**

**Solution A: Use NOCOPY instead of COPY**
```sql
-- Slow (copies all datafiles)
CREATE PLUGGABLE DATABASE HR_PDB USING '/path/hr.xml' COPY;

-- Fast (reuses datafiles from shared storage)
CREATE PLUGGABLE DATABASE HR_PDB USING '/path/hr.xml' NOCOPY;
```

**Solution B: Parallel file copy**
```bash
# If COPY is required, use parallel rsync
parallel -j 4 rsync -avP ::: /source/path/*.dbf ::: /target/path/
```

**Solution C: Compress XML metadata**
```sql
-- Enable compression for large metadata
ALTER SYSTEM SET "_enable_pdb_unplug_compression"=TRUE SCOPE=MEMORY;

-- Then unplug
ALTER PLUGGABLE DATABASE HR_PDB UNPLUG INTO '/path/hr.xml';
```

---

## Security and Permissions

### Problem 11: ORA-01031: insufficient privileges

**Symptoms:**
```
SQL> CREATE PLUGGABLE DATABASE TEST_PDB ...
ORA-01031: insufficient privileges
```

**Diagnosis:**

```sql
-- Check current user
SELECT USER FROM DUAL;

-- Check privileges
SELECT * FROM session_privs ORDER BY privilege;

-- Check roles
SELECT * FROM session_roles ORDER BY role;
```

**Solutions:**

**Solution A: Grant missing privileges**
```sql
-- Connect as SYSDBA
sqlplus / as sysdba

-- Grant CREATE PLUGGABLE DATABASE
GRANT CREATE PLUGGABLE DATABASE TO c##mcp_ai CONTAINER=ALL;

-- Verify
CONNECT c##mcp_ai/password
SELECT * FROM session_privs WHERE privilege LIKE '%PLUGGABLE%';
```

**Solution B: Use SYSDBA connection**
```bash
# If admin operations required
sql /@CDB1_SYS as sysdba
```

---

## Database Compatibility

### Problem 12: Cannot plug 23ai PDB into 26ai CDB

**Symptoms:**
```
SQL> CREATE PLUGGABLE DATABASE HR_PDB USING '/path/hr23ai.xml' NOCOPY;
ORA-65105: pluggable database file version is incompatible
```

**Solutions:**

**Solution A: Upgrade PDB before plugging**
```sql
-- First, plug as is (will be in MIGRATE mode)
CREATE PLUGGABLE DATABASE HR_PDB USING '/path/hr23ai.xml' NOCOPY;

-- Then upgrade
ALTER SESSION SET CONTAINER=HR_PDB;
@?/rdbms/admin/catuppdb.sql

-- Recompile
@?/rdbms/admin/utlrp.sql

-- Restart
ALTER PLUGGABLE DATABASE HR_PDB CLOSE;
ALTER PLUGGABLE DATABASE HR_PDB OPEN;
```

**Solution B: Use Data Pump**
```bash
# Export from 23ai PDB
expdp \"/ as sysdba\" directory=dump_dir dumpfile=hr_pdb.dmp full=y

# Import into 26ai PDB
impdp \"/ as sysdba\" directory=dump_dir dumpfile=hr_pdb.dmp full=y
```

---

## Quick Reference - Error Codes

| Error | Meaning | Quick Fix |
|-------|---------|-----------|
| ORA-01017 | Invalid username/password | Check wallet credentials |
| ORA-01031 | Insufficient privileges | Grant missing privileges |
| ORA-12541 | No listener | Start listener: `lsnrctl start` |
| ORA-12514 | Service not registered | `ALTER SYSTEM REGISTER;` |
| ORA-65011 | PDB does not exist | Check PDB name case-sensitivity |
| ORA-65090 | Not in CDB$ROOT | `ALTER SESSION SET CONTAINER=CDB$ROOT;` |
| ORA-65105 | File version incompatible | Run catuppdb.sql in PDB |

---

## Getting Help

If your issue isn't covered here:

1. **Search existing issues**: https://github.com/yourusername/oracle-ai-mcp-migration/issues
2. **Check Oracle documentation**: https://docs.oracle.com/en/database/
3. **Create new issue**: Include all diagnostic output and error messages
4. **Join discussions**: https://github.com/yourusername/oracle-ai-mcp-migration/discussions

---

**Document Version**: 1.0  
**Last Updated**: 2026-02-15  
**Maintainer**: KCB Kris
