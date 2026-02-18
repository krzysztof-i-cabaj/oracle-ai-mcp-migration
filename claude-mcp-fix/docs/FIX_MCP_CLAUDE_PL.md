# Raport: Naprawa integracji Oracle SQLcl MCP z Claude Code

**Data:** 2026-02-17  
**Środowisko:** Oracle 26ai, SQLcl 25.4.1, Claude Code 2.1.44, Linux OEL9  
**Operator:** oracle@ora26ai

---

## 1. Problem początkowy

### 1.1 Objawy
Po restarcie systemu i aktualizacji rozszerzenia Claude Code w VSCode (z wersji 2.1.42 → 2.1.44):

```
API Error: 400 {"type":"error","error":{"type":"invalid_request_error",
"message":"tools.21.custom input_schema: JSON schema is invalid. 
It must match JSON Schema draft 2020-12"}}
```

- Serwery MCP (oracle-cdb1, oracle-cdb2) nie były widoczne w Claude Code
- Timeout połączenia: 60 sekund, następnie błąd połączenia
- Procesy SQLcl MCP uruchamiały się na serwerze, ale nie komunikowały się z Claude Code

### 1.2 Konfiguracja początkowa

Pliki:
- `/home/oracle/.claude.json` — zawierał konfigurację MCP (błędne miejsce)
- `/home/oracle/.claude/settings.json` — pusty `{}`
- `/home/oracle/mcp_sqlcl_wrapper.sh` — wrapper dla SQLcl z Java 21

---

## 2. Diagnoza

### 2.1 Wykryte przyczyny

#### Przyczyna #1: Aktualizacja rozszerzenia Claude Code
- Rozszerzenie automatycznie zaktualizowało się 3 godziny przed zgłoszeniem problemu
- Wersja 2.1.44 wprowadziła ostrzejszą walidację JSON Schema draft 2020-12
- SQLcl 25.4.x eksponuje schemat tool #21 niezgodny z tym standardem

#### Przyczyna #2: Niezgodność protokołu komunikacji
**Kluczowe odkrycie przez strace:**

```bash
# SQLcl MCP używa JSON lines (jedna linia = jedna wiadomość JSON)
{"jsonrpc":"2.0","id":1,"result":{...}}\n

# Claude Code oczekuje LSP format (Content-Length headers)
Content-Length: 151\r\n
\r\n
{"jsonrpc":"2.0","id":1,"result":{...}}
```

SQLcl nie odpowiadał, ponieważ:
- Czekał na format JSON lines
- Claude Code wysyłał format LSP
- Brak konwersji = brak komunikacji

#### Przyczyna #3: Błędna lokalizacja konfiguracji MCP
Claude Code czyta konfigurację z `~/.claude/settings.json`, nie z `~/.claude.json`

---

## 3. Rozwiązanie

### 3.1 Architektura finalna

```
Claude Code (VSCode)
    │
    ├─ używa: LSP format (Content-Length headers)
    │
    └─► Python Proxy (/home/oracle/mcp_lsp_to_jsonlines.py)
            │
            ├─ konwertuje: LSP ↔ JSON lines
            ├─ naprawia: JSON Schema draft 2020-12
            │
            └─► SQLcl MCP Server
                    │
                    ├─ /home/oracle/mcp_sqlcl_wrapper.sh
                    ├─ SQLcl 25.4.1 z Java 21
                    │
                    └─► Oracle Database 26ai
                            │
                            ├─ CDB1 @ c##mcp_ai (Oracle Wallet)
                            └─ CDB2 @ c##mcp_ai (Oracle Wallet)
```

---

## 4. Implementacja rozwiązania

### 4.1 Plik #1: `/home/oracle/mcp_sqlcl_wrapper.sh`

```bash
#!/bin/bash
unset SQLPATH
unset ORACLE_PATH

export ORACLE_HOME=/u01/app/oracle/product/26.0.0/dbhome_1
export TNS_ADMIN=$ORACLE_HOME/network/admin
export PATH=/home/oracle/sqlcl/bin:$PATH

# Java 21 wymagana przez SQLcl -mcp (minimum Java 17)
export JAVA_HOME=/usr/lib/jvm/java-21-openjdk-21.0.10.0.7-1.0.1.el9.x86_64

export NLS_LANG=AMERICAN_AMERICA.AL32UTF8

/home/oracle/sqlcl/bin/sql "$@"
```

**Uprawnienia:**
```bash
chmod +x /home/oracle/mcp_sqlcl_wrapper.sh
```

---

### 4.2 Plik #2: `/home/oracle/mcp_lsp_to_jsonlines.py`

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

**Uprawnienia:**
```bash
chmod +x /home/oracle/mcp_lsp_to_jsonlines.py
```

---

### 4.3 Plik #3: `/home/oracle/.claude/settings.json`

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

### 4.4 Konfiguracja Oracle Wallet

**Lokalizacja:** `/home/oracle/wallet/`

**Pliki:**
```
cwallet.sso       # Auto-login wallet
ewallet.p12       # Encrypted wallet
```

**Zawartość (poświadczenia):**
```bash
mkstore -wrl /home/oracle/wallet -listCredential
# 4: CDB2       c##mcp_ai
# 3: CDB1       c##mcp_ai
# 2: CDB2_SYS   SYS
# 1: CDB1_SYS   SYS
```

**Konfiguracja sqlnet.ora:**
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

## 5. Weryfikacja rozwiązania

### 5.1 Test komunikacji proxy

```bash
# Test manualny JSON lines → LSP
mkfifo /tmp/test_in /tmp/test_out
/home/oracle/mcp_sqlcl_wrapper.sh "/@CDB1" "-mcp" < /tmp/test_in > /tmp/test_out 2>&1 &

echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}' > /tmp/test_in &

timeout 5 cat /tmp/test_out
```

**Oczekiwany wynik:**
```json
{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2024-11-05","capabilities":{"logging":{},"prompts":{"listChanged":true},"resources":{"subscribe":true,"listChanged":true},"tools":{"listChanged":true}},"serverInfo":{"name":"sqlcl-mcp-server","version":"1.0.0"}}}
```

### 5.2 Test w Claude Code

1. Wyczyść stare procesy:
```bash
pkill -f mcp
```

2. W VSCode:
   - `Ctrl+Shift+P` → **"Developer: Reload Window"**
   - Otwórz Claude Code
   - Sprawdź **"Manage MCP Servers"**
   - Powinny być widoczne: `oracle-cdb1`, `oracle-cdb2` ze statusem **"Running"**

3. Test działania:
```
User w Claude Code: "pokaż mi listę tabel w CDB1"
```

Oczekiwany wynik: Claude Code użyje narzędzi MCP do zapytania bazy danych.

---

## 6. Rozwiązane problemy

### 6.1 Problem: JSON Schema draft 2020-12
**Rozwiązanie:** Funkcja `fix_schema()` w proxy usuwa niekompatybilne pola z schematów narzędzi SQLcl.

### 6.2 Problem: Niezgodność protokołu (LSP vs JSON lines)
**Rozwiązanie:** Proxy wykonuje translację w obie strony:
- `read_lsp()` — parsuje Content-Length headers od Claude Code
- `write_lsp()` — pakuje odpowiedzi SQLcl w format LSP

### 6.3 Problem: Timeout 60s
**Rozwiązanie:** Po naprawie protokołu komunikacja działa natychmiast, timeout nie jest osiągany.

---

## 7. Potencjalne problemy i rozwiązania

| Problem | Objaw | Rozwiązanie |
|---------|-------|-------------|
| `Connection timeout 60s` | Serwery MCP nie odpowiadają | Sprawdź czy procesy żyją: `ps -ef \| grep mcp` |
| `Invalid JSON Schema` | Błąd 400 w Claude Code | Proxy `fix_schema()` powinien to naprawić automatycznie |
| `ORA-01017: invalid credentials` | Błąd połączenia z bazą | Sprawdź wallet: `mkstore -wrl /home/oracle/wallet -listCredential` |
| Procesy zombie | Wiele procesów `sql -mcp` | Zabij: `pkill -f "sql.*-mcp"` |
| Proxy nie startuje | Brak procesów Python | Sprawdź uprawnienia: `chmod +x /home/oracle/mcp_lsp_to_jsonlines.py` |

---

## 8. Komendy diagnostyczne

### 8.1 Sprawdzanie statusu

```bash
# Procesy MCP
ps -ef | grep -E "(mcp_proxy|mcp_lsp|@CDB)" | grep -v grep

# Logi Claude Code (VSCode)
# View → Output → wybierz "Claude Code" z dropdown

# Test połączenia z bazą (bez MCP)
/home/oracle/mcp_sqlcl_wrapper.sh /@CDB1
```

### 8.2 Restart całego systemu MCP

```bash
# 1. Zabij wszystkie procesy
pkill -f mcp

# 2. Usuń stare pliki tymczasowe
rm -f /tmp/mcp_* 2>/dev/null

# 3. Reload VSCode
# W VSCode: Ctrl+Shift+P → "Developer: Reload Window"
```

---

## 9. Wnioski i rekomendacje

### 9.1 Główne odkrycia

1. **SQLcl MCP używa JSON lines, nie LSP** — dokumentacja Oracle nie wspomina o tym wyraźnie
2. **SQLcl 25.4.x ma bug w schemacie** — tool #21 eksponuje niekompatybilny JSON Schema
3. **Claude Code aktualizuje się automatycznie** — nowe wersje mogą wprowadzać breaking changes

### 9.2 Rekomendacje

1. **Zgłoś bug do Oracle Support:**
   - Temat: "SQLcl 25.4.x MCP — JSON Schema draft 2020-12 incompatibility"
   - SR powinno zawierać logi i informację o tool #21

2. **Wyłącz auto-update rozszerzenia Claude Code:**
   - VSCode → Settings → Extensions → odznacz "Auto Update"

3. **Monitoring:**
   - Regularnie sprawdzaj `ps -ef | grep mcp`
   - Monitoruj logi w VSCode Output → Claude Code

4. **Backup konfiguracji:**
```bash
cp ~/.claude/settings.json ~/.claude/settings.json.backup
cp /home/oracle/mcp_lsp_to_jsonlines.py /home/oracle/mcp_lsp_to_jsonlines.py.backup
```

---

## 10. Appendix: Pełna ścieżka debugowania

### 10.1 Próby i błędy

1. ❌ Downgrade Claude Code 2.1.44 → 2.1.42 — nie pomogło (problem w SQLcl)
2. ❌ Proxy JSON-RPC z nagłówkami — SQLcl nie odpowiadał
3. ❌ Próba komunikacji przez TCP socket — SQLcl używa stdio
4. ❌ Test z `Content-Length` przez pipe — brak odpowiedzi
5. ✅ **Test z czystym JSON + newline — odpowiedź!**

### 10.2 Kluczowy test (breakthrough)

```bash
echo '{"jsonrpc":"2.0","id":1,"method":"initialize",...}' > /tmp/mcp_in &
timeout 5 cat /tmp/mcp_out

# Output:
{"jsonrpc":"2.0","id":1,"result":{...}}
```

To potwierdziło, że SQLcl używa JSON lines, a nie LSP.

---

## 11. Kontakt i support

**W przypadku problemów:**

1. Sprawdź logi VSCode: View → Output → Claude Code
2. Sprawdź procesy: `ps -ef | grep mcp`
3. Test manualny proxy (sekcja 5.1)
4. Jeśli problem w SQLcl: Oracle Support SR
5. Jeśli problem w Claude Code: https://support.claude.com

**Dokumentacja:**
- Oracle SQLcl MCP: https://docs.oracle.com/en/database/oracle/sql-developer-command-line/25.4/sqcug/using-sqlcl-mcp-server.html
- Claude Code: https://docs.claude.com/en/docs/claude-code

---

**Koniec raportu**  
Przygotował:  Krzysztof Cabaj & Claude (Anthropic)  
Data: 2026-02-17
