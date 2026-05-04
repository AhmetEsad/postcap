#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/DerivedData"
RELEASE_DIR="$BUILD_DIR/Build/Products/Release"
APP_PATH="$RELEASE_DIR/Postcap.app"
DIST_DIR="$ROOT_DIR/dist"
STAGING_DIR="$DIST_DIR/Postcap"
DMG_PATH="$DIST_DIR/Postcap.dmg"

cd "$ROOT_DIR"

xcodebuild \
  -project postcap.xcodeproj \
  -scheme postcap \
  -configuration Release \
  -derivedDataPath "$BUILD_DIR" \
  build

codesign --force --deep --sign - "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

rm -rf "$STAGING_DIR" "$DMG_PATH"
mkdir -p "$STAGING_DIR"
cp -R "$APP_PATH" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

hdiutil create \
  -volname Postcap \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo "Created $DMG_PATH"
