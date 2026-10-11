#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift scripts/register.swift --preflight
fixture="$PWD/.build/SandboxInputFixture.app"
if pgrep -x RawEnterSmoke >/dev/null; then
    printf 'A fixture is already running; close it before another test.\n' >&2
    exit 2
fi
mkdir -p "$fixture/Contents/MacOS"
client_flags=()
if test "${GUYI_TEST_CLIENT_SDK:-}" = "15.2"; then
    client_flags=(-target arm64-apple-macos14.0 -Xlinker -platform_version -Xlinker macos -Xlinker 14.0 -Xlinker 15.2)
fi
swiftc -swift-version 5 ${client_flags[@]+"${client_flags[@]}"} scripts/raw-enter-smoke.swift -o "$fixture/Contents/MacOS/RawEnterSmoke.new"
mv "$fixture/Contents/MacOS/RawEnterSmoke.new" "$fixture/Contents/MacOS/RawEnterSmoke"
python3 - "$fixture" <<'PY'
import plistlib
import sys
from pathlib import Path
root = Path(sys.argv[1])
with (root / "Contents/Info.plist").open("wb") as output:
    plistlib.dump({"CFBundleExecutable": "RawEnterSmoke",
                  "CFBundleIdentifier": "app.guyi.sandbox-input-fixture",
                  "CFBundlePackageType": "APPL"}, output)
with (root.parent / "sandbox-input.entitlements").open("wb") as output:
    plistlib.dump({"com.apple.security.app-sandbox": True}, output)
PY
identity="${GUYI_SIGNING_IDENTITY:--}"
if test -z "${GUYI_SIGNING_IDENTITY:-}" && test -f "$HOME/Library/Application Support/guyi/Signing/identity.txt"; then
    identity="$(cat "$HOME/Library/Application Support/guyi/Signing/identity.txt")"
fi
codesign --force --sign "$identity" --entitlements .build/sandbox-input.entitlements "$fixture"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$fixture"
logs="$(mktemp -d "${TMPDIR:-/tmp/}guyi-sandbox-test.XXXXXX")"
output="$logs/output.log"
errors="$logs/errors.log"
trap 'cp "$output" .build/sandbox-input-smoke.log; cp "$errors" .build/sandbox-input-smoke.err; rm -rf "$logs"' EXIT
: > "$output"
: > "$errors"
swiftc scripts/sandbox-input-driver.swift -o .build/sandbox-input-driver
open -n -W --stdout "$output" --stderr "$errors" "$fixture" --args --external-events "$@" &
launcher=$!
.build/sandbox-input-driver "$output" "$@" &
driver=$!
sleep 2
osascript <<'APPLESCRIPT'
tell application id "app.guyi.sandbox-input-fixture" to activate
tell application "System Events"
    set frontID to bundle identifier of (first application process whose frontmost is true)
    if frontID is not "app.guyi.sandbox-input-fixture" then error "Fixture is not frontmost; no input sent"
    tell process "TextInputMenuAgent"
        click menu bar item 1 of menu bar 2
        set inputMenu to menu 1 of menu bar item 1 of menu bar 2
        try
            set sourceItem to first menu item of inputMenu whose name starts with "GuYi"
            if not enabled of sourceItem then error "GuYi source is disabled"
            click sourceItem
        on error reason
            perform action "AXCancel" of inputMenu
            error reason
        end try
    end tell
end tell
APPLESCRIPT
wait "$launcher"
driver_result=0
wait "$driver" || driver_result=$?
cat "$output"
expected='PASS · Candidate anchor'
if [[ " $* " == *' --basic-only '* ]]; then expected='PASS · Basic input fixture completed'; fi
if [[ " $* " == *' --multilingual '* ]]; then expected='PASS · Multilingual fixture completed'; fi
if [[ " $* " == *' --rapid-input '* ]]; then expected='PASS · Rapid input preserved'; fi
if [[ " $* " == *' --selection '* ]]; then expected='PASS · Selection fixture completed'; fi
if [[ " $* " == *' --inspect-candidate '* ]]; then expected='PASS · Candidate inspection completed'; fi
if [[ " $* " == *' --inspect-emoji '* ]]; then expected='PASS · Emoji candidate explicitly inserted'; fi
if [[ " $* " == *' --manual-acceptance '* ]]; then expected='PASS · Manual input committed'; fi
if test "$driver_result" != 0 || grep -Eq 'FAIL|BLOCKED' "$output" || ! grep -q "$expected" "$output"; then
    tail -20 "$errors" >&2
    exit 1
fi
