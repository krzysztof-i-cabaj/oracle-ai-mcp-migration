# 🔌 Raport Konfiguracji Serwera MCP (Model Context Protocol) dla Oracle Database

![Oracle Version](https://img.shields.io/badge/Oracle-26ai%2023.26.1.0.0-red)
![Agent](https://img.shields.io/badge/Agent-Gemini%203%20Pro%20(Antigravity)-blue)
![Protocol](https://img.shields.io/badge/Protocol-MCP%20(STDIO)-green)
![Tool](https://img.shields.io/badge/Tool-Oracle%20SQLcl%2025.4-orange)
![Security](https://img.shields.io/badge/Security-Oracle%20Wallet%20(SEPS)-blueviolet)
![OS](https://img.shields.io/badge/OS-Oracle%20Linux%209-brightgreen)

---

| Parametr | Wartość |
|---|---|
| 🤖 **Aplikacja** | Antigravity (Gemini) |
| 🗄️ **Bazy Danych** | CDB1, CDB2 (Oracle Database 23.26.1.0.0) |
| 🔧 **Narzędzie serwera MCP** | Oracle SQLcl 25.4 |
| 📄 **Plik konfiguracyjny** | `/home/oracle/.gemini/antigravity/mcp_config.json` |

---

## 🏗️ Architektura Połączenia

Wykorzystano wbudowaną w natywne narzędzie bazodanowe Oracle SQLcl funkcjonalność uruchamiania serwera MCP z bezpośrednim mapowaniem bezpiecznego połączenia za pomocą usługi SEPS (Secure External Password Store).

### 🔐 1. Uwierzytelnianie
Użyto magazynu poświadczeń Oracle Wallet (`mkstore`) zlokalizowanego w ścieżce `/home/oracle/wallet`. Magazyn ten ukrywa i chroni hasła dla użytkownika `c##mcp_ai` w bazach CDB1 i CDB2. Pomyślne zastosowanie powiązania w portfelu umożliwia wykorzystanie tzw. skróconego łańcucha logowania w postacji `/@CDB1` i `/@CDB2`.

### ⚙️ 2. Serwer Wykonawczy
Silnikiem MCP jest instancja SQLcl znajdująca się pod ścieżką `/u01/app/oracle/product/26.0.0/dbhome_1/sqlcl/bin/sql`. Wykorzystany jest w tym celu dedykowany skrypt uruchomieniowy `/home/oracle/mcp_sqlcl_wrapper.sh`, który izoluje instalację od ustawień użytkownika min. `login.sql` (usuwając opcje generujące błędy formatowania, np. nieznane dla SQLcl parametry SET lines). Jest on powołany z flagą `-mcp` która odpowiada za włączenie trybu Model Context Protocol nasłuchującą na standardowe wejście/wyjście (STDIO) i realizującą połączenie z daną bazą docelową.

---

## 📄 Finalny Plik Konfiguracyjny MCP

```json
{
  "mcpServers": {
    "oracle-cdb1": {
      "command": "/home/oracle/mcp_sqlcl_wrapper.sh",
      "args": [
        "-mcp",
        "/@CDB1"
      ]
    },
    "oracle-cdb2": {
      "command": "/home/oracle/mcp_sqlcl_wrapper.sh",
      "args": [
        "-mcp",
        "/@CDB2"
      ]
    }
  }
}
```

---

## 🔍 Opis Poszczególnych Zmiennych i Argumentów

| Parametr | Opis |
|---|---|
| 🏷️ **`oracle-cdb1` / `oracle-cdb2`** | Nazwy profili serwerów wyeksponowanych w agencie, służących do ukierunkowania poleceń AI na konkretną przestrzeń bazodanową. |
| 📜 **`command`** | Ścieżka do skryptu pośredniczącego `/home/oracle/mcp_sqlcl_wrapper.sh`, który zapewnia twardy reset środowiska (np. ignorowanie `login.sql`, wymuszenie UTF-8). Powołuje on następnie natywne wywołanie skryptu uruchomieniowego SQLcl. |
| 🚩 **`args` → `["-mcp"]`** | Parametr wskazujący, że SQLcl nie uruchamia się w trybie standardowego wiersza poleceń SQL, tylko natywnie wstaje jako serwer integrujący LLM poprzez protokół Model Context Protocol. |
| 🔑 **`args` → `["/@CDB1"]`** | Połączenie z daną bazą wskazaną poprzez alias bez konieczności przekazywania loginu i hasła. Wszystkie informacje uwierzytelniające pobierane są poprzez natywnego klienta Oracle (i wpis w pliku `sqlnet.ora` dla parametru `WALLET_LOCATION`) z bezpiecznego zmagazynowanego pliku portfela na serwerze fizycznym. |

---

## ✅ Testy

- [x] 🔎 Detekcja zainstalowanych komponentów.
- [x] 🧪 Odkrycie i weryfikacja obsługi parametru `-mcp` przez zainstalowanego po stronie systemu klienta `sqlcl`.
- [x] 🛡️ Weryfikacja działania autoryzacji SEPS przez Oracle Wallet dla aliasu `/@CDB1` — skuteczne pozyskanie danych z bazy (komenda powrotem zwróciła informacje o uruchomionej instancji i wersji 23.26.1). Wszelkie zapytania kierowane na ten konfiguracyjny protokół zadziałają tak długo jak aktywny będzie wallet i uprawnienia użytkownika `c##mcp_ai`.
