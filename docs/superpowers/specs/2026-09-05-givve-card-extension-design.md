# givve Card — MoneyMoney Extension Design

Datum: 2026-09-05

Status: **Approved** (Design), Implementation pending

## Ziel

Eigenes Repository und MoneyMoney-Web-Banking-Extension für das
**givve Card Karteninhaber-Portal** (`https://card.givve.com`): Login mit
E-Mail/Passwort, E-Mail-MFA, Saldo und Umsätze in MoneyMoney.

## Kontext

- Hub: [moneymoney-extensions](https://github.com/rosch100/moneymoney-extensions)
- Sibling-Muster: `*-MoneyMoney` als Nested-Git-Repos unter dem Hub,
  Remote unter `rosch100` auf GitHub
- Portal: `https://card.givve.com/login` (offizielle Cardholder-URL laut givve)
- Kein Business-/Admin-Portal in v1

## Entscheidungen (bestätigt)

| Thema | Entscheidung |
| --- | --- |
| Lieferumfang | Scaffold + Design/Implementierung in derselben Session-Kette |
| Auth | Username/Passwort direkt im Plugin (kein Cookie-Import in v1) |
| Scope | Karteninhaber: eine Prepaid-/Benefit-Karte, Saldo + Umsätze |
| MFA | Erwartet; Typ E-Mail-Code via MoneyMoney-Interactive-Challenge |
| Ansatz | Sibling-Scaffold + Portal-Login; HTML und/oder XHR, was der Live-Lauf liefert |

## Nicht-Ziele (v1)

- givve Business-/Admin-Portal
- Kartenaktivierung, PIN-Anzeige, Sperren/Entsperren
- Cookie-Import (`COOKIE:…`)
- App-Push-MFA / TOTP (nur E-Mail-Code)
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
    fixtures/          # HTML/JSON-Snippets, keine Credentials
  docs/superpowers/    # Pläne nach writing-plans; Spec-Spiegel optional
```

Hub-Updates nach Repo-Create: Zeile in Hub-`README.md`-Tabelle und Kurzabschnitt
in `docs/LUA-EXTENSIONS.md`.

## MoneyMoney-Vertragsfläche

- `WebBanking`: `services = {"givve Card"}`, `url = "https://card.givve.com"`,
  `version = 0.91`, Beschreibung kurz auf Deutsch/Englisch
- `SupportsBank`: `ProtocolWebBanking` und BankCode/Service `givve Card`
- Hooks: `InitializeSession2`, `ListAccounts`, `RefreshAccount`, `EndSession`
- Credentials: `[1]` = E-Mail, `[2]` = Passwort
- Host-Allowlist: nur `card.givve.com` (plus weitere Hosts nur nach Live-Befund,
  wenn Login/API sie zwingend braucht — dann explizit in CONSTANTS und Tests)

### Kontomodell

- Ein Konto pro Login
- Typ: Prepaid-/Kartenkonto — `AccountTypeCreditCard` (Benefit-Prepaid;
  MoneyMoney hat keinen eigenen Prepaid-Typ)
- Währung: EUR
- Kontonummer: `givve.<normalized-email>` — volle E-Mail, lowercased, Trim;
  `@` in der Nummer durch `.` ersetzen (MoneyMoney-tauglich). Beispiel:
  `user@firma.de` → `givve.user.firma.de`. Vermeidet Kollisionen bei gleicher
  Local-Part unterschiedlicher Domains.
- Anzeigename: `givve Card (<email>)` — Multi-Login-fähig analog Hub-Spec
- Keine Dummy-Umsätze; leere Transaktionsliste ist gültig

## Architektur

```text
InitializeSession2
  → Connection + LocalStorage.connectionsByAccount[accountKey]
  → Requests nur gegen Allowlist-Hosts (card.givve.com, …)
  → Login E-Mail/Passwort gegen card.givve.com
  → bei MFA: Interactive (E-Mail-Code) → absenden
  → Session-State serialisierbar persistieren (keine Connection-Userdata)

ListAccounts
  → Home/Übersicht: Saldo, Anzeigename, ggf. last4
  → ein Account emitten

RefreshAccount
  → Umsätze seit `since` (HTML und/oder XHR)
  → Mapping Datum, Betrag (Ausgaben negativ), Name, optionale Booking-ID

EndSession
  → bei persistierter Map keinen Remote-Logout; Bucket behalten
```

### Session / Multi-Login

Folgt Hub-Spec Multi-Login LocalStorage. Die Spec liegt aktuell auf dem Hub-
Branch `feature/mm-crypto-jwe-ready` (noch nicht auf `main`):
[multi-login LocalStorage](https://github.com/rosch100/moneymoney-extensions/blob/feature/mm-crypto-jwe-ready/docs/superpowers/specs/2026-09-04-multi-login-localstorage-design.md).
Lokal im Hub-Checkout: `docs/superpowers/specs/2026-09-04-multi-login-localstorage-design.md`.
Nach Merge nach `main` den GitHub-Link auf `main` umstellen.

- `accountKey` = volle E-Mail aus `credentials[1]`, lowercased und getrimmt
  (mit `@`; nicht die Kontonummer-Slug-Form)
- Map-Eintrag: Cookies/Tokens als serialisierbare Strings/Tabellen
- Reuse nur bei Key-Match; abgelaufene Session → erneuter Login (+ MFA)

### Auth-Details (Live nachziehen)

Exakte Form-Felder, CSRF, MFA-Endpunkte und Response-Marker werden beim
ersten Live-Login gegen `card.givve.com` festgenagelt — nicht geraten.
Fehlerhafte Credentials: Credential-Rejection-Marker; Netzwerk/Parse: explizite
Fehlermeldung; kein stiller Fallback, keine Dummy-Salden.

### Parsing-Strategie

1. Bevorzugt stabile XHR/JSON-APIs, falls der Browser-Traffic sie zeigt
2. Sonst gezieltes HTML-Parsing der Portal-Seiten
3. Parser in testbaren Lua-Funktionen mit Fixtures; UI-Strings nicht hardcoden,
   wo Selektoren/JSON-Felder robuster sind

## Fehlerbehandlung

| Situation | Verhalten |
| --- | --- |
| Falsches Passwort / unbekannte E-Mail | Credential rejection |
| Falscher MFA-Code | Challenge erneut oder klarer Fehler |
| Session abgelaufen mid-sync | Re-Login bzw. Fehler melden, kein Fake-Erfolg |
| Parse/Netzwerk | Fehlerstring an MoneyMoney; kein leerer Erfolg mit 0-Saldo-Lüge |

## Tests

- `test_conformance.py`: Pflicht-Hooks / WebBanking-Metadaten
- `test_givve.lua`: Login-Schritt-Erkennung, MFA-Prompt-Pfad, Saldo-/Umsatz-Parser
  gegen Fixtures
- Keine echten Secrets in Repo oder Fixtures

## Lieferreihenfolge

1. Scaffold + GitHub-Repo + diese Spec / Implementation Plan
2. Stub-`Givve.lua` mit Hooks + Tests grün
3. Live-Login + E-Mail-MFA verdrahten
4. Saldo + Umsätze + Hub-Doku

## Offene Punkte (nur Live, kein Spec-Blocker)

- Konkrete Login-/MFA-Request-Formate
- Ob Umsätze paginiert/API-basiert sind
- Ob ein Login mehrere physische Karten zeigen kann (v1: trotzdem ein
  MoneyMoney-Konto oder bewusst erweitern — Default ein Konto; bei mehreren
  Karten im Portal: eine pro Karte erst nach Live-Befund)
