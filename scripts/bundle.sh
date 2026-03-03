#!/bin/bash
set -e

APP_NAME="Friday"
BUILD_DIR=".build/release"
APP_DIR="build/${APP_NAME}.app"

echo "Building release..."
swift build -c release

echo "Creating app bundle..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "${BUILD_DIR}/DesktopCompanion" "$APP_DIR/Contents/MacOS/DesktopCompanion"
cp Info.plist "$APP_DIR/Contents/"

echo "Signing..."
codesign --force --deep --sign - "$APP_DIR"

echo "Done: $APP_DIR"
