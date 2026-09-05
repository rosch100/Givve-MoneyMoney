# givve Card MoneyMoney Extension Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eigenes Repo `Givve-MoneyMoney` mit MoneyMoney-Extension für `card.givve.com`: E-Mail/Passwort, E-Mail-MFA, ein Prepaid-Konto (Saldo + Umsätze), Multi-Login-LocalStorage, Host-Allowlist.

**Architecture:** TDD zuerst für reine Hilfen (E-Mail-Normalisierung, Kontonummer, Host-Check, Response-Klassifikation, Saldo-/Umsatz-Parser gegen Fixtures). Danach WebBanking-Hooks und Session-Map. Login-/MFA-HTTP-Bodies werden erst nach Live-Capture (Task 6) verdrahtet — bis dahin failen Login-Netzwerkpfade explizit, Parser/Klassifikatoren laufen offline grün.

**Tech Stack:** LuaJIT (`luajit`), MoneyMoney WebBanking-Host-Globals, Python 3 für Conformance, GitHub (`gh`) für Remote.

**Spec:** `docs/superpowers/specs/2026-09-05-givve-card-extension-design.md`

## Global Constraints

- Service/BankCode: `givve Card`; URL `https://card.givve.com`; Version `0.91`.
- Credentials: `[1]` E-Mail, `[2]` Passwort; MFA = E-Mail-Code via Interactive-Challenge-Tabelle (`title`/`challenge`/`label`).
- Host-Allowlist: nur `card.givve.com` bis Live-Befund weitere Hosts erzwingt (dann CONSTANTS + Tests).
- Kontonummer: `givve.<email-lower-trim mit @→.>`; Anzeigename `givve Card (<email>)`; Typ `AccountTypeCreditCard`; Währung `EUR`.
- `accountKey`: volle E-Mail lowercased+trimmed (mit `@`).
- Multi-Login: `LocalStorage.connectionsByAccount[accountKey]`; keine Connection-Userdata persistieren; Cookies als serialisierbarer String.
- Keine Dummy-Umsätze/Salden; keine stillen Fallbacks; keine Secrets in Fixtures.
- Kein Cookie-Import, kein Business-Portal, keine PIN/Aktivierung in v1.
- Commits ohne Cursor-Co-Author-Trailer; Arbeitsverzeichnis Plugin-Repo außer Hub-Tasks.
- Tests: `python3 tests/test_conformance.py` und `luajit tests/test_givve.lua` aus Repo-Root.

## File map

| File | Role |
| --- | --- |
| `Givve.lua` | Extension: CONSTANTS, Hilfen, Hooks |
| `LICENSE` | MIT (wie Siblings) |
| `README.md` | Install, Auth, Tests, Hub-Link |
| `link_ext.sh` | Hardlink nach MoneyMoney Extensions |
| `tests/test_conformance.py` | BOM/WebBanking/SupportsBank/Init-Hooks |
| `tests/test_givve.lua` | Offline-Unit-Tests (dofile + Stubs) |
| `tests/fixtures/*.html` / `*.json` | Synthetisch, dann Live-Replace |
| `docs/superpowers/specs/2026-09-05-givve-card-extension-design.md` | Spec (Status am Ende → Implementiert) |
| Hub `README.md`, `docs/LUA-EXTENSIONS.md` | Index-Zeile (separates Repo) |

---

### Task 1: Repo-Scaffold (ohne Lua-Logik)

**Files:**
- Create: `LICENSE`, `README.md`, `link_ext.sh`
- Modify: none (Spec bleibt)
- Test: manuell Dateien vorhanden

**Interfaces:**
- Produces: installierbares Repo-Gerüst; noch keine `Givve.lua`

- [ ] **Step 1: LICENSE anlegen**

Datei `LICENSE` exakt wie Sibling MIT mit Copyright `(c) 2024-2026 rosch100` (Text aus `Bank-of-America-MoneyMoney/LICENSE` kopieren).

- [ ] **Step 2: `link_ext.sh` anlegen**

```sh
#!/bin/sh
set -e
EXT_DIR="$HOME/Library/Containers/com.moneymoney-app.retail/Data/Library/Application Support/MoneyMoney/Extensions"
SRC="$(cd "$(dirname "$0")" && pwd)/Givve.lua"
DST="$EXT_DIR/Givve.lua"
ls -li "$DST" "$SRC" 2>/dev/null || true
rm -f "$DST"
ln "$SRC" "$DST"
ls -li "$DST" "$SRC"
```

UTF-8 ohne BOM, LF, ausführbar: `chmod +x link_ext.sh`.

- [ ] **Step 3: README anlegen**

```markdown
# givve Card — MoneyMoney Extension
Plugin Homepage: https://github.com/rosch100/Givve-MoneyMoney
Bank/Portal: https://card.givve.com
Version: **0.91** Beta
Status: E-Mail/Passwort + E-Mail-MFA; Saldo + Umsätze (Karteninhaber)
Hub (gemeinsame Tools/Doku): https://github.com/rosch100/moneymoney-extensions

## Installation
Unsignierte Datei: [Givve.lua](https://raw.githubusercontent.com/rosch100/Givve-MoneyMoney/main/Givve.lua)
Datei nach `~/Library/Containers/com.moneymoney-app.retail/Data/Library/Application Support/MoneyMoney/Extensions` kopieren, oder im Klon `./link_ext.sh` ausführen.
Unsignierte Plugins: MoneyMoney-**Beta**, Signaturprüfung in den Erweiterungseinstellungen aus.

In MoneyMoney Bankzugang anlegen: Bank **givve Card**, Benutzername = E-Mail, Passwort = Portal-Passwort.
Bei MFA den Code aus der E-Mail in die Challenge eingeben.

## Multi-Login
Mehrere Zugänge: je einen Bankzugang mit eigener E-Mail. Kontonummer
`givve.<email-mit-punkt-statt-at>`, Name `givve Card (<email>)`.

## Tests
```sh
python3 tests/test_conformance.py
luajit tests/test_givve.lua
```
Aus dem Repo-Root ausführen.

## Lizenz
MIT — siehe [LICENSE](LICENSE).
```

- [ ] **Step 4: Commit**

```bash
cd /Users/roschmac/Entwicklung/MoneyMoney/Givve-MoneyMoney
git add LICENSE README.md link_ext.sh
git commit -m "$(cat <<'EOF'
Add givve Card repo scaffold (license, README, link script).

EOF
)"
```

---

### Task 2: E-Mail-/Kontonummer-Hilfen (TDD)

**Files:**
- Create: `Givve.lua` (nur Hilfen + WebBanking-Stub-Metadaten), `tests/test_givve.lua`
- Test: `tests/test_givve.lua`

**Interfaces:**
- Produces:
  - `normalizeEmail(raw) → string` (trim + lower; `""` wenn nil/leer)
  - `accountNumberForEmail(email) → string` (`givve.` + normalize, `@`→`.`)
  - `accountNameForEmail(email) → string` (`givve Card (` .. normalize .. `)`)
  - `normalizeAccountKey(raw) → string` (= `normalizeEmail`)

- [ ] **Step 1: Failing test schreiben**

`tests/test_givve.lua`:

```lua
function WebBanking(_) end
ProtocolWebBanking = "WebBanking"
AccountTypeCreditCard = 3
LoginFailed = "LoginFailed"

MM = {
  printStatus = function(msg) io.stderr:write("[STATUS] " .. msg .. "\n") end,
  urlencode = function(s)
    return (tostring(s):gsub("([^%w%-%.%_%~])", function(c)
      return string.format("%%%02X", string.byte(c))
    end))
  end
}

function Connection()
  return {
    request = function() end,
    get = function() end,
    getCookies = function() return "" end,
    setCookie = function() end
  }
end

dofile("Givve.lua")

local function assertEq(actual, expected, label)
  if actual == expected then
    print("OK    " .. label .. " = " .. tostring(actual))
  else
    print("FAIL  " .. label .. ": expected=" .. tostring(expected) .. ", actual=" .. tostring(actual))
    os.exit(1)
  end
end

assertEq(normalizeEmail("  User@Firma.DE "), "user@firma.de", "normalizeEmail.trim.lower")
assertEq(normalizeEmail(""), "", "normalizeEmail.empty")
assertEq(normalizeEmail(nil), "", "normalizeEmail.nil")
assertEq(accountNumberForEmail("user@firma.de"), "givve.user.firma.de", "accountNumber")
assertEq(accountNumberForEmail("  A@B.C "), "givve.a.b.c", "accountNumber.normalize")
assertEq(accountNameForEmail("user@firma.de"), "givve Card (user@firma.de)", "accountName")
assertEq(normalizeAccountKey("  User@Firma.DE "), "user@firma.de", "accountKey")
print("test_givve helpers OK")
```

- [ ] **Step 2: Test ausführen (erwarteter Fail)**

Run: `luajit tests/test_givve.lua`  
Expected: Fail (`Givve.lua` fehlt oder Funktionen undefined)

- [ ] **Step 3: Minimale `Givve.lua`**

```lua
--
-- Plugin Homepage: https://github.com/rosch100/Givve-MoneyMoney
-- givve Card — MoneyMoney Web Banking Extension
-- https://card.givve.com
-- Dokumentation: README.md (Hub: https://github.com/rosch100/moneymoney-extensions)
-- API: https://moneymoney.app/api/webbanking/
--

WebBanking{
  version     = 0.91,
  url         = "https://card.givve.com",
  services    = {"givve Card"},
  description = "givve Card — E-Mail/Passwort + E-Mail-MFA"
}

local CONSTANTS = {
  baseUrl = "https://card.givve.com",
  loginUrl = "https://card.givve.com/login",
  allowedHosts = { "card.givve.com" },
  serviceName = "givve Card",
  userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
}

local connection
local session = {}

function trim(s)
  if type(s) ~= "string" then
    return ""
  end
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

function normalizeEmail(raw)
  return trim(tostring(raw or "")):lower()
end

function normalizeAccountKey(raw)
  return normalizeEmail(raw)
end

function accountNumberForEmail(email)
  local e = normalizeEmail(email)
  if e == "" then
    return "givve.unknown"
  end
  return "givve." .. (e:gsub("@", "."))
end

function accountNameForEmail(email)
  local e = normalizeEmail(email)
  if e == "" then
    return "givve Card"
  end
  return "givve Card (" .. e .. ")"
end

function SupportsBank(protocol, bankCode)
  return protocol == ProtocolWebBanking and bankCode == CONSTANTS.serviceName
end
```

Hinweis: `accountNumberForEmail`/`accountNameForEmail` bei leerer E-Mail — Tests oben decken nur gültige E-Mails; leere Pfade für Hooks später mit explizitem Fehler, nicht still.

- [ ] **Step 4: Test grün**

Run: `luajit tests/test_givve.lua`  
Expected: `test_givve helpers OK` und alle `OK` Zeilen

- [ ] **Step 5: Commit**

```bash
git add Givve.lua tests/test_givve.lua
git commit -m "$(cat <<'EOF'
Add givve email and account number helpers with tests.

EOF
)"
```

---

### Task 3: Host-Allowlist + Response-Klassifikatoren (TDD)

**Files:**
- Modify: `Givve.lua`, `tests/test_givve.lua`
- Create: `tests/fixtures/login_failed.html`, `tests/fixtures/mfa_challenge.html`, `tests/fixtures/home_ok.html`

**Interfaces:**
- Produces:
  - `hostAllowed(urlOrHost) → boolean`
  - `assertAllowedUrl(url) → url` oder `error(...)`
  - `classifyLoginHtml(html) → "ok"|"mfa"|"login_failed"|"unknown"`
  - `emailMfaChallenge(message?) → { title, challenge, label }`

- [ ] **Step 1: Fixtures anlegen (synthetisch, keine Secrets)**

`tests/fixtures/login_failed.html`:

```html
<html><body><div class="error">Invalid email or password</div></body></html>
```

`tests/fixtures/mfa_challenge.html`:

```html
<html><body><h1>Verify your identity</h1><p>We sent a code to your email</p>
<form id="mfa"><input name="code" /></form></body></html>
```

`tests/fixtures/home_ok.html`:

```html
<html><body data-givve-home="1">
  <div class="balance" data-balance="123.45">123,45 €</div>
  <div class="card-last4">1234</div>
  <table class="transactions">
    <tr data-booking-id="tx1"><td class="date">2026-09-01</td><td class="name">Café</td><td class="amount">-12.50</td></tr>
    <tr data-booking-id="tx2"><td class="date">2026-09-02</td><td class="name">Aufladung</td><td class="amount">50.00</td></tr>
  </table>
</body></html>
```

- [ ] **Step 2: Failing assertions an `tests/test_givve.lua` anhängen**

```lua
local function readFixture(name)
  local f = assert(io.open("tests/fixtures/" .. name, "r"))
  local s = f:read("*a")
  f:close()
  return s
end

assertEq(hostAllowed("https://card.givve.com/login"), true, "host.card")
assertEq(hostAllowed("https://evil.example/login"), false, "host.evil")
assertEq(hostAllowed("card.givve.com"), true, "host.bare")

local okCall, err = pcall(function() assertAllowedUrl("https://evil.example/x") end)
assertEq(okCall, false, "assertAllowedUrl.rejects")

assertEq(classifyLoginHtml(readFixture("login_failed.html")), "login_failed", "classify.failed")
assertEq(classifyLoginHtml(readFixture("mfa_challenge.html")), "mfa", "classify.mfa")
assertEq(classifyLoginHtml(readFixture("home_ok.html")), "ok", "classify.ok")

local ch = emailMfaChallenge(nil)
assertEq(type(ch) == "table" and ch.label ~= nil, true, "mfaChallenge.table")
assertEq(ch.label, "E-Mail-Code", "mfaChallenge.label")
print("test_givve classify OK")
```

- [ ] **Step 3: Test failen lassen**

Run: `luajit tests/test_givve.lua`  
Expected: Fail auf fehlende Funktionen

- [ ] **Step 4: Implementierung in `Givve.lua`**

```lua
function hostAllowed(urlOrHost)
  if type(urlOrHost) ~= "string" or urlOrHost == "" then
    return false
  end
  local host = urlOrHost
  if host:match("^https?://") then
    host = host:match("^https?://([^/?#]+)") or ""
  end
  host = host:lower():gsub(":443$", ""):gsub(":80$", "")
  for _, allowed in ipairs(CONSTANTS.allowedHosts) do
    if host == allowed then
      return true
    end
  end
  return false
end

function assertAllowedUrl(url)
  if type(url) ~= "string" or url == "" then
    error("givve Card: URL fehlt")
  end
  if not url:match("^https://") then
    error("givve Card: nur https:// erlaubt")
  end
  if not hostAllowed(url) then
    error("givve Card: Host nicht erlaubt: " .. tostring(url))
  end
  return url
end

function classifyLoginHtml(html)
  if type(html) ~= "string" or html == "" then
    return "unknown"
  end
  local lower = html:lower()
  if lower:find("invalid email or password", 1, true)
      or lower:find("falsche.? (e%-?mail|passwort)", 1)
      or lower:find("login failed", 1, true) then
    return "login_failed"
  end
  if lower:find("data%-givve%-home", 1)
      or (lower:find("balance", 1, true) and lower:find("transactions", 1, true)) then
    return "ok"
  end
  if lower:find("we sent a code", 1, true)
      or lower:find("verify your identity", 1, true)
      or lower:find("code to your email", 1, true)
      or lower:find("bestätigungscode", 1, true) then
    return "mfa"
  end
  return "unknown"
end

function emailMfaChallenge(message)
  return {
    title = "givve Card Authentifizierung",
    challenge = message or "Bitte den Code aus der givve-E-Mail eingeben.",
    label = "E-Mail-Code"
  }
end
```

Marker in `classifyLoginHtml` nach Live-Capture erweitern — bestehende Tests müssen weiter grün bleiben.

- [ ] **Step 5: Test grün + Commit**

```bash
luajit tests/test_givve.lua
git add Givve.lua tests/test_givve.lua tests/fixtures/
git commit -m "$(cat <<'EOF'
Add givve host allowlist and login response classifiers.

EOF
)"
```

---

### Task 4: Saldo- und Umsatz-Parser (TDD gegen synthetische Fixtures)

**Files:**
- Modify: `Givve.lua`, `tests/test_givve.lua`
- Test: Fixture `home_ok.html` aus Task 3

**Interfaces:**
- Produces:
  - `parseBalanceFromHomeHtml(html) → number|nil`
  - `parseTransactionsFromHomeHtml(html, sinceTimestamp?) → { {bookingDate, name, amount, bookingKey?}, ... }`
  - Beträge: Ausgaben negativ; Datums-ISO `YYYY-MM-DD` → Unix-Mitternacht lokal via `os.time`

- [ ] **Step 1: Failing tests**

```lua
local bal = parseBalanceFromHomeHtml(readFixture("home_ok.html"))
assertEq(bal, 123.45, "balance")

local txs = parseTransactionsFromHomeHtml(readFixture("home_ok.html"), nil)
assertEq(#txs, 2, "tx.count")
assertEq(txs[1].name, "Café", "tx1.name")
assertEq(txs[1].amount, -12.50, "tx1.amount")
assertEq(txs[1].bookingKey, "tx1", "tx1.key")
assertEq(txs[2].amount, 50.00, "tx2.amount")

local empty = parseTransactionsFromHomeHtml("<html></html>", nil)
assertEq(#empty, 0, "tx.empty")
assertEq(parseBalanceFromHomeHtml("<html></html>"), nil, "balance.missing")
print("test_givve parse OK")
```

- [ ] **Step 2: Fail beobachten** — `luajit tests/test_givve.lua`

- [ ] **Step 3: Parser implementieren**

```lua
function parseGermanOrPlainAmount(text)
  if type(text) ~= "string" then
    return nil
  end
  local raw = trim(text)
  raw = raw:gsub("%s", ""):gsub("€", ""):gsub("&nbsp;", "")
  if raw:find(",", 1, true) and raw:find("%.", 1, true) then
    raw = raw:gsub("%.", ""):gsub(",", ".")
  elseif raw:find(",", 1, true) then
    raw = raw:gsub(",", ".")
  end
  return tonumber(raw)
end

function parseIsoDateToTimestamp(iso)
  local y, m, d = iso:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
  if not y then
    return nil
  end
  return os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12 })
end

function parseBalanceFromHomeHtml(html)
  if type(html) ~= "string" then
    return nil
  end
  local attr = html:match('data%-balance="([%d%.]+)"')
  if attr then
    return tonumber(attr)
  end
  local text = html:match('class="balance"[^>]*>([^<]+)<')
  return parseGermanOrPlainAmount(text)
end

function parseTransactionsFromHomeHtml(html, sinceTimestamp)
  local out = {}
  if type(html) ~= "string" then
    return out
  end
  for id, inner in html:gmatch('<tr[^>]*data%-booking%-id="([^"]+)"([^>]*>.-)</tr>') do
    local dateIso = inner:match('class="date">([^<]+)<')
    local name = inner:match('class="name">([^<]+)<')
    local amountRaw = inner:match('class="amount">([^<]+)<')
    local amount = parseGermanOrPlainAmount(amountRaw)
    local ts = dateIso and parseIsoDateToTimestamp(trim(dateIso))
    if name and amount and ts then
      if sinceTimestamp == nil or ts >= sinceTimestamp then
        out[#out + 1] = {
          bookingDate = ts,
          name = trim(name),
          amount = amount,
          bookingKey = id,
          currency = "EUR"
        }
      end
    end
  end
  return out
end
```

`gmatch`-Pattern so wählen, dass beide Zeilen aus `home_ok.html` matchen; mit dem Test verifizieren. Keine Dummy-Zeile bei Parse-Fail.

- [ ] **Step 4: Grün + Commit**

```bash
luajit tests/test_givve.lua
git add Givve.lua tests/test_givve.lua
git commit -m "$(cat <<'EOF'
Add givve balance and transaction HTML parsers.

EOF
)"
```

---

### Task 5: Session-Map, Hooks-Stub, Conformance

**Files:**
- Modify: `Givve.lua`, `tests/test_givve.lua`
- Create: `tests/test_conformance.py` (Sibling-Kopie + Checks auf `ListAccounts`/`RefreshAccount`/`EndSession` und Service-String)

**Interfaces:**
- Produces:
  - `getConnectionEntry(storage, accountKey) → entry table`
  - `persistSessionCookies(storage, accountKey, cookieHeader)`
  - `InitializeSession2`, `ListAccounts`, `RefreshAccount`, `EndSession`
  - Bis Task 6/7: `InitializeSession2` ohne gültige Live-Session → klarer Fehlerstring, außer offline-Tests rufen Parser direkt

- [ ] **Step 1: Conformance-Datei**

`tests/test_conformance.py` wie Shareview, plus:

```python
        assert_true(file_contains(lua_path, r"\bfunction\s+ListAccounts\s*\("), f"{lua_path}: missing ListAccounts")
        assert_true(file_contains(lua_path, r"\bfunction\s+RefreshAccount\s*\("), f"{lua_path}: missing RefreshAccount")
        assert_true(file_contains(lua_path, r"\bfunction\s+EndSession\s*\("), f"{lua_path}: missing EndSession")
        assert_true(file_contains(lua_path, r'services\s*=\s*\{\s*"givve Card"\s*\}'), f"{lua_path}: service name")
        assert_true(file_contains(lua_path, r"allowedHosts"), f"{lua_path}: host allowlist")
```

- [ ] **Step 2: Session-Helfer + Hooks in `Givve.lua`**

```lua
function stripNonSerializableConnections(storage)
  if type(storage) ~= "table" then
    return
  end
  storage.connection = nil
  if type(storage.connectionsByAccount) == "table" then
    for _, entry in pairs(storage.connectionsByAccount) do
      if type(entry) == "table" then
        entry.connection = nil
      end
    end
  end
end

function getConnectionEntry(storage, accountKey)
  if not storage then
    return nil
  end
  storage.connectionsByAccount = storage.connectionsByAccount or {}
  local entry = storage.connectionsByAccount[accountKey]
  if not entry then
    entry = {}
    storage.connectionsByAccount[accountKey] = entry
  end
  return entry
end

function persistSessionCookies(storage, accountKey, cookieHeader)
  local entry = getConnectionEntry(storage, accountKey)
  if entry and type(cookieHeader) == "string" then
    entry.sessionCookies = cookieHeader
  end
  if storage and accountKey ~= "" then
    storage.connectionAccountKey = accountKey
    if type(cookieHeader) == "string" then
      storage.sessionCookies = cookieHeader
    end
  end
end

function InitializeSession2(protocol, bankCode, step, credentials, interactive)
  local email = normalizeEmail(credentials and credentials[1])
  if email == "" then
    return "Bitte die givve-E-Mail-Adresse eingeben."
  end
  session.accountKey = email
  local storage = rawget(_G, "LocalStorage")
  if storage then
    stripNonSerializableConnections(storage)
  end
  connection = Connection()
  connection.language = "de-DE"
  connection.useragent = CONSTANTS.userAgent
  if storage then
    getConnectionEntry(storage, email)
    storage.connectionAccountKey = email
  end
  -- Live-Login folgt in Task 6; Stub:
  if step == 1 then
    return "givve Card: Login noch nicht verdrahtet — Live-Capture (Task 6) ausführen."
  end
  return "Anmeldesitzung abgelaufen. Bitte erneut anmelden."
end

function ListAccounts(knownAccounts)
  return "givve Card: Session fehlt — bitte zuerst anmelden (nach Live-Login)."
end

function RefreshAccount(account, since)
  return "givve Card: Session fehlt — bitte zuerst anmelden (nach Live-Login)."
end

function EndSession()
  local storage = rawget(_G, "LocalStorage")
  if storage then
    stripNonSerializableConnections(storage)
  end
  connection = nil
end
```

- [ ] **Step 3: Tests**

```bash
python3 tests/test_conformance.py
# Expected: CONFORMANCE OK
luajit tests/test_givve.lua
# Expected: bisherige OK-Ausgaben
```

Optional in `test_givve.lua`:

```lua
assertEq(SupportsBank(ProtocolWebBanking, "givve Card"), true, "SupportsBank.ok")
assertEq(SupportsBank(ProtocolWebBanking, "Other"), false, "SupportsBank.no")
```

- [ ] **Step 4: Commit**

```bash
git add Givve.lua tests/test_conformance.py tests/test_givve.lua
git commit -m "$(cat <<'EOF'
Add givve session helpers, stub hooks, and conformance tests.

EOF
)"
```

---

### Task 6: Live-Capture Gate (manuell) + Login/MFA verdrahten

**Files:**
- Modify: `Givve.lua`, Fixtures unter `tests/fixtures/` (echte HTML/JSON-Snippets, redacted)
- Test: Classifier-/Parser-Tests ggf. an echte Marker anpassen

**Interfaces:**
- Consumes: `classifyLoginHtml`, `emailMfaChallenge`, `assertAllowedUrl`, Session-Map
- Produces: `loginWithPassword(email, password, interactive)`, `submitEmailMfaCode(code)`, echte Request-Pfade

- [ ] **Step 1: Capture-Protokoll ausführen**

1. Safari/Chrome DevTools → Network, gegen `https://card.givve.com/login` einloggen.
2. Speichern (ohne Cookies/Tokens ins Repo): Login-POST URL, Form-Feldnamen, CSRF-Header, MFA-Seite HTML, erfolgreiche Home-HTML oder XHR-JSON für Saldo/Umsätze.
3. Redacted Fixtures ersetzen/ergänzen (`login_failed`, `mfa_challenge`, `home_ok` oder `home_ok.json`).
4. Wenn weitere Hosts nötig: `CONSTANTS.allowedHosts` erweitern + `hostAllowed`-Tests.

- [ ] **Step 2: `loginWithPassword` / MFA in `InitializeSession2` verdrahten**

Muster (Feldnamen aus Capture einsetzen — Platzhalter unten ersetzen, nicht raten):

```lua
function loginWithPassword(email, password, interactive)
  assertAllowedUrl(CONSTANTS.loginUrl)
  local page = connection:get(CONSTANTS.loginUrl)
  -- CSRF / hidden fields aus page extrahieren (laut Capture)
  local body = MM.urlencode({
    -- CAPTURE: emailField = email,
    -- CAPTURE: passwordField = password,
    -- CAPTURE: csrf = ...
  })
  local postUrl = CONSTANTS.loginUrl -- CAPTURE: echte Action-URL
  assertAllowedUrl(postUrl)
  local html = connection:request("POST", postUrl, body, "application/x-www-form-urlencoded", {
    ["Referer"] = CONSTANTS.loginUrl
  })
  local kind = classifyLoginHtml(html or "")
  if kind == "login_failed" then
    return LoginFailed
  end
  if kind == "mfa" then
    if interactive == false then
      return "givve Card: E-Mail-MFA erforderlich — interaktive Anmeldung nötig."
    end
    session.awaitingMfa = true
    session.pendingEmail = email
    return emailMfaChallenge(nil)
  end
  if kind == "ok" then
    session.homeHtml = html
    local storage = rawget(_G, "LocalStorage")
    if storage and connection.getCookies then
      persistSessionCookies(storage, session.accountKey, connection:getCookies())
    end
    return nil
  end
  return "givve Card: Unerwartete Login-Antwort — Portal-HTML prüfen."
end

function submitEmailMfaCode(code)
  session.awaitingMfa = false
  if type(code) ~= "string" or trim(code) == "" then
    return "Bitte den E-Mail-Code eingeben."
  end
  -- CAPTURE: MFA POST URL + Felder
  local postUrl = CONSTANTS.baseUrl .. "/CAPTURE_MFA_PATH"
  assertAllowedUrl(postUrl)
  local body = MM.urlencode({ code = trim(code) }) -- CAPTURE field names
  local html = connection:request("POST", postUrl, body, "application/x-www-form-urlencoded", {})
  local kind = classifyLoginHtml(html or "")
  if kind == "mfa" then
    session.awaitingMfa = true
    return emailMfaChallenge("Code ungültig oder abgelaufen. Bitte neuen Code prüfen.")
  end
  if kind == "ok" then
    session.homeHtml = html
    local storage = rawget(_G, "LocalStorage")
    if storage and connection.getCookies then
      persistSessionCookies(storage, session.accountKey, connection:getCookies())
    end
    return nil
  end
  return "givve Card: MFA-Antwort unerwartet."
end

function InitializeSession2(protocol, bankCode, step, credentials, interactive)
  local email = normalizeEmail(credentials and credentials[1])
  local password = credentials and credentials[2] or ""
  if email == "" then
    return "Bitte die givve-E-Mail-Adresse eingeben."
  end
  session.accountKey = email
  local storage = rawget(_G, "LocalStorage")
  if storage then
    stripNonSerializableConnections(storage)
    getConnectionEntry(storage, email)
    storage.connectionAccountKey = email
  end
  if not connection then
    connection = Connection()
  end
  connection.language = "de-DE"
  connection.useragent = CONSTANTS.userAgent

  if step == 1 then
    if password == "" then
      return "Bitte das givve-Passwort eingeben."
    end
    return loginWithPassword(email, password, interactive)
  end
  if session.awaitingMfa then
    return submitEmailMfaCode(credentials[1])
  end
  return "Anmeldesitzung abgelaufen. Bitte erneut anmelden."
end
```

Wichtig: MoneyMoney liefert MFA-Antwort typischerweise als `credentials[1]` im Folgeschritt — wie Shareview `submitMfaCode`. An Engine-Verhalten anpassen falls Capture anderes zeigt.

- [ ] **Step 3: Classifier an echte Marker anpassen; Tests grün**

```bash
luajit tests/test_givve.lua
python3 tests/test_conformance.py
```

- [ ] **Step 4: Commit**

```bash
git add Givve.lua tests/fixtures/ tests/test_givve.lua
git commit -m "$(cat <<'EOF'
Wire givve login and email MFA from live portal capture.

EOF
)"
```

---

### Task 7: `ListAccounts` + `RefreshAccount` verdrahten

**Files:**
- Modify: `Givve.lua`, ggf. Parser wenn Live-JSON statt HTML
- Test: `tests/test_givve.lua` (Parser); manuell MoneyMoney nach `link_ext.sh`

**Interfaces:**
- Consumes: `parseBalanceFromHomeHtml`, `parseTransactionsFromHomeHtml`, `accountNumberForEmail`, `accountNameForEmail`
- Produces: ein Account; Transaktionsliste ohne Dummies

- [ ] **Step 1: Implementierung**

```lua
function fetchHomeHtml()
  local url = CONSTANTS.baseUrl .. "/" -- CAPTURE: echte Home/Dashboard-URL
  assertAllowedUrl(url)
  local html = connection:get(url)
  if type(html) ~= "string" or html == "" then
    return nil, "givve Card: Startseite nicht ladbar."
  end
  return html
end

function ListAccounts(knownAccounts)
  local html = session.homeHtml
  if not html then
    local err
    html, err = fetchHomeHtml()
    if not html then
      return err
    end
  end
  local balance = parseBalanceFromHomeHtml(html)
  if balance == nil then
    return "givve Card: Saldo konnte nicht gelesen werden."
  end
  local email = session.accountKey or ""
  return {
    {
      name = accountNameForEmail(email),
      accountNumber = accountNumberForEmail(email),
      currency = "EUR",
      balance = balance,
      type = AccountTypeCreditCard
    }
  }
end

function RefreshAccount(account, since)
  local html, err = fetchHomeHtml()
  if not html then
    return err
  end
  local balance = parseBalanceFromHomeHtml(html)
  if balance == nil then
    return "givve Card: Saldo konnte nicht gelesen werden."
  end
  local txs = parseTransactionsFromHomeHtml(html, since)
  return {
    balance = balance,
    transactions = txs
  }
end
```

Wenn Live-JSON: Parser `parseBalanceFromJson` / `parseTransactionsFromJson` analog Task 4 mit Fixture-JSON und denselben Rückgabeformen; HTML-Parser behalten falls parallel genutzt.

- [ ] **Step 2: Offline-Tests weiter grün; Stub-Fehlerstrings aus Task 5 entfernt**

```bash
luajit tests/test_givve.lua
python3 tests/test_conformance.py
```

- [ ] **Step 3: Commit**

```bash
git add Givve.lua tests/
git commit -m "$(cat <<'EOF'
Implement givve ListAccounts and RefreshAccount from portal data.

EOF
)"
```

---

### Task 8: GitHub-Remote anlegen und pushen

**Files:**
- Remote only

**Interfaces:**
- Produces: `https://github.com/rosch100/Givve-MoneyMoney`

- [ ] **Step 1: Repo erstellen und pushen**

```bash
cd /Users/roschmac/Entwicklung/MoneyMoney/Givve-MoneyMoney
gh auth status
gh repo create Givve-MoneyMoney --public --source=. --remote=origin --push --description "MoneyMoney extension for givve Card (card.givve.com)"
git status -sb
git remote -v
```

Expected: Remote `origin` → `rosch100/Givve-MoneyMoney`, Branch `main` gepusht.

Falls Name belegt: einmal `Givve-Card-MoneyMoney` versuchen, sonst Nutzer fragen.

---

### Task 9: Hub-Index aktualisieren

**Files:**
- Modify (Hub-Repo `/Users/roschmac/Entwicklung/MoneyMoney`): `README.md`, `docs/LUA-EXTENSIONS.md`
- Working tree: Hub, nicht Nested-Repo

**Interfaces:**
- Produces: Übersichtseintrag givve Card 0.91 Beta

- [ ] **Step 1: Hub-README-Tabelle**

Zeile ergänzen analog Siblings:

`| [givve Card](https://github.com/rosch100/Givve-MoneyMoney) | [Givve-MoneyMoney](https://github.com/rosch100/Givve-MoneyMoney) | **0.91** Beta | E-Mail/Passwort + E-Mail-MFA; Saldo + Umsätze (card.givve.com) |`

- [ ] **Step 2: `docs/LUA-EXTENSIONS.md` Abschnitt**

```markdown
## givve Card — 0.91 Beta

**Repo:** [Givve-MoneyMoney](https://github.com/rosch100/Givve-MoneyMoney)

Service-Name: `givve Card`. Portal: `card.givve.com`.
Login E-Mail/Passwort + E-Mail-MFA (Interactive). Host-Allowlist: `card.givve.com`.
Kontonummer `givve.<email-mit-punkt-statt-at>`; Multi-Login über `connectionsByAccount`.
```

- [ ] **Step 3: Commit im Hub** (nur wenn Nutzer Commit auf Hub-Branch erlaubt / eigener Branch)

```bash
cd /Users/roschmac/Entwicklung/MoneyMoney
git checkout -b docs/givve-extension-index   # falls nicht schon auf passendem Branch
git add README.md docs/LUA-EXTENSIONS.md
git commit -m "$(cat <<'EOF'
Document givve Card extension in hub index.

EOF
)"
```

Nicht auf fremde Feature-Branches mischen, wenn der aktuelle Hub-Branch unbezogen ist.

---

### Task 10: Spec-Status + Smoke in MoneyMoney

**Files:**
- Modify: `docs/superpowers/specs/2026-09-05-givve-card-extension-design.md` Status → Implementiert (wenn Login+Sync live grün)
- Test: `./link_ext.sh` + MoneyMoney manuell

- [ ] **Step 1: `./link_ext.sh`**

- [ ] **Step 2: MoneyMoney** — Bank `givve Card` anlegen, Login, MFA, Konten/Umsätze prüfen

- [ ] **Step 3: Spec-Status setzen** wenn Smoke OK:

`Status: **Implementiert** (2026-09-05)` (Datum anpassen)

- [ ] **Step 4: Commit im Plugin-Repo**

```bash
cd /Users/roschmac/Entwicklung/MoneyMoney/Givve-MoneyMoney
git add docs/superpowers/specs/2026-09-05-givve-card-extension-design.md
git commit -m "$(cat <<'EOF'
Mark givve Card extension design as implemented.

EOF
)"
git push
```

---

## Spec coverage (self-review)

| Spec-Anforderung | Task |
| --- | --- |
| Eigenes Repo + GitHub | 1, 8 |
| Service `givve Card`, 0.91, card.givve.com | 2, 5 |
| E-Mail/Passwort + E-Mail-MFA Interactive | 3, 6 |
| Host-Allowlist | 3, 6 |
| Kontonummer volle E-Mail / accountKey mit `@` | 2 |
| Multi-Login LocalStorage Map | 5, 6 |
| ListAccounts Saldo / Refresh Umsätze | 4, 7 |
| Keine Dummies / Credential rejection | 3, 6, 7 |
| Tests Conformance + Lua | 2–5 |
| Hub README + LUA-EXTENSIONS | 9 |
| Live Capture nicht raten | 6 (Gate) |
| Out-of-scope v1 | nicht eingeplant |

## Placeholder scan

Task 6/7 enthalten bewusst `CAPTURE_*`-Stellen — die dürfen erst nach dem Capture-Protokoll durch echte Werte ersetzt werden; Offline-Tasks 1–5 sind vollständig ohne Capture lauffähig.
