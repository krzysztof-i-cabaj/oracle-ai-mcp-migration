# 🔌 MCP Server Configuration Report (Model Context Protocol) for Oracle Database

![Oracle Version](https://img.shields.io/badge/Oracle-26ai%2023.26.1.0.0-red)
![Agent](https://img.shields.io/badge/Agent-Gemini%203%20Pro%20(Antigravity)-blue)
![Protocol](https://img.shields.io/badge/Protocol-MCP%20(STDIO)-green)
![Tool](https://img.shields.io/badge/Tool-Oracle%20SQLcl%2025.4-orange)
![Security](https://img.shields.io/badge/Security-Oracle%20Wallet%20(SEPS)-blueviolet)
![OS](https://img.shields.io/badge/OS-Oracle%20Linux%209-brightgreen)

---

| Parameter | Value |
|---|---|
| 🤖 **Application** | Antigravity (Gemini) |
| 🗄️ **Databases** | CDB1, CDB2 (Oracle Database 23.26.1.0.0) |
| 🔧 **MCP Server Tool** | Oracle SQLcl 25.4 |
| 📄 **Configuration File** | `/home/oracle/.gemini/antigravity/mcp_config.json` |

---

## 🏗️ Connection Architecture

The MCP server functionality built natively into Oracle SQLcl was used, with direct mapping of a secure connection via the SEPS (Secure External Password Store) service.

### 🔐 1. Authentication
An Oracle Wallet credential store (`mkstore`) located at `/home/oracle/wallet` was used. This store hides and protects passwords for the `c##mcp_ai` user in both CDB1 and CDB2. Successfully binding credentials in the wallet enables the use of short-form login strings: `/@CDB1` and `/@CDB2`.

### ⚙️ 2. Execution Engine
The MCP engine is a SQLcl instance located at `/u01/app/oracle/product/26.0.0/dbhome_1/sqlcl/bin/sql`. A dedicated wrapper script `/home/oracle/mcp_sqlcl_wrapper.sh` is used to isolate the installation from user-level settings such as `login.sql` (removing options that generate formatting errors, e.g. `SET lines` parameters unknown to SQLcl). It is invoked with the `-mcp` flag, which enables Model Context Protocol mode — listening on standard input/output (STDIO) and establishing a connection to the target database.

---

## 📄 Final MCP Configuration File

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

## 🔍 Parameter and Argument Reference

| Parameter | Description |
|---|---|
| 🏷️ **`oracle-cdb1` / `oracle-cdb2`** | Server profile names exposed in the agent, used to direct AI commands to a specific database instance. |
| 📜 **`command`** | Path to the wrapper script `/home/oracle/mcp_sqlcl_wrapper.sh`, which performs a hard environment reset (e.g. ignoring `login.sql`, enforcing UTF-8). It then invokes the native SQLcl startup script. |
| 🚩 **`args` → `["-mcp"]`** | Indicates that SQLcl should not start in standard SQL command-line mode, but instead start natively as an MCP server integrating the LLM via the Model Context Protocol. |
| 🔑 **`args` → `["/@CDB1"]`** | Connects to the target database via alias without providing a username or password. All authentication credentials are retrieved by the native Oracle client (via the `WALLET_LOCATION` parameter in `sqlnet.ora`) from the securely stored wallet file on the physical server. |

---

## ✅ Tests

- [x] 🔎 Detection of installed components.
- [x] 🧪 Discovery and verification of `-mcp` flag support by the system-installed `sqlcl` client.
- [x] 🛡️ Verification of SEPS authorization via Oracle Wallet for alias `/@CDB1` — successfully retrieved database data (the command returned instance information and version `23.26.1`). All queries directed through this protocol configuration will work as long as the wallet is active and the `c##mcp_ai` user permissions remain valid.
