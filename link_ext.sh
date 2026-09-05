#!/bin/sh
set -e
EXT_DIR="$HOME/Library/Containers/com.moneymoney-app.retail/Data/Library/Application Support/MoneyMoney/Extensions"
SRC="$(cd "$(dirname "$0")" && pwd)/Givve Card.lua"
DST="$EXT_DIR/Givve Card.lua"
OLD="$EXT_DIR/Givve.lua"
ls -li "$DST" "$SRC" "$OLD" 2>/dev/null || true
rm -f "$DST" "$OLD"
ln "$SRC" "$DST"
ls -li "$DST" "$SRC"
