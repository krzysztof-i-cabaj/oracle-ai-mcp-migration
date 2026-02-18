# 🔧 Integracja Oracle SQLcl MCP z Claude Code — Przewodnik naprawy

![Status](https://img.shields.io/badge/Status-✅%20ROZWIĄZANE-brightgreen)
![Claude Code](https://img.shields.io/badge/Claude%20Code-2.1.45-blueviolet)
![SQLcl](https://img.shields.io/badge/SQLcl-25.4.1-blue)
![Oracle](https://img.shields.io/badge/Oracle-26ai-red)
![OS](https://img.shields.io/badge/OS-OEL9%20Linux-lightgrey)
![Protocol](https://img.shields.io/badge/Protokół-JSON%20lines-orange)
![Fix](https://img.shields.io/badge/Poprawka-Python%20Proxy-yellow)

> **TL;DR** — Claude Code 2.1.44+ zmienił protokół MCP z LSP na JSON lines. Lekki proxy w Pythonie naprawia zarówno niezgodność komunikacyjną, jak i błąd JSON Schema w SQLcl.

---

## 📋 Spis treści

- [Streszczenie wykonawcze](#-streszczenie-wykonawcze)
- [Pierwotny problem](#-pierwotny-problem)
- [Proces diagnozy](#-proces-diagnozy)
- [Ostateczne rozwiązanie](#-ostateczne-rozwiązanie)
- [Implementacja](#️-implementacja)
- [Weryfikacja rozwiązania](#-weryfikacja-rozwiązania)
- [Kluczowe odkrycia](#-kluczowe-odkrycia)
- [Rozwiązane problemy](#-rozwiązane-problemy)
- [Procedury operacyjne](#️-procedury-operacyjne)
- [Potencjalne problemy](#-potencjalne-problemy)
- [Wnioski i rekomendacje](#-wnioski-i-rekomendacje)
- [Dodatek: Pełna historia debugowania](#-dodatek-pełna-historia-debugowania)

---

## 🎯 Streszczenie wykonawcze

### 🔴 Problem
Po aktualizacji rozszerzenia Claude Code (2.1.42 → 2.1.44 → 2.1.45) serwery Oracle SQLcl MCP przestały działać z błędem timeout 60s.

### 🔬 Przyczyna źródłowa
Claude Code 2.1.44+ **zmienił protokół komunikacji MCP**:
- **Wcześniej:** Format LSP (nagłówki Content-Length)
- **Teraz:** JSON lines (jedna linia JSON = jedna wiadomość)

### ✅ Rozwiązanie
Prosty proxy w Pythonie, który:
1. Przepuszcza komunikację JSON lines bez zmian
2. Naprawia schematy JSON narzędzi SQLcl do draft 2020-12

---

## 🚨 Pierwotny problem

### 2.1 Objawy
```
Connection timeout: 60 seconds
MCP server "oracle-cdb1" connection timed out after 60000ms
```

- ❌ Serwery MCP nie odpowiadają na initialize
- ❌ Procesy SQLcl uruchamiają się, ale nie komunikują
- ❌ Brak narzędzi MCP dostępnych w Claude Code

### 2.2 Środowisko

| Komponent | Wersja |
|-----------|--------|
| 🗄️ Oracle Database | 26ai Enterprise Edition |
| 🛠️ SQLcl | 25.4.1 Build 022.0618 |
| 🤖 Claude Code | 2.1.45 (automatyczna aktualizacja z 2.1.42) |
| 🐧 System | Oracle Linux 9 |
| ☕ Java | OpenJDK 21 |
| 🔐 Uwierzytelnianie | Oracle Wallet (SEPS) |

---

## 🔍 Proces diagnozy

### 3.1 Metoda prób i błędów

| # | 🧪 Hipoteza | Test | Wynik |
|---|------------|------|-------|
| 1 | Problem z JSON schema | Powrót do 2.1.42 | ❌ Brak efektu |
| 2 | SQLcl używa formatu LSP | Proxy LSP ↔ JSON lines | ❌ Timeout |
| 3 | SQLcl używa gniazda TCP | Test portów | ❌ Używa stdio |
| 4 | Buforowanie stdout | Test niebuforowanego I/O | ❌ Timeout |
| 5 | Claude Code zmienił protokół | Proxy z logowaniem debug | ✅ **SUKCES** |

### 3.2 🔑 Kluczowe odkrycie

**Ręczny test z logowaniem debug:**
```bash
[22:58:59] read_lsp: headers={'{"method"': '"initialize",...'}, data=None
```

Claude Code **nie wysyła Content-Length** — wysyła czyste JSON!

```json
{"method":"initialize","params":{"protocolVersion":"2025-11-25",...},"jsonrpc":"2.0","id":0}
```

### 3.3 ⚠️ Dodatkowy problem: JSON Schema

SQLcl 25.4.x eksponuje narzędzie #21 z niekompatybilnym schematem (draft-07 zamiast draft 2020-12).

---

## 💡 Ostateczne rozwiązanie

### 4.1 Architektura

```
Claude Code 2.1.45
    │
    ├─ JSON lines ({"jsonrpc":"2.0",...}\n)
    │
    └─► 🐍 Python Proxy (/home/oracle/mcp_jsonlines_fix.py)
            │
            ├─ Przepuszcza JSON lines bez zmian
            ├─ Naprawia JSON Schema draft 2020-12
            │
            └─► 🛠️ Serwer SQLcl MCP
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

## 🛠️ Implementacja

### 5.1 Plik #1: `/home/oracle/mcp_sqlcl_wrapper.sh`

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

### 5.2 Plik #2: `/home/oracle/mcp_jsonlines_fix.py`

```python
#!/usr/bin/env python3
"""Prosty proxy: JSON lines we/wy, tylko naprawia schemat"""
import sys, json, subprocess, threading

def fix_schema(schema):
    """Napraw JSON Schema do draft 2020-12"""
    if not isinstance(schema, dict):
        return
    # Usuń niestandardowe pola
    for k in list(schema.keys()):
        if k not in ['type','properties','required','description','items',
                     'enum','default','title','anyOf','oneOf','allOf',
                     'not','format','minimum','maximum','minLength',
                     'maxLength','pattern','additionalProperties','const']:
            del schema[k]
    # Upewnij się, że type: object jest obecny
    if 'properties' in schema and 'type' not in schema:
        schema['type'] = 'object'
    # Rekurencja do zagnieżdżonych właściwości
    for v in schema.get('properties', {}).values():
        fix_schema(v)

# Uruchom SQLcl MCP
proc = subprocess.Popen(
    ['/home/oracle/mcp_sqlcl_wrapper.sh'] + sys.argv[1:],
    stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=sys.stderr,
    bufsize=0  # Niebuforowany
)

# Przekazuj stdin: JSON lines → SQLcl
def forward_stdin():
    for line in sys.stdin:
        proc.stdin.write(line.encode())
        proc.stdin.flush()

t = threading.Thread(target=forward_stdin, daemon=True)
t.start()

# Przekazuj stdout: SQLcl → Claude Code (z naprawą schematu)
for line in iter(proc.stdout.readline, b''):
    line = line.strip()
    if not line:
        continue
    try:
        data = json.loads(line)
        # Napraw błąd schematu w odpowiedzi narzędzi
        if 'result' in data and 'tools' in data.get('result', {}):
            for tool in data['result']['tools']:
                if 'inputSchema' in tool:
                    fix_schema(tool['inputSchema'])
        sys.stdout.write(json.dumps(data) + '\n')
        sys.stdout.flush()
    except:
        pass
```

**Uprawnienia:**
```bash
chmod +x /home/oracle/mcp_jsonlines_fix.py
```

---

### 5.3 Plik #3: `/home/oracle/.claude.json`

> **⚠️ WAŻNE:** Claude Code 2.1.44+ odczytuje konfigurację MCP z `~/.claude.json`, **NIE** z `~/.claude/settings.json`!

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

**⚡ Automatyczna konfiguracja:**
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

print('OK - mcpServers skonfigurowane w .claude.json')
"
```

---

### 5.4 🔐 Oracle Wallet (konfiguracja bez zmian)

**Lokalizacja:** `/home/oracle/wallet/`

**Pliki:**
```
cwallet.sso       # Wallet z automatycznym logowaniem
ewallet.p12       # Zaszyfrowany wallet
```

**Dane uwierzytelniające:**
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

## ✅ Weryfikacja rozwiązania

### 6.1 🖥️ Test procesów

```bash
# Sprawdź procesy MCP
ps -ef | grep mcp_jsonlines
# Oczekiwany wynik:
# oracle  60xxx  /usr/bin/python3 -u /home/oracle/mcp_jsonlines_fix.py /@CDB1 -mcp
# oracle  60xxx  /usr/bin/python3 -u /home/oracle/mcp_jsonlines_fix.py /@CDB2 -mcp
```

### 6.2 📋 Test logów VSCode

**Widok → Wyjście → Claude Code:**
```
✅ MCP server "oracle-cdb1": Successfully connected in 9342ms
✅ MCP server "oracle-cdb2": Successfully connected in 9179ms
Connection established with capabilities: {"hasTools":true,"hasPrompts":true,...}
```

### 6.3 🧪 Test funkcjonalny

W Claude Code:
```
Użytkownik: /mcp
# Powinno wyświetlić serwery oracle-cdb1, oracle-cdb2

Użytkownik: pokaż mi listę tabel w CDB1
# Claude Code użyje narzędzi MCP do zapytania bazy danych
```

**Oczekiwany wynik:** ✅ Claude Code używa narzędzi SQLcl MCP do wykonywania zapytań.

---

## 🔑 Kluczowe odkrycia

### 7.1 Zmiana protokołu w Claude Code

| Wersja | Protokół MCP | Format |
|--------|:------------:|--------|
| ≤ 2.1.42 | LSP | `Content-Length: 123\r\n\r\n{...}` |
| ≥ 2.1.44 | JSON lines | `{...}\n` |

### 7.2 🐛 Błąd w SQLcl 25.4.x

Narzędzie #21 eksponuje schemat niekompatybilny z JSON Schema draft 2020-12:
- Niestandardowe pola w schemacie
- Brak `type: object` przy obecności `properties`

### 7.3 📁 Lokalizacja konfiguracji MCP

| Wersja Claude Code | Lokalizacja konfiguracji MCP |
|:-----------------:|------------------------------|
| ≤ 2.1.42 | `~/.claude/settings.json` |
| ≥ 2.1.44 | `~/.claude.json` ⚠️ |

---

## 🐛 Rozwiązane problemy

| Problem | 🔍 Przyczyna | ✅ Rozwiązanie |
|---------|-------------|--------------|
| Timeout 60s | Niezgodność protokołu LSP vs JSON lines | Proxy JSON lines bez konwersji |
| Nieprawidłowy JSON Schema | Błąd w SQLcl 25.4.x | Funkcja `fix_schema()` |
| Brak komunikacji | Claude Code czyta zły plik | Konfiguracja w `.claude.json` |
| Automatyczna aktualizacja rozszerzenia | Przełomowe zmiany w VSCode | Wyłącz automatyczną aktualizację |

---

## ⚙️ Procedury operacyjne

### 9.1 🔄 Restart systemu MCP

```bash
# 1. Zatrzymaj wszystkie procesy
pkill -f mcp_jsonlines
pkill -f "sql.*-mcp"

# 2. Wyczyść logi debug (opcjonalnie)
rm /tmp/mcp_proxy_debug.log 2>/dev/null

# 3. Przeładuj VSCode
# W VSCode: Ctrl+Shift+P → "Developer: Reload Window"
```

### 9.2 🩺 Diagnoza problemów

```bash
# Sprawdź procesy
ps -ef | grep -E "(mcp_jsonlines|@CDB)" | grep -v grep

# Sprawdź połączenie z bazą danych (bez MCP)
/home/oracle/mcp_sqlcl_wrapper.sh /@CDB1
SQL> show user
# Oczekiwany wynik: USER is "C##MCP_AI"

# Sprawdź logi Claude Code
# VSCode: Widok → Wyjście → wybierz "Claude Code"
```

### 9.3 🧪 Ręczny test proxy

```bash
# Uruchom proxy ręcznie
/usr/bin/python3 -u /home/oracle/mcp_jsonlines_fix.py "/@CDB1" "-mcp" &
PROXY_PID=$!

# Wyślij initialize
echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}' | nc localhost 1234

# Oczekiwana odpowiedź w ciągu 3 sekund
kill $PROXY_PID
```

---

## ⚠️ Potencjalne problemy

| ⚠️ Problem | 🔴 Objawy | ✅ Rozwiązanie |
|-----------|----------|--------------|
| Automatyczna aktualizacja Claude Code | Nowa wersja → timeout | Wyłącz automatyczną aktualizację, testuj nowe wersje |
| Aktualizacja SQLcl | Nowe błędy schematu | Zaktualizuj `fix_schema()` |
| Wygaśnięty wallet | ORA-01017 | Odnów certyfikaty w wallet |
| Brak Java 21 | Błąd SQLcl | Sprawdź `JAVA_HOME` w wrapperze |
| Procesy zombie | Wiele procesów `sql -mcp` | `pkill -9 -f "sql.*-mcp"` |

---

## 📌 Wnioski i rekomendacje

### 11.1 👤 Dla użytkowników

1. **🔒 Wyłącz automatyczną aktualizację Claude Code**
   - VSCode → Ustawienia → Rozszerzenia → odznacz "Auto Update"
   
2. **📊 Monitoruj logi**
   - Regularnie sprawdzaj Wyjście → Claude Code
   - Szukaj "Successfully connected" po restarcie

3. **💾 Kopia zapasowa konfiguracji**
   ```bash
   cp ~/.claude.json ~/.claude.json.backup.$(date +%Y%m%d)
   ```

### 11.2 🏢 Dla Oracle

**Błąd powinien zostać zgłoszony do Oracle Support:**

> **Temat:** SQLcl 25.4.x MCP — Niekompatybilność JSON Schema draft 2020-12  
> **Wersje:** 25.4.0.344.0019, 25.4.1.022.0618  
> **Problem:** Narzędzie #21 eksponuje niekompatybilny schemat  
> **Obejście:** Proxy Python naprawiający schemat (ten dokument)

### 11.3 🤖 Dla Anthropic

**Prośba o funkcję:** Udokumentuj zmianę protokołu MCP w notatkach wydania:
- Wersja 2.1.44: LSP → JSON lines
- Lokalizacja konfiguracji: `settings.json` → `.claude.json`

---

## 📜 Dodatek: Pełna historia debugowania

### 12.1 ⏱️ Oś czasu

| 🕐 Czas | 📝 Zdarzenie |
|--------|-------------|
| 15:00 | 🔴 Zgłoszono problem — timeout MCP |
| 16:00 | 🧪 Powrót do 2.1.42 — brak efektu |
| 17:00 | 💡 Odkrycie: potrzebny proxy LSP |
| 18:00 | 🧪 Test proxy LSP — timeout |
| 19:00 | 🧪 Test komunikacji SQLcl — JSON lines działa! |
| 20:00 | 🔍 Logowanie debug — Claude Code wysyła JSON lines |
| 21:00 | ✅ Prosty proxy JSON lines — **SUKCES** |
| 22:00 | 📝 Weryfikacja i dokumentacja |

### 12.2 🏆 Kluczowy test (przełom)

```bash
# Ręczny test SQLcl (bez proxy)
echo '{"jsonrpc":"2.0","id":1,"method":"initialize",...}' | sql /@CDB1 -mcp

# Odpowiedź:
{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2024-11-05",...}}
```

To potwierdziło:
1. ✅ SQLcl używa JSON lines (nie LSP)
2. ✅ SQLcl odpowiada poprawnie
3. ✅ Problem leżał w konwersji protokołu

---

## 📂 Podsumowanie plików

| 📄 Plik | 📍 Lokalizacja | 📝 Cel |
|---------|--------------|-------|
| `mcp_sqlcl_wrapper.sh` | `/home/oracle/` | Wrapper SQLcl — konfiguracja środowiska |
| `mcp_jsonlines_fix.py` | `/home/oracle/` | 🐍 Proxy naprawiający schemat |
| `.claude.json` | `~/` | Konfiguracja serwerów MCP |

---

## 📞 Kontakt i wsparcie

| 🔗 Zasób | 📍 Link |
|---------|--------|
| 📋 Sprawdź logi | Widok → Wyjście → Claude Code |
| 🔍 Sprawdź procesy | `ps -ef \| grep mcp` |
| 🧪 Ręczny test | Patrz sekcja 9.3 |
| 🏢 Oracle Support | Zgłoś błąd SQLcl (sekcja 11.2) |
| 🤖 Anthropic Support | https://support.claude.com |

**📚 Dokumentacja:**
- 🗄️ Oracle SQLcl MCP: https://docs.oracle.com/en/database/oracle/sql-developer-command-line/25.4/
- 🤖 Claude Code: https://docs.claude.com/en/docs/claude-code
- 🔌 Protokół MCP: https://modelcontextprotocol.io/

---

<p align="center">
  <img src="https://img.shields.io/badge/Status-✅%20ROZWIĄZANE-brightgreen" />
  <img src="https://img.shields.io/badge/Czas%20diagnozy-~8%20godzin-blue" />
  <img src="https://img.shields.io/badge/Data-2026--02--17-lightgrey" />
</p>

<p align="center">
  <sub>Zdiagnozowane i naprawione przez Krzysztofa Cabaj i Claude (Anthropic) · Zweryfikowano: kompletne, rozwiązanie działa</sub>
</p>
