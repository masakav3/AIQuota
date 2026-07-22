#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
source "$ROOT/version.env"

export ARCHES="${ARCHES:-arm64 x86_64}"
export CODEXBAR_SIGNING=adhoc
export AIQUOTA_INCLUDE_WIDGET=0

"$ROOT/Scripts/package_app.sh" release

DIST_DIR="$ROOT/dist"
APP_PATH="$ROOT/AI Quota.app"
ZIP_PATH="$DIST_DIR/AI-Quota-macos-universal-${MARKETING_VERSION}.zip"
mkdir -p "$DIST_DIR"
rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

echo "Created $ZIP_PATH"
