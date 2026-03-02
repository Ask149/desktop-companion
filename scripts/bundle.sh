#!/bin/bash
set -e

# Build release binary
echo "Building release binary..."
swift build -c release

# Create app bundle structure
echo "Creating app bundle..."
BUNDLE_DIR="build/DesktopCompanion.app"
rm -rf "$BUNDLE_DIR"
mkdir -p "$BUNDLE_DIR/Contents/MacOS"
mkdir -p "$BUNDLE_DIR/Contents/Resources"

# Copy binary
cp .build/release/DesktopCompanion "$BUNDLE_DIR/Contents/MacOS/"

# Copy Info.plist
cp Info.plist "$BUNDLE_DIR/Contents/"

# Ad-hoc code sign so macOS treats it as a real app (Spotlight, Launchpad, Gatekeeper)
echo "Code signing (ad-hoc)..."
codesign --force --sign - "$BUNDLE_DIR"

echo "✅ App bundle created at $BUNDLE_DIR"
