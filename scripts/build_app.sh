#!/usr/bin/env bash
# Builds "Sound Outdoor EQ.app" (Apple Silicon + Intel) into dist/.
# Usage: scripts/build_app.sh [version]   e.g. scripts/build_app.sh 1.0.0
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="${1:-${VERSION:-0.0.0-dev}}"
VERSION="${VERSION#v}"
BUILD="${BUILD_NUMBER:-1}"
APP_NAME="Sound Outdoor EQ"
EXECUTABLE="SoundOutdoorEQ"
DIST="dist"
APP="$DIST/$APP_NAME.app"

echo "Building $APP_NAME $VERSION ($BUILD)"
swift build -c release --arch arm64 --arch x86_64 --product "$EXECUTABLE"
BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$EXECUTABLE" "$APP/Contents/MacOS/$EXECUTABLE"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" Resources/Info.plist > "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist"

# Ad-hoc signature: enough to run on your own Mac. Not notarized, so the first open needs right-click > Open.
codesign --force --deep --sign - "$APP"
codesign --verify --verbose "$APP"
lipo -info "$APP/Contents/MacOS/$EXECUTABLE"

echo "Built $APP"
