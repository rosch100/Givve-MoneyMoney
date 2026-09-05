#!/bin/sh
set -e
# MoneyMoney läuft sandboxed: Hardlinks auf Dateien außerhalb des Containers
# werden oft nicht geladen. Deshalb echte Kopie (wie die übrigen Extensions).
# Dateiname = Service-Name (Title Case), analog Presidential Bank / Shareview / Pluxee.
EXT_DIR="$HOME/Library/Containers/com.moneymoney-app.retail/Data/Library/Application Support/MoneyMoney/Extensions"
SRC="$(cd "$(dirname "$0")" && pwd)/Givve Prepaid.lua"
DST="$EXT_DIR/Givve Prepaid.lua"
# Alte Dateinamen entfernen (Kollision mit Builtin „Givve Card“ / frühere Stände)
rm -f "$DST" "$EXT_DIR/Givve Card.lua" "$EXT_DIR/Givve.lua"
cp "$SRC" "$DST"
ls -li "$DST" "$SRC"
