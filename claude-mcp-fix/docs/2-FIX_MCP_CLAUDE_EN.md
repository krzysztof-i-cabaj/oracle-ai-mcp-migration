# Report: Fixing Oracle SQLcl MCP Integration with Claude Code

**Date:** 2026-02-17  
**Environment:** Oracle 26ai, SQLcl 25.4.1, Claude Code 2.1.44, Linux OEL9  
**Operator:** oracle@ora26ai

---

## 1. Initial Problem

### 1.1 Symptoms
After system restart and Claude Code VSCode extension update (from version 2.1.42 → 2.1.44):

```
API Error: 400 {"type":"error","error":{"type":"invalid_request_error",
"message":"tools.21.custom input_schema: JSON schema is invalid. 
It must match JSON Schema draft 2020-12"}}
```

- MCP servers (oracle-cdb1, oracle-cdb2) were not visible in Claude Code
- Connection timeout: 60 seconds, followed by connection error
- SQLcl MCP processes were starting on the server but not communicating with Claude Code

### 1.2 Initial Configuration

Files:
- `/home/oracle/.claude.json` — contained MCP configuration (wrong location)
- `/home/oracle/.claude/settings.json` — empty `{}`
- `/home/oracle/mcp_sqlcl_wrapper.sh` — wrapper for SQLcl with Java 21

---

## 2. Diagnosis

### 2.1 Root Causes Identified

#### Root Cause #1: Claude Code Extension Update
- Extension automatically updated 3 hours before problem report
- Version 2.1.44 introduced stricter JSON Schema draft 2020-12 validation
- SQLcl 25.4.x exposes tool #21 schema incompatible with this standard

#### Root Cause #2: Protocol Mismatch
**Key discovery via strace:**

```bash
# SQLcl MCP uses JSON lines (one line = one JSON message)
{"jsonrpc":"2.0","id":1,"result":{...}}\n

# Claude Code expects LSP format (Content-Length headers)
Content-Length: 151\r\n
\r\n
{"jsonrpc":"2.0","id":1,"result":{...}}
```

SQLcl was not responding because:
- It expected JSON lines format
- Claude Code was sending LSP format
- No conversion = no communication

#### Root Cause #3: Wrong MCP Configuration Location
Claude Code reads configuration from `~/.claude/settings.json`, not from `~/.claude.json`

---

## 3. Solution

### 3.1 Final Architecture

```
Claude Code (VSCode)
    │
    ├─ uses: LSP format (Content-Length headers)
    │
    └─► Python Proxy (/home/oracle/mcp_lsp_to_jsonlines.py)
            │
            ├─ converts: LSP ↔ JSON lines
            ├─ fixes: JSON Schema draft 2020-12
            │
            └─► SQLcl MCP Server
                    │
                    ├─ /home/oracle/mcp_sqlcl_wrapper.sh
                    ├─ SQLcl 25.4.1 with Java 21
                    │
                    └─► Oracle Database 26ai
                            │
                            ├─ CDB1 @ c##mcp_ai (Oracle Wallet)
                            └─ CDB2 @ c##mcp_ai (Oracle Wallet)
```

---

## 4. Solution Implementation

### 4.1 File #1: `/home/oracle/mcp_sqlcl_wrapper.sh`

```bash
#!/bin/bash
unset SQLPATH
unset ORACLE_PATH

export ORACLE_HOME=/u01/app/oracle/product/26.0.0/dbhome_1
export TNS_ADMIN=$ORACLE_HOME/network/admin
export PATH=/home/oracle/sqlcl/bin:$PATH

# Java 21 required by SQLcl -mcp (minimum Java 17)
export JAVA_HOME=/usr/lib/jvm/java-21-openjdk-21.0.10.0.7-1.0.1.el9.x86_64

export NLS_LANG=AMERICAN_AMERICA.AL32UTF8

/home/oracle/sqlcl/bin/sql "$@"
```

**Permissions:**
```bash
chmod +x /home/oracle/mcp_sqlcl_wrapper.sh
```

---

### 4.2 File #2: `/home/oracle/mcp_lsp_to_jsonlines.py`

```python
#!/usr/bin/env python3
"""
Proxy: LSP (Claude Code) ↔ JSON lines (SQLcl MCP)
Claude Code: Content-Length headers
SQLcl MCP: One JSON object per line
"""
import sys, json, subprocess, threading

def read_lsp(stream):
    """Read Content-Length framed message"""
    headers = {}
    while True:
        line = stream.readline()
        if not line or line in (b'\r\n', b'\n'):
            break
        if b':' in line:
            k, v = line.decode().split(':', 1)
            headers[k.strip()] = v.strip()
    length = int(headers.get('Content-Length', 0))
    return stream.read(length) if length else None

def write_lsp(data):
    """Write Content-Length framed message"""
    msg = data.encode() if isinstance(data, str) else data
    sys.stdout.buffer.write(f'Content-Length: {len(msg)}\r\n\r\n'.encode())
    sys.stdout.buffer.write(msg)
    sys.stdout.buffer.flush()

def fix_schema(schema):
    """Fix JSON Schema to draft 2020-12"""
    if not isinstance(schema, dict):
        return
    for k in list(schema.keys()):
        if k not in ['type','properties','required','description','items',
                     'enum','default','title','anyOf','oneOf','allOf',
                     'not','format','minimum','maximum','minLength',
                     'maxLength','pattern','additionalProperties','const']:
            del schema[k]
    if 'properties' in schema and 'type' not in schema:
        schema['type'] = 'object'
    for v in schema.get('properties', {}).values():
        fix_schema(v)

# Start SQLcl
proc = subprocess.Popen(
    ['/home/oracle/mcp_sqlcl_wrapper.sh'] + sys.argv[1:],
    stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=sys.stderr
)

# Forward stdin: LSP → JSON lines
def forward_stdin():
    while True:
        msg = read_lsp(sys.stdin.buffer)
        if msg is None:
            break
        proc.stdin.write(msg.rstrip() + b'\n')
        proc.stdin.flush()

t = threading.Thread(target=forward_stdin, daemon=True)
t.start()

# Forward stdout: JSON lines → LSP
while True:
    line = proc.stdout.readline()
    if not line:
        break
    line = line.strip()
    if not line:
        continue
    try:
        data = json.loads(line)
        # Fix schema bug
        if 'result' in data and 'tools' in data.get('result', {}):
            for tool in data['result']['tools']:
                if 'inputSchema' in tool:
                    fix_schema(tool['inputSchema'])
        write_lsp(json.dumps(data))
    except:
        pass
```

**Permissions:**
```bash
chmod +x /home/oracle/mcp_lsp_to_jsonlines.py
```

---

### 4.3 File #3: `/home/oracle/.claude/settings.json`

```json
{
  "env": {
    "MCP_TIMEOUT": "60000"
  },
  "mcpServers": {
    "oracle-cdb1": {
      "command": "/usr/bin/python3",
      "args": ["-u", "/home/oracle/mcp_lsp_to_jsonlines.py", "/@CDB1", "-mcp"],
      "env": {
        "WALLET_LOCATION": "/home/oracle/wallet"
      }
    },
    "oracle-cdb2": {
      "command": "/usr/bin/python3",
      "args": ["-u", "/home/oracle/mcp_lsp_to_jsonlines.py", "/@CDB2", "-mcp"],
      "env": {
        "WALLET_LOCATION": "/home/oracle/wallet"
      }
    }
  }
}
```

---

### 4.4 Oracle Wallet Configuration

**Location:** `/home/oracle/wallet/`

**Files:**
```
cwallet.sso       # Auto-login wallet
ewallet.p12       # Encrypted wallet
```

**Contents (credentials):**
```bash
mkstore -wrl /home/oracle/wallet -listCredential
# 4: CDB2       c##mcp_ai
# 3: CDB1       c##mcp_ai
# 2: CDB2_SYS   SYS
# 1: CDB1_SYS   SYS
```

**sqlnet.ora configuration:**
```ini
# /u01/app/oracle/product/26.0.0/dbhome_1/network/admin/sqlnet.ora
WALLET_LOCATION =
  (SOURCE =
    (METHOD = FILE)
    (METHOD_DATA =
      (DIRECTORY = /home/oracle/wallet)
    )
  )
SQLNET.WALLET_OVERRIDE = TRUE
```

---

## 5. Solution Verification

### 5.1 Proxy Communication Test

```bash
# Manual test JSON lines → LSP
mkfifo /tmp/test_in /tmp/test_out
/home/oracle/mcp_sqlcl_wrapper.sh "/@CDB1" "-mcp" < /tmp/test_in > /tmp/test_out 2>&1 &

echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}' > /tmp/test_in &

timeout 5 cat /tmp/test_out
```

**Expected output:**
```json
{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2024-11-05","capabilities":{"logging":{},"prompts":{"listChanged":true},"resources":{"subscribe":true,"listChanged":true},"tools":{"listChanged":true}},"serverInfo":{"name":"sqlcl-mcp-server","version":"1.0.0"}}}
```

### 5.2 Test in Claude Code

1. Clean up old processes:
```bash
pkill -f mcp
```

2. In VSCode:
   - `Ctrl+Shift+P` → **"Developer: Reload Window"**
   - Open Claude Code
   - Check **"Manage MCP Servers"**
   - Should see: `oracle-cdb1`, `oracle-cdb2` with **"Running"** status

3. Functionality test:
```
User in Claude Code: "show me the list of tables in CDB1"
```

Expected result: Claude Code uses MCP tools to query the database.

---

## 6. Problems Resolved

### 6.1 Problem: JSON Schema draft 2020-12
**Solution:** `fix_schema()` function in proxy removes incompatible fields from SQLcl tool schemas.

### 6.2 Problem: Protocol Mismatch (LSP vs JSON lines)
**Solution:** Proxy performs bidirectional translation:
- `read_lsp()` — parses Content-Length headers from Claude Code
- `write_lsp()` — wraps SQLcl responses in LSP format

### 6.3 Problem: 60s Timeout
**Solution:** After fixing the protocol, communication works immediately, timeout is not reached.

---

## 7. Potential Issues and Solutions

| Problem | Symptom | Solution |
|---------|---------|----------|
| `Connection timeout 60s` | MCP servers not responding | Check if processes are alive: `ps -ef \| grep mcp` |
| `Invalid JSON Schema` | 400 error in Claude Code | Proxy `fix_schema()` should fix this automatically |
| `ORA-01017: invalid credentials` | Database connection error | Check wallet: `mkstore -wrl /home/oracle/wallet -listCredential` |
| Zombie processes | Multiple `sql -mcp` processes | Kill: `pkill -f "sql.*-mcp"` |
| Proxy not starting | No Python processes | Check permissions: `chmod +x /home/oracle/mcp_lsp_to_jsonlines.py` |

---

## 8. Diagnostic Commands

### 8.1 Status Check

```bash
# MCP processes
ps -ef | grep -E "(mcp_proxy|mcp_lsp|@CDB)" | grep -v grep

# Claude Code logs (VSCode)
# View → Output → select "Claude Code" from dropdown

# Database connection test (without MCP)
/home/oracle/mcp_sqlcl_wrapper.sh /@CDB1
```

### 8.2 Complete MCP System Restart

```bash
# 1. Kill all processes
pkill -f mcp

# 2. Remove old temporary files
rm -f /tmp/mcp_* 2>/dev/null

# 3. Reload VSCode
# In VSCode: Ctrl+Shift+P → "Developer: Reload Window"
```

---

## 9. Conclusions and Recommendations

### 9.1 Key Findings

1. **SQLcl MCP uses JSON lines, not LSP** — Oracle documentation doesn't mention this clearly
2. **SQLcl 25.4.x has schema bug** — tool #21 exposes incompatible JSON Schema
3. **Claude Code auto-updates** — new versions may introduce breaking changes

### 9.2 Recommendations

1. **Report bug to Oracle Support:**
   - Subject: "SQLcl 25.4.x MCP — JSON Schema draft 2020-12 incompatibility"
   - SR should include logs and information about tool #21

2. **Disable Claude Code extension auto-update:**
   - VSCode → Settings → Extensions → uncheck "Auto Update"

3. **Monitoring:**
   - Regularly check `ps -ef | grep mcp`
   - Monitor logs in VSCode Output → Claude Code

4. **Configuration backup:**
```bash
cp ~/.claude/settings.json ~/.claude/settings.json.backup
cp /home/oracle/mcp_lsp_to_jsonlines.py /home/oracle/mcp_lsp_to_jsonlines.py.backup
```

---

## 10. Appendix: Complete Debugging Path

### 10.1 Trial and Error

1. ❌ Downgrade Claude Code 2.1.44 → 2.1.42 — didn't help (problem in SQLcl)
2. ❌ JSON-RPC proxy with headers — SQLcl didn't respond
3. ❌ TCP socket communication attempt — SQLcl uses stdio
4. ❌ Test with `Content-Length` via pipe — no response
5. ✅ **Test with pure JSON + newline — response!**

### 10.2 Key Test (Breakthrough)

```bash
echo '{"jsonrpc":"2.0","id":1,"method":"initialize",...}' > /tmp/mcp_in &
timeout 5 cat /tmp/mcp_out

# Output:
{"jsonrpc":"2.0","id":1,"result":{...}}
```

This confirmed that SQLcl uses JSON lines, not LSP.

---

## 11. Contact and Support

**In case of problems:**

1. Check VSCode logs: View → Output → Claude Code
2. Check processes: `ps -ef | grep mcp`
3. Manual proxy test (section 5.1)
4. If SQLcl issue: Oracle Support SR
5. If Claude Code issue: https://support.claude.com

**Documentation:**
- Oracle SQLcl MCP: https://docs.oracle.com/en/database/oracle/sql-developer-command-line/25.4/sqcug/using-sqlcl-mcp-server.html
- Claude Code: https://docs.claude.com/en/docs/claude-code

---

**End of Report**  
Prepared by: Krzysztof Cabaj & Claude (Anthropic)  
Date: 2026-02-17
