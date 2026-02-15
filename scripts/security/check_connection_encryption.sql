-- =============================================================================
-- Script name: check_connection_encryption.sql
-- Author: KCB Kris
-- Description: 
-- [PL] Szczegółowa weryfikacja parametrów sieciowych, kryptograficznych i 
--      uwierzytelniających bieżącej sesji zdalnej.
-- [EN] Detailed verification of network, cryptographic, and authentication 
--      parameters of the current remote session.
-- Oracle version: 23ai/26ai
-- =============================================================================
-- Script purpose:
-- [PL] Zapytanie do V$SESSION_CONNECT_INFO ujawnia mechanizmy działające w tle 
--      połączenia Oracle Net, w tym potwierdzenie użycia zewnętrznego portfela 
--      oraz algorytmów szyfrowania (Native Network Encryption).
-- [EN] Querying V$SESSION_CONNECT_INFO reveals the background mechanisms of the 
--      Oracle Net connection, including confirmation of external wallet usage 
--      and encryption algorithms (Native Network Encryption).
-- Parameters: None
-- =============================================================================

SET LINESIZE 200
SET PAGESIZE 100
COL sid FORMAT 99999
COL authentication_type FORMAT A20
COL network_service_banner FORMAT A80
COL osuser FORMAT A15

SELECT 
    sys_context('USERENV', 'SID') AS sid,
    sys_context('USERENV', 'OS_USER') AS osuser,
    sys_context('USERENV', 'AUTHENTICATION_METHOD') AS authentication_type,
    network_service_banner
FROM 
    v$session_connect_info
WHERE 
    sid = sys_context('USERENV', 'SID')
    AND (network_service_banner LIKE '%Authentication%' 
         OR network_service_banner LIKE '%Encryption%');

-- =============================================================================
-- Usage example:
-- @check_connection_encryption.sql
-- =============================================================================
-- Results interpretation:
-- [PL] 
-- 1. AUTHENTICATION_TYPE: Powinno wskazywać 'PASSWORD' w kontekście pliku haseł 
--    lub 'SECURE ROLE'/'EXTERNAL' zależnie od topologii portfela.
-- 2. NETWORK_SERVICE_BANNER: Szukaj wpisów o użyciu algorytmów np. AES256. 
--    W Oracle 23ai/26ai szyfrowanie sieciowe (Native Network Encryption) jest 
--    zazwyczaj włączone domyślnie dla połączeń zdalnych.
-- [EN]
-- 1. AUTHENTICATION_TYPE: Should indicate 'PASSWORD' in the context of a password 
--    file or 'SECURE ROLE'/'EXTERNAL' depending on the wallet topology.
-- 2. NETWORK_SERVICE_BANNER: Look for entries indicating the use of algorithms 
--    e.g., AES256. In Oracle 23ai/26ai, Native Network Encryption is generally 
--    enabled by default for remote connections.
-- =============================================================================
