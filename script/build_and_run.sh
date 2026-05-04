#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCHEME="postcap"
APP_NAME="Postcap"
PROJECT="$ROOT/postcap.xcodeproj"
CONFIGURATION="Debug"
DERIVED_DATA="$ROOT/.build/DerivedData"

pkill -x "$APP_NAME" 2>/dev/null || true

xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA" \
  build

APP_PATH="$DERIVED_DATA/Build/Products/$CONFIGURATION/$APP_NAME.app"
/usr/bin/open -n "$APP_PATH"

if [[ "${1:-}" == "--verify" ]]; then
  sleep 2
  pgrep -x "$APP_NAME" >/dev/null
fi
