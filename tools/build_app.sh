#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
VERSION=$(cat "$ROOT_DIR/VERSION")
BUILD_DIR="$ROOT_DIR/build"
APP_DIR="$BUILD_DIR/Taken.app"

if [ -x "$ROOT_DIR/tools/build_icons.sh" ]; then
  "$ROOT_DIR/tools/build_icons.sh"
fi

swift build -c release --package-path "$ROOT_DIR"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$ROOT_DIR/.build/release/taken" "$APP_DIR/Contents/MacOS/taken"
chmod +x "$APP_DIR/Contents/MacOS/taken"

sed "s/__VERSION__/$VERSION/g" "$ROOT_DIR/App/Info.plist" > "$APP_DIR/Contents/Info.plist"

if [ -f "$BUILD_DIR/Icon.icns" ]; then
  cp "$BUILD_DIR/Icon.icns" "$APP_DIR/Contents/Resources/Icon.icns"
fi

if [ -f "$BUILD_DIR/MenuBarTemplate.pdf" ]; then
  cp "$BUILD_DIR/MenuBarTemplate.pdf" "$APP_DIR/Contents/Resources/MenuBarTemplate.pdf"
elif [ -f "$BUILD_DIR/MenuBarTemplate.png" ]; then
  cp "$BUILD_DIR/MenuBarTemplate.png" "$APP_DIR/Contents/Resources/MenuBarTemplate.png"
fi

echo "Built $APP_DIR"
