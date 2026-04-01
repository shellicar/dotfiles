#!/usr/bin/env sh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="/mnt/c/Users/Stephen/AppData/Local/Microsoft/PowerToys/FancyZones/custom-layouts.json"
DEST="$SCRIPT_DIR/config/custom-layouts.json"

if [ ! -f "$SRC" ]; then
    echo "Source not found: $SRC"
    exit 1
fi

cp "$SRC" "$DEST"
echo "Synced FancyZones config to $DEST"
