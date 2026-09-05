# Givve Prepaid — MoneyMoney Extension
Plugin Homepage: https://github.com/rosch100/Givve-MoneyMoney
Bank/Portal: https://card.givve.com (API: https://www.givve.com)
Version: **1.05**
Status: E-Mail/Passwort + E-Mail-OTP (API); Saldo + Umsätze (Builtin-nah: name/purpose/valueDate); ein Konto pro Voucher
Hub (gemeinsame Tools/Doku): https://github.com/rosch100/moneymoney-extensions

## Installation
Unsignierte Datei: [Givve Prepaid.lua](https://raw.githubusercontent.com/rosch100/Givve-MoneyMoney/main/Givve%20Prepaid.lua)

Datei nach
`~/Library/Containers/com.moneymoney-app.retail/Data/Library/Application Support/MoneyMoney/Extensions`
**kopieren** (keine Hardlinks — die Sandbox lädt sie oft nicht), oder im Klon
`./link_ext.sh` ausführen (legt eine echte Kopie an). Danach MoneyMoney neu starten.

Unsignierte Plugins: MoneyMoney-**Beta**, Signaturprüfung unter
*MoneyMoney → Einstellungen → Erweiterungen* **ausschalten**.

In MoneyMoney: **Konto → Konto hinzufügen → Andere** (nicht IBAN/BLZ) →
**Givve Prepaid** wählen. Plugin-Dateiname und Service-Name sind identisch
(Title Case, Sibling-Konvention). Nicht „Givve Card“ — das ist MoneyMoney’s
eingebaute Kreditkarte (wie „Amazon Bestellungen“ vs. „Amazon-Kreditkarte“).
Benutzername = E-Mail, Passwort = Portal-Passwort. Bei OTP den Code aus der
E-Mail eingeben.

## Konten / Multi-Voucher
Jeder Voucher (Prepaid-Karte) wird als eigenes Konto angelegt:

- Name: `givve` (eine Karte) bzw. `givve ****<last4>` (mehrere Karten)
- Kontonummer (Übersicht): maskierte Kartennummer aus der API, z. B.
  `521965******6363` (volle PAN liefert die API nicht)

Bestehende Konten mit alter Nummer `givve.<voucherId>` werden beim Abruf
weiter erkannt; für die Anzeige-PAN Konto neu anlegen.

## Multi-Login
Mehrere Portallogins: je einen Bankzugang mit eigener E-Mail anlegen.
Sessions liegen in `LocalStorage.connectionsByAccount`.

## Tests
```sh
python3 tests/test_conformance.py
luajit tests/test_givve.lua
```
Aus dem Repo-Root ausführen.

## Lizenz
MIT — siehe [LICENSE](LICENSE).
