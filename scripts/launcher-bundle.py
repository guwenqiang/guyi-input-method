from pathlib import Path
import plistlib
import shutil
import subprocess
import os

root = Path(__file__).resolve().parent.parent
contents = root / "dist/Launcher/GuYi.app/Contents"
(contents / "MacOS").mkdir(parents=True, exist_ok=True)
resources = contents / "Resources"
resources.mkdir(exist_ok=True)
shutil.copy2(root / ".build/release/guyi-launcher", contents / "MacOS/GuYi")
shutil.copy2(root / "dist/.build.noindex/Guyi.app/Contents/Resources/Guyi.icns", resources / "Guyi.icns")
for localization in (root / "Resources").glob("*.lproj"):
    shutil.copytree(localization, resources / localization.name, dirs_exist_ok=True)
with (root / "dist/.build.noindex/Guyi.app/Contents/Info.plist").open("rb") as source:
    backend_info = plistlib.load(source)
info = {
    "CFBundleIdentifier": "app.guyi.launcher",
    "CFBundleInfoDictionaryVersion": "6.0",
    "CFBundleSupportedPlatforms": ["MacOSX"],
    "CFBundleName": "GuYi输入法",
    "CFBundleDisplayName": "GuYi输入法",
    "CFBundleExecutable": "GuYi",
    "CFBundlePackageType": "APPL",
    "CFBundleIconFile": "Guyi.icns",
    "CFBundleVersion": backend_info["CFBundleVersion"],
    "CFBundleShortVersionString": backend_info["CFBundleShortVersionString"],
    "LSHasLocalizedDisplayName": True,
    "CFBundleDevelopmentRegion": "zh-Hans",
    "LSMinimumSystemVersion": "26.0",
    "NSPrincipalClass": "NSApplication",
}
with (contents / "Info.plist").open("wb") as output:
    plistlib.dump(info, output)
subprocess.run(["bash", str(root / "scripts/sign-app.sh"), str(contents.parent)], check=True)
