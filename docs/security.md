# Security Notes

![Oracle Version](https://img.shields.io/badge/Oracle-26ai-red) ![SQLcl](https://img.shields.io/badge/SQLcl-25.2%2B-blue) ![Protocol](https://img.shields.io/badge/Protocol-MCP-green) ![Security](https://img.shields.io/badge/Security-Wallet-orange)

This PoC is designed to keep credentials out of the AI prompt by relying on
Oracle Wallet or JCEKS and local SQLcl execution.

Note: In the final version, SQLcl is used as the credential store when Wallet
integration is not available in the VS Code/GitHub Copilot MCP client.

## 🛡 Recommendations

- Replace all hardcoded passwords before use.
- Prefer external authentication (wallet) when supported; otherwise use SQLcl
	credential store and protect local files and OS access.
- Use least privilege for the AI agent. Review sql/AI_PDB_Migration_Role.sql.
- Add human approval for destructive operations in production.
- Enable auditing for PDB unplug/plug actions if required.
