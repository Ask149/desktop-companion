#!/bin/bash
set -e

# Build the app bundle
./scripts/bundle.sh

APP_NAME="DesktopCompanion"
BUNDLE_DIR="build/${APP_NAME}.app"
INSTALL_DIR="/Applications"

# Kill existing instance if running
echo "Stopping existing instance..."
pkill -f "$APP_NAME" || true

# Copy to /Applications
echo "Installing to $INSTALL_DIR..."
rm -rf "$INSTALL_DIR/$APP_NAME.app"
cp -R "$BUNDLE_DIR" "$INSTALL_DIR/"

# Launch the app
echo "Launching $APP_NAME..."
open "$INSTALL_DIR/$APP_NAME.app"

echo ""
echo "✅ Installation complete!"
echo ""
echo "To launch at login, add to Login Items:"
echo "  System Settings → General → Login Items → + → /Applications/$APP_NAME.app"
echo ""
echo "Or run this command:"
echo "  osascript -e 'tell application \"System Events\" to make login item at end with properties {path:\"/Applications/$APP_NAME.app\", hidden:false}'"
