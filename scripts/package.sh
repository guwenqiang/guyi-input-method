#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test -d dist/.build.noindex/Guyi.app || bash scripts/build.sh
identity="${GUYI_SIGNING_IDENTITY:--}"
if test -z "${GUYI_SIGNING_IDENTITY:-}" && test -f "$HOME/Library/Application Support/guyi/Signing/identity.txt"; then
    identity="$(cat "$HOME/Library/Application Support/guyi/Signing/identity.txt")"
fi
package_dir="$PWD/dist/.package-staging.noindex/GuYi-Input-Method-macOS-arm64"
if test -d "$package_dir"; then rm -rf "$package_dir"; fi
mkdir -p "$package_dir"
export GUYI_SIGNING_IDENTITY="$identity"
if codesign -dv --verbose=4 dist/.build.noindex/Guyi.app 2>&1 | grep -q '^Authority=Developer ID Application:'; then
    export GUYI_RELEASE_BUILD=1
fi
bash scripts/build-pkg.sh
python3 scripts/pkg-smoke.py
cp dist/GuYi-Input-Method-macOS-arm64.pkg "$package_dir/GuYi-Input-Method.pkg"
python3 scripts/help.py
ditto .build/help "$package_dir/Help"
cp docs/使用说明.html "$package_dir/User Guide.html"
ditto -c -k --keepParent "$package_dir" dist/GuYi-Input-Method-macOS-arm64.zip
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' dist/.build.noindex/Guyi.app/Contents/Info.plist)
dmg="dist/GuYi-Input-Method-${version}-macOS-arm64.dmg"
hdiutil create -volname 'GuYi Input Method' -srcfolder "$package_dir" -ov -format UDZO "$dmg"
shasum -a 256 dist/GuYi-Input-Method-macOS-arm64.pkg dist/GuYi-Input-Method-macOS-arm64.zip "$dmg" > dist/SHA256SUMS.txt
