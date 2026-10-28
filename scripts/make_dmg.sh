#!/usr/bin/env bash
# Packs dist/Sound Outdoor EQ.app into dist/SoundOutdoorEQ[-version].dmg with an Applications shortcut.
# Usage: scripts/make_dmg.sh [version]
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="${1:-${VERSION:-}}"
VERSION="${VERSION#v}"
APP_NAME="Sound Outdoor EQ"
DIST="dist"
APP="$DIST/$APP_NAME.app"
DMG="$DIST/SoundOutdoorEQ${VERSION:+-$VERSION}.dmg"
STAGING="$DIST/dmg-staging"

[ -d "$APP" ] || { echo "Missing $APP. Run scripts/build_app.sh first." >&2; exit 1; }

rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -ov -format UDZO "$DMG"
rm -rf "$STAGING"
hdiutil verify "$DMG"

echo "Created $DMG"
