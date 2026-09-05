# Givve Prepaid — MoneyMoney-Erweiterung

Givve-Prepaid-Karten (Saldo und Umsätze) in MoneyMoney.

Version: **1.00**
Repository: https://github.com/rosch100/Givve-MoneyMoney
Gemeinsame Infos: https://github.com/rosch100/moneymoney-extensions

## Installation

Unsignierte Datei:
[Givve Prepaid.lua](https://raw.githubusercontent.com/rosch100/Givve-MoneyMoney/main/Givve%20Prepaid.lua)

Datei nach
`~/Library/Containers/com.moneymoney-app.retail/Data/Library/Application Support/MoneyMoney/Extensions`
**kopieren** (keine Hardlinks — die Sandbox lädt sie oft nicht), oder im Klon
`./link_ext.sh` ausführen. Danach MoneyMoney neu starten.

Unsignierte Plugins: MoneyMoney-**Beta**, Signaturprüfung unter
*MoneyMoney → Einstellungen → Erweiterungen* ausschalten.

## Einrichten

*Konto hinzufügen* → *Andere* (nicht IBAN/BLZ) → **Givve Prepaid**.

Nicht „Givve Card“ wählen — das ist MoneyMoney’s eingebaute Kreditkarte.

Benutzername = E-Mail, Passwort = Portal-Passwort. Bei Nachfrage den Code aus
der E-Mail eingeben.

Mehrere Portallogins: je einen Bankzugang mit eigener E-Mail anlegen.

## Nutzung

Jede Prepaid-Karte erscheint als eigenes Konto. Bei mehreren Karten stehen die
letzten vier Ziffern im Namen.

Ältere Konten mit anderer Nummernform werden weiter aktualisiert; für die
maskierte Kartennummer in der Übersicht ggf. Konto neu anlegen.

## Lizenz

MIT — siehe [LICENSE](LICENSE).
