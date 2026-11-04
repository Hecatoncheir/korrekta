#!/usr/bin/env bash
set -euo pipefail
version="$1"
mkdir -p release/dmg-stage
ditto app/build/macos/Build/Products/Release/korrekta.app release/dmg-stage/Корректа.app
ln -s /Applications release/dmg-stage/Applications
hdiutil create -volname Корректа -srcfolder release/dmg-stage -ov -format UDZO "release/Korrekta-${version}-macos-universal.dmg"
