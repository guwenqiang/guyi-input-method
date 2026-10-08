#!/bin/bash
set -euo pipefail
app="$1"
identity="${GUYI_SIGNING_IDENTITY:--}"
flags=(--force --sign "$identity")
if test "${GUYI_RELEASE_BUILD:-0}" = 1; then
    flags+=(--options runtime --timestamp)
fi
if test -d "$app/Contents/Frameworks"; then
    for library in "$app/Contents/Frameworks/"*.dylib; do
        test -f "$library" || continue
        codesign "${flags[@]}" "$library"
    done
fi
codesign "${flags[@]}" "$app"
codesign --verify --deep --strict "$app"
