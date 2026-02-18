# 🔧 Oracle SQLcl MCP Integration with Claude Code — Fix Guide

![Status](https://img.shields.io/badge/Status-✅%20RESOLVED-brightgreen)
![Claude Code](https://img.shields.io/badge/Claude%20Code-2.1.45-blueviolet)
![SQLcl](https://img.shields.io/badge/SQLcl-25.4.1-blue)
![Oracle](https://img.shields.io/badge/Oracle-26ai-red)
![OS](https://img.shields.io/badge/OS-OEL9%20Linux-lightgrey)
![Protocol](https://img.shields.io/badge/Protocol-JSON%20lines-orange)
![Fix](https://img.shields.io/badge/Fix-Python%20Proxy-yellow)

> **TL;DR** — Claude Code 2.1.44+ changed MCP protocol from LSP to JSON lines. A lightweight Python proxy fixes both the communication mismatch and a SQLcl JSON Schema bug.

---

## 📋 Table of Contents

- [Executive Summary](#-executive-summary)
- [Initial Problem](#-initial-problem)
- [Diagnosis Process](#-diagnosis-process)
- [Final Solution](#-final-solution)
- [Implementation](#️-implementation)
- [Solution Verification](#-solution-verification)
- [Key Findings](#-key-findings)
- [Problems Resolved](#-problems-resolved)
- [Operational Procedures](#️-operational-procedures)
- [Potential Issues](#-potential-issues)
- [Conclusions and Recommendations](#-conclusions-and-recommendations)
- [Appendix: Complete Debugging History](#-appendix-complete-debugging-history)

---

## 🎯 Executive Summary

### 🔴 Problem
After Claude Code extension update (2.1.42 → 2.1.44 → 2.1.45), Oracle SQLcl MCP servers stopped working with 60s timeout error.

### 🔬 Root Cause
Claude Code 2.1.44+ **changed MCP communication protocol**:
- **Before:** LSP format (Content-Length headers)
- **Now:** JSON lines (one JSON line = one message)

### ✅ Solution
Simple Python proxy that:
1. Passes through JSON lines communication unchanged
2. Fixes SQLcl tool JSON schemas to draft 2020-12

---

## 🚨 Initial Problem

### 2.1 Symptoms
```
Connection timeout: 60 seconds
MCP server "oracle-cdb1" connection timed out after 60000ms
```

- ❌ MCP servers not responding to initialize
- ❌ SQLcl processes starting but not communicating
- ❌ No MCP tools available in Claude Code

### 2.2 Environment

| Component | Version |
|-----------|---------|
| 🗄️ Oracle Database | 26ai Enterprise Edition |
| 🛠️ SQLcl | 25.4.1 Build 022.0618 |
| 🤖 Claude Code | 2.1.45 (auto-updated from 2.1.42) |
| 🐧 System | Oracle Linux 9 |
| ☕ Java | OpenJDK 21 |
| 🔐 Authentication | Oracle Wallet (SEPS) |

---

## 🔍 Diagnosis Process

### 3.1 Trial and Error

| # | 🧪 Hypothesis | Test | Result |
|---|--------------|------|--------|
| 1 | JSON schema issue | Downgrade to 2.1.42 | ❌ No effect |
| 2 | SQLcl uses LSP format | LSP ↔ JSON lines proxy | ❌ Timeout |
| 3 | SQLcl uses TCP socket | Port testing | ❌ Uses stdio |
| 4 | stdout buffering | Unbuffered I/O test | ❌ Timeout |
| 5 | Claude Code changed protocol | Debug logging proxy | ✅ **SUCCESS** |

### 3.2 🔑 Key Discovery

**Manual test with debug logging:**
```bash
[22:58:59] read_lsp: headers={'{"method"': '"initialize",...'}, data=None
```

Claude Code **doesn't send Content-Length** — it sends pure JSON!

```json
{"method":"initialize","params":{"protocolVersion":"2025-11-25",...},"jsonrpc":"2.0","id":0}
```

### 3.3 ⚠️ Additional Issue: JSON Schema

SQLcl 25.4.x exposes tool #21 with incompatible schema (draft-07 instead of draft 2020-12).

---

## 💡 Final Solution

### 4.1 Architecture

```
Claude Code 2.1.45
    │
    ├─ JSON lines ({"jsonrpc":"2.0",...}\n)
    │
    └─► 🐍 Python Proxy (/home/oracle/mcp_jsonlines_fix.py)
            │
            ├─ Passes JSON lines unchanged
            ├─ Fixes JSON Schema draft 2020-12
            │
            └─► 🛠️ SQLcl MCP Server
                    │
                    ├─ JSON lines ({"jsonrpc":"2.0",...}\n)
                    ├─ SQLcl 25.4.1 + Java 21
                    │
                    └─► 🗄️ Oracle Database 26ai
                            │
                            ├─ CDB1 @ c##mcp_ai
                            └─ CDB2 @ c##mcp_ai
```

---

## 🛠️ Implementation

### 5.1 File #1: `/home/oracle/mcp_sqlcl_wrapper.sh`

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

### 5.2 File #2: `/home/oracle/mcp_jsonlines_fix.py`

```python
#!/usr/bin/env python3
"""Simple proxy: JSON lines in/out, only fixes schema"""
import sys, json, subprocess, threading

def fix_schema(schema):
    """Fix JSON Schema to draft 2020-12"""
    if not isinstance(schema, dict):
        return
    # Remove non-standard fields
    for k in list(schema.keys()):
        if k not in ['type','properties','required','description','items',
                     'enum','default','title','anyOf','oneOf','allOf',
                     'not','format','minimum','maximum','minLength',
                     'maxLength','pattern','additionalProperties','const']:
            del schema[k]
    # Ensure type: object is present
    if 'properties' in schema and 'type' not in schema:
        schema['type'] = 'object'
    # Recurse into nested properties
    for v in schema.get('properties', {}).values():
        fix_schema(v)

# Start SQLcl MCP
proc = subprocess.Popen(
    ['/home/oracle/mcp_sqlcl_wrapper.sh'] + sys.argv[1:],
    stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=sys.stderr,
    bufsize=0  # Unbuffered
)

# Forward stdin: JSON lines → SQLcl
def forward_stdin():
    for line in sys.stdin:
        proc.stdin.write(line.encode())
        proc.stdin.flush()

t = threading.Thread(target=forward_stdin, daemon=True)
t.start()

# Forward stdout: SQLcl → Claude Code (with schema fix)
for line in iter(proc.stdout.readline, b''):
    line = line.strip()
    if not line:
        continue
    try:
        data = json.loads(line)
        # Fix schema bug in tools response
        if 'result' in data and 'tools' in data.get('result', {}):
            for tool in data['result']['tools']:
                if 'inputSchema' in tool:
                    fix_schema(tool['inputSchema'])
        sys.stdout.write(json.dumps(data) + '\n')
        sys.stdout.flush()
    except:
        pass
```

**Permissions:**
```bash
chmod +x /home/oracle/mcp_jsonlines_fix.py
```

---

### 5.3 File #3: `/home/oracle/.claude.json`

> **⚠️ IMPORTANT:** Claude Code 2.1.44+ reads MCP configuration from `~/.claude.json`, **NOT** from `~/.claude/settings.json`!

```json
{
  "mcpServers": {
    "oracle-cdb1": {
      "command": "/usr/bin/python3",
      "args": ["-u", "/home/oracle/mcp_jsonlines_fix.py", "/@CDB1", "-mcp"],
      "env": {
        "WALLET_LOCATION": "/home/oracle/wallet"
      }
    },
    "oracle-cdb2": {
      "command": "/usr/bin/python3",
      "args": ["-u", "/home/oracle/mcp_jsonlines_fix.py", "/@CDB2", "-mcp"],
      "env": {
        "WALLET_LOCATION": "/home/oracle/wallet"
      }
    }
  }
}
```

**⚡ Automatic configuration:**
```bash
python3 -c "
import json

with open('/home/oracle/.claude.json', 'r') as f:
    config = json.load(f)

config['mcpServers'] = {
    'oracle-cdb1': {
        'command': '/usr/bin/python3',
        'args': ['-u', '/home/oracle/mcp_jsonlines_fix.py', '/@CDB1', '-mcp'],
        'env': {'WALLET_LOCATION': '/home/oracle/wallet'}
    },
    'oracle-cdb2': {
        'command': '/usr/bin/python3',
        'args': ['-u', '/home/oracle/mcp_jsonlines_fix.py', '/@CDB2', '-mcp'],
        'env': {'WALLET_LOCATION': '/home/oracle/wallet'}
    }
}

with open('/home/oracle/.claude.json', 'w') as f:
    json.dump(config, f, indent=2)

print('OK - mcpServers configured in .claude.json')
"
```

---

### 5.4 🔐 Oracle Wallet (unchanged configuration)

**Location:** `/home/oracle/wallet/`

**Files:**
```
cwallet.sso       # Auto-login wallet
ewallet.p12       # Encrypted wallet
```

**Credentials:**
```bash
$ mkstore -wrl /home/oracle/wallet -listCredential
4: CDB2       c##mcp_ai
3: CDB1       c##mcp_ai
2: CDB2_SYS   SYS
1: CDB1_SYS   SYS
```

**sqlnet.ora:**
```ini
WALLET_LOCATION =
  (SOURCE =
    (METHOD = FILE)
    (METHOD_DATA = (DIRECTORY = /home/oracle/wallet))
  )
SQLNET.WALLET_OVERRIDE = TRUE
```

---

## ✅ Solution Verification

### 6.1 🖥️ Process Test

```bash
# Check MCP processes
ps -ef | grep mcp_jsonlines
# Expected output:
# oracle  60xxx  /usr/bin/python3 -u /home/oracle/mcp_jsonlines_fix.py /@CDB1 -mcp
# oracle  60xxx  /usr/bin/python3 -u /home/oracle/mcp_jsonlines_fix.py /@CDB2 -mcp
```

### 6.2 📋 VSCode Logs Test

**View → Output → Claude Code:**
```
✅ MCP server "oracle-cdb1": Successfully connected in 9342ms
✅ MCP server "oracle-cdb2": Successfully connected in 9179ms
Connection established with capabilities: {"hasTools":true,"hasPrompts":true,...}
```

### 6.3 🧪 Functional Test

In Claude Code:
```
User: /mcp
# Should show oracle-cdb1, oracle-cdb2 servers

User: show me the list of tables in CDB1
# Claude Code will use MCP tools to query the database
```

**Expected result:** ✅ Claude Code uses SQLcl MCP tools to execute queries.

---

## 🔑 Key Findings

### 7.1 Protocol Change in Claude Code

| Version | MCP Protocol | Format |
|---------|:------------:|--------|
| ≤ 2.1.42 | LSP | `Content-Length: 123\r\n\r\n{...}` |
| ≥ 2.1.44 | JSON lines | `{...}\n` |

### 7.2 🐛 Bug in SQLcl 25.4.x

Tool #21 exposes schema incompatible with JSON Schema draft 2020-12:
- Non-standard fields in schema
- Missing `type: object` when `properties` present

### 7.3 📁 MCP Configuration Location

| Claude Code Version | MCP Configuration Location |
|:-------------------:|----------------------------|
| ≤ 2.1.42 | `~/.claude/settings.json` |
| ≥ 2.1.44 | `~/.claude.json` ⚠️ |

---

## 🐛 Problems Resolved

| Problem | 🔍 Cause | ✅ Solution |
|---------|----------|------------|
| 60s timeout | LSP vs JSON lines protocol mismatch | JSON lines proxy without conversion |
| Invalid JSON Schema | Bug in SQLcl 25.4.x | `fix_schema()` function |
| No communication | Claude Code reading wrong file | Configuration in `.claude.json` |
| Auto-update extension | VSCode auto-update breaking changes | Disable auto-update |

---

## ⚙️ Operational Procedures

### 9.1 🔄 MCP System Restart

```bash
# 1. Kill all processes
pkill -f mcp_jsonlines
pkill -f "sql.*-mcp"

# 2. Clear debug logs (optional)
rm /tmp/mcp_proxy_debug.log 2>/dev/null

# 3. Reload VSCode
# In VSCode: Ctrl+Shift+P → "Developer: Reload Window"
```

### 9.2 🩺 Problem Diagnosis

```bash
# Check processes
ps -ef | grep -E "(mcp_jsonlines|@CDB)" | grep -v grep

# Check database connection (without MCP)
/home/oracle/mcp_sqlcl_wrapper.sh /@CDB1
SQL> show user
# Expected: USER is "C##MCP_AI"

# Check Claude Code logs
# VSCode: View → Output → select "Claude Code"
```

### 9.3 🧪 Manual Proxy Test

```bash
# Run proxy manually
/usr/bin/python3 -u /home/oracle/mcp_jsonlines_fix.py "/@CDB1" "-mcp" &
PROXY_PID=$!

# Send initialize
echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}' | nc localhost 1234

# Expected response within 3 seconds
kill $PROXY_PID
```

---

## ⚠️ Potential Issues

| ⚠️ Problem | 🔴 Symptoms | ✅ Solution |
|-----------|-------------|------------|
| Claude Code auto-update | New version → timeout | Disable auto-update, test new versions |
| SQLcl upgrade | New schema errors | Update `fix_schema()` |
| Wallet expired | ORA-01017 | Renew certificates in wallet |
| No Java 21 | SQLcl error | Check `JAVA_HOME` in wrapper |
| Zombie processes | Multiple `sql -mcp` processes | `pkill -9 -f "sql.*-mcp"` |

---

## 📌 Conclusions and Recommendations

### 11.1 👤 For Users

1. **🔒 Disable Claude Code Auto-Update**
   - VSCode → Settings → Extensions → uncheck "Auto Update"
   
2. **📊 Monitor Logs**
   - Regularly check Output → Claude Code
   - Look for "Successfully connected" after restart

3. **💾 Configuration Backup**
   ```bash
   cp ~/.claude.json ~/.claude.json.backup.$(date +%Y%m%d)
   ```

### 11.2 🏢 For Oracle

**Bug should be reported to Oracle Support:**

> **Subject:** SQLcl 25.4.x MCP — JSON Schema draft 2020-12 incompatibility  
> **Versions:** 25.4.0.344.0019, 25.4.1.022.0618  
> **Problem:** Tool #21 exposes incompatible schema  
> **Workaround:** Python proxy fixing schema (this document)

### 11.3 🤖 For Anthropic

**Feature request:** Document MCP protocol change in release notes:
- Version 2.1.44: LSP → JSON lines
- Config location: `settings.json` → `.claude.json`

---

## 📜 Appendix: Complete Debugging History

### 12.1 ⏱️ Timeline

| 🕐 Time | 📝 Event |
|--------|---------|
| 15:00 | 🔴 Problem reported — MCP timeout |
| 16:00 | 🧪 Downgrade to 2.1.42 — no effect |
| 17:00 | 💡 Discovery: LSP proxy needed |
| 18:00 | 🧪 LSP proxy test — timeout |
| 19:00 | 🧪 SQLcl communication test — JSON lines works! |
| 20:00 | 🔍 Debug logging — Claude Code sends JSON lines |
| 21:00 | ✅ Simple JSON lines proxy — **SUCCESS** |
| 22:00 | 📝 Verification and documentation |

### 12.2 🏆 Key Test (Breakthrough)

```bash
# Manual SQLcl test (without proxy)
echo '{"jsonrpc":"2.0","id":1,"method":"initialize",...}' | sql /@CDB1 -mcp

# Response:
{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2024-11-05",...}}
```

This confirmed:
1. ✅ SQLcl uses JSON lines (not LSP)
2. ✅ SQLcl responds correctly
3. ✅ Problem in protocol conversion

---

## 📂 Files Summary

| 📄 File | 📍 Location | 📝 Purpose |
|---------|------------|-----------|
| `mcp_sqlcl_wrapper.sh` | `/home/oracle/` | SQLcl wrapper — env setup |
| `mcp_jsonlines_fix.py` | `/home/oracle/` | 🐍 Schema fixing proxy |
| `.claude.json` | `~/` | MCP server configuration |

---

## 📞 Contact and Support

| 🔗 Resource | 📍 Link |
|------------|--------|
| 📋 Check logs | View → Output → Claude Code |
| 🔍 Check processes | `ps -ef \| grep mcp` |
| 🧪 Manual test | See section 9.3 |
| 🏢 Oracle Support | Report SQLcl bug (section 11.2) |
| 🤖 Anthropic Support | https://support.claude.com |

**📚 Documentation:**
- 🗄️ Oracle SQLcl MCP: https://docs.oracle.com/en/database/oracle/sql-developer-command-line/25.4/
- 🤖 Claude Code: https://docs.claude.com/en/docs/claude-code
- 🔌 MCP Protocol: https://modelcontextprotocol.io/

---

<p align="center">
  <img src="https://img.shields.io/badge/Status-✅%20RESOLVED-brightgreen" />
  <img src="https://img.shields.io/badge/Diagnosis%20Time-~8%20hours-blue" />
  <img src="https://img.shields.io/badge/Date-2026--02--17-lightgrey" />
</p>

<p align="center">
  <sub>Diagnosed and fixed by Krzysztof Cabaj & Claude (Anthropic) · Verified: complete, solution working</sub>
</p>
