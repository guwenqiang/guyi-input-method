#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
identity="${GUYI_SIGNING_IDENTITY:--}"
if test -z "${GUYI_SIGNING_IDENTITY:-}" && test -f "$HOME/Library/Application Support/guyi/Signing/identity.txt"; then
    identity="$(cat "$HOME/Library/Application Support/guyi/Signing/identity.txt")"
fi
export GUYI_SIGNING_IDENTITY="$identity"
export GUYI_RELEASE_BUILD=0
if test "${1:-}" = "--release"; then
    if ! security find-identity -v -p codesigning | awk -v identity="$identity" 'index($0, identity) && index($0, "Developer ID Application:") { found=1 } END { exit !found }'; then
        printf 'Release builds require a valid Apple Developer ID Application identity, not a local development certificate.\n' >&2
        exit 1
    fi
    export GUYI_RELEASE_BUILD=1
fi
if test "${1:-}" = "--release" && test "$identity" = "-"; then
    printf 'Release builds require GUYI_SIGNING_IDENTITY. Ad-hoc updates invalidate Keychain and screen-recording trust.\n' >&2
    exit 1
fi
if test "$identity" = "-"; then
    printf 'WARNING: development ad-hoc signing; screen-recording and legacy Keychain migration may require renewed approval. Local credential files are unaffected.\n' >&2
fi
bash scripts/compile.sh
python3 scripts/bundle.py
swift scripts/icon.swift dist/.build.noindex/Guyi.app/Contents/Resources
bash scripts/sign-app.sh dist/.build.noindex/Guyi.app
# A signed build artifact shares the installed IME bundle ID. Keep only the
# installed copy registered with LaunchServices after local builds.
registry='/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister'
"$registry" -u "$PWD/dist/.build.noindex/Guyi.app" ||
    printf 'WARNING: could not unregister the local build artifact; verify LaunchServices before installation.\n' >&2
swiftc -swift-version 5 Sources/GuyiLauncher/main.swift -o .build/release/guyi-launcher
python3 scripts/launcher-bundle.py
swiftc -swift-version 5 Sources/GuyiInstaller/*.swift -o .build/release/InstallGuYi
bash scripts/sign-app.sh .build/release/InstallGuYi
printf 'Built %s/dist/.build.noindex/Guyi.app\n' "$PWD"
