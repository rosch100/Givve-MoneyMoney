# givve Card — MoneyMoney Extension
Plugin Homepage: https://github.com/rosch100/Givve-MoneyMoney
Bank/Portal: https://card.givve.com (API: https://www.givve.com)
Version: **0.91** Beta
Status: E-Mail/Passwort + E-Mail-OTP (API); Saldo + Umsätze (Karteninhaber)
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
