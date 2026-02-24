# 📋 Podsumowanie Wykonanych Prac: Klonowanie i Maskowanie HR_PDB

![Oracle Version](https://img.shields.io/badge/Oracle-26ai%2023.26.1.0.0-red)
![Source](https://img.shields.io/badge/Źródło-CDB2%20→%20CDB1-blue)
![PDB](https://img.shields.io/badge/PDB-HR__PDB-orange)
![Security](https://img.shields.io/badge/GDPR-Data%20Masking%20PII-brightgreen)
![Status](https://img.shields.io/badge/Status-✓%20Completed-success)

---

Poniższy dokument stanowi podsumowanie wszystkich kroków wykonanych w celu sklonowania bazy `HR_PDB` z `CDB2` do `CDB1`, utworzenia serwisu bazodanowego oraz zmaskowania danych wrażliwych. Wyszczególniono w nim również napotkane problemy i sposoby ich rozwiązania.

---

## 🔎 1. Weryfikacja i Przygotowanie Środowiska

- **🎯 Działanie**: Próba diagnozy bazy na instancji CDB1.
- **⚠️ Problem 1**: Brak dostępu lub nieodpowiednie uprawnienia podczas korzystania ze zdefiniowanych połączeń MCP, co uniemożliwiało wykonanie niektórych poleceń (np. `show pdbs` kończyło się błędem braku uprawnień, a `sqlplus` nie był dostępny globalnie).
- **✅ Rozwiązanie**: Uruchomienie precyzyjnego polecenia na OS z pełną ścieżką do binariów Oracle wraz z połączeniem z uprawnieniami administratora:
  ```
  /u01/app/oracle/product/26.0.0/dbhome_1/bin/sqlplus / as sysdba
  ```

---

## 🔁 2. Klonowanie Bazy HR_PDB z CDB2 do CDB1

- **🎯 Działanie**: Próba utworzenia klonalnej bazy PDB w CDB1 z wykorzystaniem autoryzowanego powiązania `CLONE_LINK`.
- **⚠️ Problem 2**: Podczas polecenia `CREATE PLUGGABLE DATABASE` napotkano błąd **ORA-65012: Pluggable database HR_PDB already exists**, wskazujący na istnienie starej wersji tej bazy z poprzednich wdrożeń.
- **✅ Rozwiązanie**: Zidentyfikowano stan powielonej bazy, a następnie poprawnie ją zamknięto (`CLOSE IMMEDIATE`) i usunięto w całości łącznie z plikami danych:
  ```sql
  DROP PLUGGABLE DATABASE HR_PDB INCLUDING DATAFILES;
  ```
- **🎯 Działanie**: Po oczyszczeniu środowiska wykonano w pełni poprawne sklonowanie bazy z zachowaniem ciągłości konfiguracji:
  ```sql
  CREATE PLUGGABLE DATABASE HR_PDB FROM HR_PDB@CLONE_LINK;
  ```

---

## 🔄 3. Konfiguracja Auto-Startu PDB po Restarcie Instancji

- **🎯 Działanie**: Bazę sklonowaną wprowadzono w stan `OPEN`, gotową na przyjmowanie zapytań.
- **💾 Działanie**: Oznaczono bazę wskaźnikiem stanu, co wymusi w Oracle powrót do pożądanego trybu otwarcia po każdym restarcie głównej instancji (CDB1):
  ```sql
  ALTER PLUGGABLE DATABASE HR_PDB SAVE STATE;
  ```

---

## 🛠️ 4. Utworzenie Serwisu Bazy `hr_pdb_cdb1`

- **🎯 Działanie**: Przełączono sesję do nowo powstałej bazy `HR_PDB` i utworzono wyspecjalizowany serwis nazwany `hr_pdb_cdb1`, wykorzystując do tego pakiet deweloperski `DBMS_SERVICE`.
- **⚡ Działanie**: Skompilowano i powołano do życia wyzwalacz sprzętowy (`TRIGGER hr_pdb_service_trg`), który w sposób ciągły monitoruje operację `AFTER STARTUP ON DATABASE` — dzięki jego ingerencji zdefiniowany serwis nieustannie aktywuje się samoczynnie podczas ładowania instancji dla określonego kontenera.

---

## 🛡️ 5. Identyfikacja i Maskowanie Danych Wrażliwych (PII) w Tabeli EMPLOYEES

- **🎯 Działanie**: Opracowano listę pól tabeli `HR.EMPLOYEES` zaliczanych do danych zastrzeżonych.

**🔒 Maskowanie — Etap 1:** W trybie wsadowym nadpisano dane, podstawiając wartości generowane operacjami z użyciem pakietu `DBMS_RANDOM`. Poprawnie zmieniono i zatwierdzono zmiany na **107 rekordach**:

| Kolumna | Metoda Maskowania |
|---|---|
| 📞 `PHONE_NUMBER` | Ciąg `555-` + losowe 7 cyfr |
| 📧 `EMAIL` | 10-znakowy alfanumeryk + `@example.com` |
| 💰 `SALARY` | Zastąpienie nowymi progami wejściowymi |
| 📊 `COMMISSION_PCT` | Zamaskowane jako `NULL` |

- **⚠️ Problem 3**: Po zatwierdzeniu zmian, ujawniono, że zapytania `SELECT` na kolumnach `FIRST_NAME` oraz `LAST_NAME` zwracają niezamaskowane, prawdziwe nazwiska pracowników. Pierwotnie potraktowano te atrybuty w planie jako nadpis nadmiarowy, pozostawiając je zakomentowane.

- **✅ Rozwiązanie**: Podjęto dodatkową akcję wymuszającą nadpisanie w czasie rzeczywistym tych dwóch kolumn:
  ```sql
  UPDATE HR.EMPLOYEES
  SET FIRST_NAME = INITCAP(DBMS_RANDOM.STRING('A', 6)),
      LAST_NAME  = INITCAP(DBMS_RANDOM.STRING('A', 8));
  ```
  Reewaluacja odczytu poprawnie zweryfikowała ich wykreślenie do formatu nieczytelnego (np. `"Phsmeg Ahgdcss"`). Łącznie zmaskowano **107 instancji** — zero danych PII w środowisku testowym. ✅
