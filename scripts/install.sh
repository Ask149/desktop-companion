#!/bin/bash
set -e

APP_NAME="Friday"
SRC="build/${APP_NAME}.app"
DEST="/Applications/${APP_NAME}.app"

if [ ! -d "$SRC" ]; then
    echo "Error: $SRC not found. Run scripts/bundle.sh first."
    exit 1
fi

echo "Installing ${APP_NAME} to /Applications..."

# Kill if running
pkill -f "DesktopCompanion" 2>/dev/null || true
sleep 1

rm -rf "$DEST"
cp -R "$SRC" "$DEST"

# Re-index Spotlight
mdimport "$DEST"

echo "Installed: $DEST"
echo "Launch: open /Applications/${APP_NAME}.app"
