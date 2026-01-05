#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
VERSION=$(cat "$ROOT_DIR/VERSION")
BUILD_DIR="$ROOT_DIR/build"
ARCHIVE_NAME="Taken-$VERSION.zip"

"$ROOT_DIR/tools/build_app.sh"

cd "$BUILD_DIR"
rm -f "$ARCHIVE_NAME"
zip -r "$ARCHIVE_NAME" "Taken.app" >/dev/null

SHA=$(shasum -a 256 "$ARCHIVE_NAME" | awk '{print $1}')

echo "Archive: $BUILD_DIR/$ARCHIVE_NAME"
echo "SHA256: $SHA"
