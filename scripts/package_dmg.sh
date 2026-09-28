#!/bin/sh
# Produces a Finder-friendly drag-to-Applications disk image for local sharing.
# The app is ad hoc signed; add Developer ID signing and notarization before a
# broader public release.
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
APP_NAME="Clipboard Cleaner"
APP_PATH="$ROOT_DIR/build/$APP_NAME.app"
DIST_DIR="$ROOT_DIR/dist"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/clipboard-cleaner-dmg.XXXXXX")"

cleanup() {
  rm -rf "$STAGING_DIR"
}
trap cleanup EXIT HUP INT TERM

"$SCRIPT_DIR/build_app.sh" "$@"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")"
DMG_PATH="$DIST_DIR/Clipboard-Cleaner-$VERSION.dmg"

mkdir -p "$DIST_DIR"
rm -f "$DMG_PATH"

# Create the standard Finder layout: the app plus an Applications shortcut.
xattr -cr "$APP_PATH"
ditto --norsrc "$APP_PATH" "$STAGING_DIR/$APP_NAME.app"
ln -s /Applications "$STAGING_DIR/Applications"

hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGING_DIR" \
  -format UDZO \
  -ov \
  "$DMG_PATH"
hdiutil verify "$DMG_PATH"

echo "Packaged: $DMG_PATH"
echo "The DMG is ad hoc signed for local sharing; notarize it before a public release."
