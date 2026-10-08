#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test -d dist/.build.noindex/Guyi.app || bash scripts/build.sh
if ! test -x .build/release/InstallGuYi; then
    swiftc -swift-version 5 Sources/GuyiInstaller/*.swift -o .build/release/InstallGuYi
fi
swift scripts/register.swift --preflight
if pgrep -x guyi >/dev/null; then
    printf 'GuYi Input Method is running. Switch to another input source and quit it before updating. No files were replaced.\n' >&2
    exit 1
fi
launcher_name="GuYi Input Method.app"
case "$(defaults read -g AppleLanguages 2>/dev/null | sed -n '2p')" in *zh*) launcher_name="GuYi输入法.app" ;; esac
destination="$HOME/Library/Input Methods/$launcher_name"
for directory in "/Library/Input Methods" "$HOME/Library/Input Methods"; do
    for name in "GuYi输入法.app" "GuYi Input Method.app" "Guyi.app"; do
        candidate="$directory/$name"
        if test -d "$candidate" && test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$candidate/Contents/Info.plist" 2>/dev/null)" = "app.guyi.inputmethod.Guyi"; then
            destination="$candidate"
            break 2
        fi
    done
done
if test -L "$destination"; then printf 'Refusing a symlink installation destination.\n' >&2; exit 1; fi
codesign --verify --deep --strict dist/.build.noindex/Guyi.app
backup_root="$HOME/Library/Application Support/guyi/Backups"
mkdir -p "$HOME/Library/Input Methods"
mkdir -p "$backup_root"
if test -d "$destination"; then
    mkdir -p "$HOME/Library/Application Support/guyi/Backups"
    backup="$HOME/Library/Application Support/guyi/Backups/Guyi.$(date +%Y%m%d%H%M%S).backup"
    ditto "$destination" "$backup"
fi
if [[ "$destination" == /Library/Input\ Methods/* ]]; then
    osascript - "$PWD/.build/release/InstallGuYi" "$PWD/dist/.build.noindex/Guyi.app" "$destination" <<'APPLESCRIPT'
on run arguments
    do shell script quoted form of (item 1 of arguments) & " " & quoted form of (item 2 of arguments) & " " & quoted form of (item 3 of arguments) with administrator privileges
end run
APPLESCRIPT
else
    .build/release/InstallGuYi "$PWD/dist/.build.noindex/Guyi.app" "$destination"
fi
codesign --verify --deep --strict "$destination"
for old_name in "Guyi.app" "GuYi Input Method.app" "GuYi输入法.app"; do
    old_path="$HOME/Library/Input Methods/$old_name"
    if test "$old_path" != "$destination" && test -d "$old_path" && test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$old_path/Contents/Info.plist" 2>/dev/null)" = "app.guyi.inputmethod.Guyi"; then
        mv "$old_path" "$backup_root/InputMethod.$old_name.$(date +%Y%m%d%H%M%S).backup"
    fi
done
applications="/Applications"
if ! test -w "$applications"; then applications="$HOME/Applications"; fi
mkdir -p "$applications"
for old_name in "GuYi.app" "GuYi Input Method.app" "GuYi输入法.app"; do
if test "$old_name" != "$launcher_name" && test -d "$applications/$old_name" && test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$applications/$old_name/Contents/Info.plist" 2>/dev/null)" = "app.guyi.launcher"; then
    mkdir -p "$HOME/Library/Application Support/guyi/Backups"
    mv "$applications/$old_name" "$HOME/Library/Application Support/guyi/Backups/Launcher.$old_name.$(date +%Y%m%d%H%M%S).backup"
fi
done
.build/release/InstallGuYi "$PWD/dist/Launcher/GuYi.app" "$applications/$launcher_name"
registry="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
"$registry" -f "$destination"
swift scripts/register.swift "$destination"
"$registry" -f "$applications/$launcher_name"
open "$applications/$launcher_name"
printf 'Files installed: %s\nIf GuYi Input Method is missing or gray, open System Settings > Keyboard > Text Input > Edit > + > Simplified Chinese, add GuYi Input Method, and click Done. Registration alone does not verify activation.\n' "$destination"
printf 'If GuYi works in a newly launched application but not an existing process, save your work and reopen only the affected application when safe. This installer does not quit your applications or restart macOS.\n'
