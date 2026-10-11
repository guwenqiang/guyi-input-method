import plistlib
import subprocess
import tempfile
import xml.etree.ElementTree as ET
from pathlib import Path

root = Path(__file__).resolve().parent.parent
package = root / "dist/GuYi-Input-Method-macOS-arm64.pkg"
expected = {"Applications/GuYi输入法.app": "app.guyi.launcher",
            "Library/Input Methods/GuYi输入法.app": "app.guyi.inputmethod.Guyi"}
with tempfile.TemporaryDirectory(prefix="guyi-pkg-check-") as directory:
    expanded = Path(directory) / "expanded"
    subprocess.run(["pkgutil", "--expand-full", str(package), str(expanded)], check=True)
    distribution = ET.parse(expanded / "Distribution").getroot()
    assert distribution.find("conclusion") is None, "Use macOS Installer default completion page"
    assert distribution.find("domains").get("enable_localSystem") == "true"
    assert distribution.find("domains").get("enable_currentUserHome") == "false"
    assert distribution.find("options").get("hostArchitectures") == "arm64"
    assert distribution.find("volume-check/allowed-os-versions/os-version").get("min") == "26.0"
    component = expanded / "GuYi-component.pkg"
    metadata = ET.parse(component / "PackageInfo").getroot()
    assert metadata.get("identifier") == "app.guyi.installer"
    assert metadata.get("install-location") == "/"
    for bundle in metadata.findall("bundle"):
        path = Path(bundle.get("path")).as_posix()
        assert path in expected
        assert bundle.get("id") == expected[path]
    assert {item.get("id") for item in metadata.findall("upgrade-bundle/bundle")} == set(expected.values())
    assert not list(metadata.find("relocate"))
    payload = component / "Payload"
    assert {path.relative_to(payload).as_posix() for path in payload.rglob("*.app")} == set(expected)
    expected_package_version = None
    for path, identifier in expected.items():
        app = payload / path
        with (app / "Contents/Info.plist").open("rb") as stream:
            info = plistlib.load(stream)
        assert info["CFBundleIdentifier"] == identifier
        if identifier == "app.guyi.inputmethod.Guyi":
            expected_package_version = f'{info["CFBundleShortVersionString"]}.{info["CFBundleVersion"]}'
            assert "TICapsLockLanguageSwitchCapable" not in info
            modes = info["ComponentInputModeDict"]["tsInputModeListKey"]
            assert all("TICapsLockLanguageSwitchCapable" not in mode for mode in modes.values())
            assert info["tsInputMethodCharacterRepertoireKey"] == ["Latn", "Hans", "Hira", "Kana", "Hang"]
            assert "TISIntendedLanguage" not in info
            assert all("TISIntendedLanguage" not in mode and
                       "tsInputModeCharacterRepertoireKey" not in mode for mode in modes.values())
            symbols = subprocess.check_output(["nm", "-u", str(app / "Contents/MacOS/guyi")], text=True)
            assert "_TISDisableInputSource" not in symbols, "Upgrades must not disable existing input sources"
            assert "_TISSelectInputSource" not in symbols, "Runtime must not override the user's input-source selection"
        subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
    assert metadata.get("version") == expected_package_version, "Package version must advance for same-app-version hotfixes"
    for path in payload.rglob("*"):
        assert path.name not in {"credentials.json", "Install GuYi.command"}
        assert not path.is_symlink()
    for name in ["preinstall", "postinstall"]:
        subprocess.run(["bash", "-n", str(component / "Scripts" / name)], check=True)
    components = plistlib.loads((root / "dist/.pkg-staging.noindex/components.plist").read_bytes())
    assert len(components) == 2
    assert all(row["BundleOverwriteAction"] == "upgrade" and not row["BundleIsRelocatable"]
               and row["BundleHasStrictIdentifier"] for row in components)
    for language in ["en", "zh-Hans", "id", "ja", "ko"]:
        for name in ["welcome.html"]:
            assert (expanded / "Resources" / (language + ".lproj") / name).is_file()
print("PASS · Native Installer package: fixed destinations, atomic bundle upgrades, signed apps, five languages, no user data or Terminal installer")
