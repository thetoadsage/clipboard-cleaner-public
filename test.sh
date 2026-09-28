#!/bin/sh
# Runs the unit tests.
#
# On a machine with only Command Line Tools installed (no full Xcode),
# swift-testing's Testing.framework isn't on the default framework/library
# search paths, so `swift test` fails to link/load it. These flags point
# the compiler, linker, and resulting binary's rpath at it. When a full
# Xcode toolchain is selected, none of this is necessary.
set -e

DEVELOPER_DIR="$(xcode-select -p)"

if [ "$DEVELOPER_DIR" = "/Library/Developer/CommandLineTools" ]; then
  CLT="/Library/Developer/CommandLineTools/Library/Developer"
  exec swift test \
    -Xswiftc -F -Xswiftc "$CLT/Frameworks" \
    -Xswiftc -plugin-path -Xswiftc "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing" \
    -Xlinker -F -Xlinker "$CLT/Frameworks" \
    -Xlinker -L -Xlinker "$CLT/usr/lib" \
    -Xlinker -rpath -Xlinker "$CLT/Frameworks" \
    -Xlinker -rpath -Xlinker "$CLT/usr/lib" \
    -Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays \
    "$@"
else
  exec swift test "$@"
fi
