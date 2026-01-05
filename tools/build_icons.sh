#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BUILD_DIR="$ROOT_DIR/build"
ICON_PNG="$ROOT_DIR/icons/app.png"
MENU_PDF="$ROOT_DIR/icons/menu.pdf"
MENU_PNG="$ROOT_DIR/icons/menu.png"
ICONSET_DIR="$BUILD_DIR/AppIcon.iconset"

mkdir -p "$BUILD_DIR"

if [ -f "$ICON_PNG" ]; then
  rm -rf "$ICONSET_DIR"
  mkdir -p "$ICONSET_DIR"

  sips -z 16 16   "$ICON_PNG" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
  sips -z 32 32   "$ICON_PNG" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
  sips -z 32 32   "$ICON_PNG" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
  sips -z 64 64   "$ICON_PNG" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
  sips -z 128 128 "$ICON_PNG" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
  sips -z 256 256 "$ICON_PNG" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
  sips -z 256 256 "$ICON_PNG" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
  sips -z 512 512 "$ICON_PNG" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
  sips -z 512 512 "$ICON_PNG" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
  sips -z 1024 1024 "$ICON_PNG" --out "$ICONSET_DIR/icon_512x512@2x.png" >/dev/null

  iconutil -c icns "$ICONSET_DIR" -o "$BUILD_DIR/Icon.icns"
fi

if [ -f "$MENU_PDF" ]; then
  cp "$MENU_PDF" "$BUILD_DIR/MenuBarTemplate.pdf"
elif [ -f "$MENU_PNG" ]; then
  cp "$MENU_PNG" "$BUILD_DIR/MenuBarTemplate.png"
fi
