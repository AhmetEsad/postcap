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

echo "building postcap..."

xcodebuild \
  -project postcap.xcodeproj \
  -scheme postcap \
  -configuration Release \
  -derivedDataPath "$BUILD_DIR" \
  CODE_SIGNING_ALLOWED=NO \
  build

echo "finding developer id signing identity..."

CODESIGN_IDENTITY="${CODESIGN_IDENTITY:-}"

if [[ -z "$CODESIGN_IDENTITY" ]]; then
  CODESIGN_IDENTITY="$(
    security find-identity -v -p codesigning \
      | grep "Developer ID Application" \
      | head -n 1 \
      | sed -E 's/.*"(.+)"/\1/'
  )"
fi

if [[ -z "$CODESIGN_IDENTITY" ]]; then
  echo "error: no Developer ID Application signing identity found."
  echo "available signing identities:"
  security find-identity -v -p codesigning || true
  exit 1
fi

echo "using signing identity: $CODESIGN_IDENTITY"

echo "signing app..."

codesign \
  --force \
  --deep \
  --options runtime \
  --timestamp \
  --sign "$CODESIGN_IDENTITY" \
  "$APP_PATH"

echo "verifying app signature..."

codesign --verify --deep --strict --verbose=2 "$APP_PATH"
spctl -a -vvv -t exec "$APP_PATH" || true

echo "creating dmg..."

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

echo "signing dmg..."

codesign \
  --force \
  --timestamp \
  --sign "$CODESIGN_IDENTITY" \
  "$DMG_PATH"

echo "verifying dmg signature..."

codesign --verify --verbose=2 "$DMG_PATH"
spctl -a -vvv -t open --context context:primary-signature "$DMG_PATH" || true

echo "created $DMG_PATH"