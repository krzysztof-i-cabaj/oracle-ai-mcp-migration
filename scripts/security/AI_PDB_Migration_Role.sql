-- =============================================================================
-- Skrypt: AI_PDB_Migration_Role.sql
-- Wykonaj w: CDB1 oraz CDB2 (aby agent miał władzę w obu instancjach)
-- =============================================================================

-- 1. Tworzymy wspólnego użytkownika (Musi mieć prefiks C##)
CREATE USER c##mcp_ai IDENTIFIED BY SilneHasloDlaAI_2026# CONTAINER=ALL;

-- 2. Nadajemy potężne uprawnienia do zarządzania PDB (bez roli SYSDBA!)
GRANT CREATE SESSION, CREATE DATABASE LINK TO c##mcp_ai CONTAINER=ALL;
GRANT CREATE PLUGGABLE DATABASE TO c##mcp_ai CONTAINER=ALL;
-- GRANT CREATE PLUGGABLE DATABASE, ALTER PLUGGABLE DATABASE, DROP PLUGGABLE DATABASE TO c##mcp_ai CONTAINER=ALL;
GRANT CREATE ANY DIRECTORY, DROP ANY DIRECTORY TO c##mcp_ai CONTAINER=ALL;

-- 3. Nadajemy role globalnego administratora
GRANT DBA, CDB_DBA TO c##mcp_ai CONTAINER=ALL;
GRANT SELECT ANY DICTIONARY TO c##mcp_ai CONTAINER=ALL;

-- Weryfikacja
PROMPT Konto c##mcp_ai gotowe do automatyzacji PDB!
