#!/bin/sh
# Produces a versioned app archive and SHA-256 checksum. Signing remains ad
# hoc until the separate Developer ID/notarization release work is enabled.
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
APP_PATH="$ROOT_DIR/build/Clipboard Cleaner.app"
DIST_DIR="$ROOT_DIR/dist"

"$SCRIPT_DIR/build_app.sh" "$@"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")"
ARCHIVE="Clipboard-Cleaner-$VERSION.zip"

mkdir -p "$DIST_DIR"
rm -f "$DIST_DIR/$ARCHIVE" "$DIST_DIR/SHA256SUMS"
xattr -cr "$APP_PATH"
ditto --norsrc -c -k --keepParent "$APP_PATH" "$DIST_DIR/$ARCHIVE"
# Some file-provider-backed workspaces reattach FinderInfo while `ditto`
# reads the bundle. Keep the source bundle strict-verification clean too.
xattr -cr "$APP_PATH"
(
  cd "$DIST_DIR"
  shasum -a 256 "$ARCHIVE" > SHA256SUMS
  shasum -a 256 -c SHA256SUMS
)

echo "Packaged: $DIST_DIR/$ARCHIVE"
echo "Checksum: $DIST_DIR/SHA256SUMS"
