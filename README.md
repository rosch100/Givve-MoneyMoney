# Givve Card — MoneyMoney Extension
Plugin Homepage: https://github.com/rosch100/Givve-MoneyMoney
Bank/Portal: https://card.givve.com (API: https://www.givve.com)
Version: **1.00**
Status: E-Mail/Passwort + E-Mail-OTP (API); Saldo + Umsätze; ein Konto pro Voucher
Hub (gemeinsame Tools/Doku): https://github.com/rosch100/moneymoney-extensions

## Installation
Unsignierte Datei: [Givve Card.lua](https://raw.githubusercontent.com/rosch100/Givve-MoneyMoney/main/Givve%20Card.lua)

Datei nach
`~/Library/Containers/com.moneymoney-app.retail/Data/Library/Application Support/MoneyMoney/Extensions`
kopieren, oder im Klon `./link_ext.sh` ausführen.

Unsignierte Plugins: MoneyMoney-**Beta**, Signaturprüfung unter
*MoneyMoney → Einstellungen → Erweiterungen* **ausschalten**.

In MoneyMoney: Bankzugang anlegen → nach **Givve Card** suchen (Title Case).
Benutzername = E-Mail, Passwort = Portal-Passwort. Bei OTP den Code aus der
E-Mail eingeben.

## Konten / Multi-Voucher
Jeder Voucher (Prepaid-Karte) wird als eigenes Konto angelegt:

- Kontonummer: `givve.<voucherId>`
- Name: `Givve Card ****<last4> (<email>)`

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
