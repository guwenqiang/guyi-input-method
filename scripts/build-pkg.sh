#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
backend=dist/.build.noindex/Guyi.app
launcher=dist/Launcher/GuYi.app
codesign --verify --deep --strict "$backend"
codesign --verify --deep --strict "$launcher"
python3 scripts/help.py >/dev/null
diff -qr .build/help "$backend/Contents/Resources/Help" >/dev/null || {
    echo 'Bundled help is stale. Run scripts/build.sh before packaging.' >&2
    exit 1
}
stage="$PWD/dist/.pkg-staging.noindex"
rm -rf "$stage"
mkdir -p "$stage/root/Library/Input Methods" "$stage/root/Applications" "$stage/scripts" "$stage/resources"
ditto --norsrc --noextattr "$backend" "$stage/root/Library/Input Methods/GuYi输入法.app"
ditto --norsrc --noextattr "$launcher" "$stage/root/Applications/GuYi输入法.app"
cp scripts/pkg/preinstall scripts/pkg/postinstall "$stage/scripts/"
chmod 755 "$stage/scripts/"*
python3 - "$stage" <<'PY'
from pathlib import Path
import plistlib
import sys
stage = Path(sys.argv[1])
components = [{"RootRelativeBundlePath": path, "BundleIsRelocatable": False,
               "BundleIsVersionChecked": True, "BundleHasStrictIdentifier": True,
               "BundleOverwriteAction": "upgrade"}
              for path in ("Library/Input Methods/GuYi输入法.app", "Applications/GuYi输入法.app")]
with (stage / "components.plist").open("wb") as output:
    plistlib.dump(components, output)
translations = {
    "zh_CN": ("安装 GuYi输入法", "中文输入、实时翻译与截图工具。升级将保留个人配置和词库。"),
    "en": ("Install GuYi Input Method", "Chinese input, live translation and screenshot tools. Updates preserve your settings and dictionaries."),
    "id": ("Instal GuYi Input Method", "Input Mandarin, terjemahan langsung, dan alat tangkapan layar. Pembaruan mempertahankan pengaturan dan kamus Anda.")
}
for language, (title, welcome) in translations.items():
    folder = stage / "resources" / (language + ".lproj")
    folder.mkdir()
    (folder / "welcome.html").write_text('<!doctype html><meta charset="utf-8"><style>body{font:14px -apple-system;padding:18px;line-height:1.6}h1{font-size:23px}</style><h1>' + title + '</h1><p>' + welcome + '</p>', encoding="utf-8")

PY
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$backend/Contents/Info.plist")
pkgbuild --root "$stage/root" --component-plist "$stage/components.plist" --scripts "$stage/scripts" --identifier app.guyi.installer --version "$version" --install-location / "$stage/GuYi-component.pkg"
sign_flags=()
if test -n "${GUYI_INSTALLER_IDENTITY:-}"; then
    case "$GUYI_INSTALLER_IDENTITY" in 'Developer ID Installer:'*) ;; *) echo 'Installer signing requires Developer ID Installer.' >&2; exit 1 ;; esac
    sign_flags=(--sign "$GUYI_INSTALLER_IDENTITY" --timestamp)
elif test "${GUYI_RELEASE_BUILD:-0}" = 1; then
    echo 'Release packaging requires GUYI_INSTALLER_IDENTITY.' >&2
    exit 1
fi
productbuild --distribution scripts/pkg/distribution.xml --resources "$stage/resources" --package-path "$stage" ${sign_flags[@]+"${sign_flags[@]}"} dist/GuYi-Input-Method-macOS-arm64.pkg
