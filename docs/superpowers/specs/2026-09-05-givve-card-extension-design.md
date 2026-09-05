# givve Card — MoneyMoney Extension Design

Datum: 2026-09-05

Status: **Implementiert** (2026-09-05) — Offline-Tests grün; Live-Smoke in MoneyMoney empfohlen

## Ziel

Eigenes Repository und MoneyMoney-Web-Banking-Extension für das
**givve Card Karteninhaber-Portal** (`https://card.givve.com`): Login mit
E-Mail/Passwort, E-Mail-OTP, Saldo und Umsätze in MoneyMoney über die
JSON-API auf `https://www.givve.com`.

## Kontext

- Hub: [moneymoney-extensions](https://github.com/rosch100/moneymoney-extensions)
- Sibling-Muster: `*-MoneyMoney` als Nested-Git-Repos unter dem Hub,
  Remote unter `rosch100` auf GitHub
- Portal (SPA): `https://card.givve.com` (Flutter Web, z. B. Version 8.1.1)
- API: `https://www.givve.com/api/…`
- Kein Business-/Admin-Portal in v1

## Entscheidungen (bestätigt)

| Thema | Entscheidung |
| --- | --- |
| Lieferumfang | Scaffold + Design/Implementierung in derselben Session-Kette |
| Auth | E-Mail/Passwort direkt im Plugin (kein Cookie-Import in v1) |
| Scope | Karteninhaber: eine Prepaid-/Benefit-Karte, Saldo + Umsätze |
| MFA | E-Mail-OTP via MoneyMoney-Interactive-Challenge (`/login` → `/login/otp`) |
| Ansatz | Sibling-Scaffold + **JSON-API first** (Live-HAR 2026-09-05) |
| Kontoart | `AccountTypeCreditCard` (MoneyMoney hat keinen Prepaid-Typ) |
| Service-Name | `Givve Card` (Title Case; Dateiname `Givve Card.lua`) |
| Version | `1.00` |
| Multi-Voucher | Ein MoneyMoney-Konto pro Voucher-ID |

## Nicht-Ziele (v1)

- givve Business-/Admin-Portal
- Kartenaktivierung, PIN-Anzeige, Sperren/Entsperren
- Cookie-Import (`COOKIE:…`)
- App-Push-MFA / TOTP (nur E-Mail-OTP)
- Erstregistrierung mit Token aus dem Kartenanschreiben
- Gemeinsames Lua-Modul im Hub

## Repository

| Feld | Wert |
| --- | --- |
| Lokaler Pfad | `MoneyMoney/Givve-MoneyMoney/` |
| GitHub | `https://github.com/rosch100/Givve-MoneyMoney` |
| Lizenz | MIT |
| Startversion | `0.91` (Beta), später `1.0x` wenn Login+Sync stabil |

### Dateien

```text
Givve-MoneyMoney/
  Givve.lua
  README.md
  LICENSE
  link_ext.sh
  tests/
    test_conformance.py
    test_givve.lua
    fixtures/          # JSON-Snippets, keine Credentials
  docs/superpowers/
```

Hub-Index: Zeile in Hub-`README.md` und Abschnitt in `docs/LUA-EXTENSIONS.md`
(Branch `docs/givve-extension-index`); `.gitignore` listet `/Givve-MoneyMoney/`.

## MoneyMoney-Vertragsfläche

- `WebBanking`: `services = {"Givve Card"}`, `url = "https://card.givve.com"`,
  `version = 1.00`, Beschreibung ASCII (ohne Em-Dash), Dateiname `Givve Card.lua`
  (Title Case wie Sibling-Konvention; Sichtbarkeit in der Bankauswahl)
- `SupportsBank`: `ProtocolWebBanking` und BankCode/Service `Givve Card`
- Hooks: `InitializeSession2`, `ListAccounts`, `RefreshAccount`, `EndSession`
- Credentials: `[1]` = E-Mail, `[2]` = Passwort; OTP-Folgeschritt: Code in
  `credentials[1]`
- Host-Allowlist: `card.givve.com` (SPA Origin/Referer) und `www.givve.com`
  (API). Weitere Hosts nur nach neuem Live-Befund + Tests.

### Kontomodell

- **Ein MoneyMoney-Konto pro Voucher** (API-Liste, inkl. Pagination)
- Typ: `AccountTypeCreditCard` (Benefit-Prepaid; kein eigener Prepaid-Typ)
- Währung: aus Voucher, typisch `EUR`
- Kontonummer: `givve.<voucherId>` (Voucher-ID ist global eindeutig)
- Anzeigename: `Givve Card ****<last4> (<email>)`
- Keine Dummy-Umsätze; leere Transaktionsliste ist gültig
- Multi-Login: `accountKey` = E-Mail; mehrere Portal-Logins = mehrere Bankzugänge

## Architektur

```text
InitializeSession2
  → Connection + LocalStorage.connectionsByAccount[accountKey]
  → optional Token-Reuse (probe GET /vouchers)
  → sonst POST /api/authorizations (identifier/password)
  → bei auth_status=otp_required: Interactive → POST inkl. otp
  → access_token/refresh_token serialisierbar persistieren (keine Connection-Userdata)

ListAccounts
  → GET /api/voucher_owners/me/vouchers (alle Seiten)
  → je Voucher ein Account (Nummer givve.<id>, Name mit last4 + E-Mail)

RefreshAccount
  → Voucher-ID aus account.accountNumber
  → GET …/vouchers/{id} (Saldo)
  → GET …/transaction_groups?page[number]=1&page[size]=250&skip_meta_totals=true
    (+ optional filter[latest_booked_at][$gte]=… aus since)
  → Mapping Datum, Betrag (API-Cents/100, Ausgaben negativ), Name, bookingKey

EndSession
  → pending Password/OTP-State löschen; Token-Map behalten; kein Remote-Logout
```

### Session / Multi-Login

Folgt Hub-Spec Multi-Login LocalStorage. Die Spec liegt aktuell auf dem Hub-
Branch `feature/mm-crypto-jwe-ready` (noch nicht auf `main`):
[multi-login LocalStorage](https://github.com/rosch100/moneymoney-extensions/blob/feature/mm-crypto-jwe-ready/docs/superpowers/specs/2026-09-04-multi-login-localstorage-design.md).
Lokal im Hub-Checkout: `docs/superpowers/specs/2026-09-04-multi-login-localstorage-design.md`.
Nach Merge nach `main` den GitHub-Link auf `main` umstellen.

- `accountKey` = volle E-Mail aus `credentials[1]`, lowercased und getrimmt
  (mit `@`; nicht die Kontonummer-Slug-Form)
- Map-Eintrag: `accessToken`, `refreshToken` (Strings); zusätzlich flache
  Spiegel-Felder für Legacy-Debug
- Reuse nur bei Key-Match; abgelaufenes Token → erneuter Login (+ OTP)

### Auth (Live-HAR 2026-09-05)

| Schritt | Request |
| --- | --- |
| Login | `POST https://www.givve.com/api/authorizations` |
| Body | `{"identifier":"<email>","password":"…","accessors":["voucher_owner"],"client_id":"givve-card-web"}` |
| OTP nötig | HTTP 202, `data.auth_status = "otp_required"` |
| OTP | gleicher Endpoint + `"otp":"<code>"` → 201, `auth_status=authenticated`, `access_token`, `refresh_token` |
| Header danach | `Authorization: Bearer …`, `Accept-Version: v2`, `Content-Type: application/json`, `Origin`/`Referer` `https://card.givve.com`, `User-Agent: givve Card/8.1.1 (web)` |

Fehlerhafte Credentials: Credential-Rejection / `LoginFailed`; Netzwerk/Parse:
explizite Fehlermeldung; kein stiller Fallback, keine Dummy-Salden.

### Daten-API

1. Saldo: `GET /api/voucher_owners/me/vouchers` → `data[].balance.cents`
2. Einzelvoucher: `GET /api/voucher_owners/me/vouchers/{id}`
3. Umsätze: `GET …/transaction_groups?page[number]=1&page[size]=250&skip_meta_totals=true`
   → `amount.cents`, `merchant_name` / `description` (Load → „Aufladung“),
   `first_booked_at`, `id` als `bookingKey`

## Fehlerbehandlung

| Situation | Verhalten |
| --- | --- |
| Falsches Passwort / unbekannte E-Mail | Credential rejection (`LoginFailed`) |
| Falscher OTP-Code | Challenge erneut oder klarer Fehler |
| Abgelaufenes Token (Probe/Sync) | Fehler melden / erneuter Login; kein Fake-Erfolg |
| Parse/Netzwerk | Fehlerstring an MoneyMoney; kein leerer Erfolg mit 0-Saldo-Lüge |

## Tests

- `test_conformance.py`: Pflicht-Hooks / WebBanking-Metadaten / Allowlist-Host
- `test_givve.lua`: E-Mail/Kontonummer, Host-Allowlist, Auth-Klassifikation,
  MFA-Challenge-Tabelle, Auth-Body, Saldo-/Umsatz-Parser, `transaction_groups`-URL
- Fixtures unter `tests/fixtures/*.json` ohne echte Secrets

## Lieferstatus

1. ~~Scaffold + GitHub-Repo + Spec / Plan~~
2. ~~`Givve.lua` + Tests grün~~
3. ~~Live-Login + E-Mail-OTP verdrahten~~
4. ~~Saldo + Umsätze + Hub-Doku (Hub-Branch `docs/givve-extension-index`)~~

## Offene Punkte

- Live-Smoke in MoneyMoney (OTP-Zustellung, Token-Persistenz über Neustart,
  Sichtbarkeit **Givve Card** in der Bankauswahl bei deaktivierter Signaturprüfung)
