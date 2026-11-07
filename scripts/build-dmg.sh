#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build-app.sh
staging_dir="$(mktemp -d "$PWD/.build/dmg.XXXXXX")"
trap 'rm -rf "$staging_dir"' EXIT
ditto "dist/Dock Twin.app" "$staging_dir/Dock Twin.app"
ln -s /Applications "$staging_dir/Applications"
cp docs/INSTALL.txt "$staging_dir/INSTALL.txt"
cp LICENSE "$staging_dir/LICENSE.txt"
hdiutil create -volname "Dock Twin" -srcfolder "$staging_dir" -format UDZO -ov "dist/Dock Twin.dmg"
hdiutil verify "dist/Dock Twin.dmg"
