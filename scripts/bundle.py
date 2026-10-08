from pathlib import Path
import shutil
import subprocess
from help import generate

root = Path(__file__).resolve().parent.parent
app = root / "dist/.build.noindex/Guyi.app"
if app.exists():
    shutil.rmtree(app)
contents = app / "Contents"
binary_dir = contents / "MacOS"
resources = contents / "Resources"
frameworks = contents / "Frameworks"
for directory in (binary_dir, resources, frameworks):
    directory.mkdir(parents=True, exist_ok=True)
shutil.copy2(root / ".build/release/guyi", binary_dir / "guyi")
shutil.copy2(root / ".build/release/libGuyiCore.dylib", frameworks / "libGuyiCore.dylib")
shutil.copy2(root / "Resources/Info.plist", contents / "Info.plist")
shutil.copy2(root / "Resources/shortcut-messages.json", resources / "shortcut-messages.json")
shutil.copytree(root / "Resources/Rime", resources / "Rime", dirs_exist_ok=True)
for localization in (root / "Resources").glob("*.lproj"):
    shutil.copytree(localization, resources / localization.name)
shutil.copy2(root / "Vendor/luna-pinyin/luna_pinyin.dict.yaml", resources / "Rime")
shutil.copy2(root / "Vendor/essay/essay.txt", resources / "Rime")
shutil.copytree(Path("/opt/homebrew/share/opencc"), resources / "Rime/opencc", dirs_exist_ok=True)
licenses = resources / "Licenses"
licenses.mkdir()
shutil.copy2(root / "Vendor/luna-pinyin/LICENSE", licenses / "luna-pinyin-LGPL-3.txt")
shutil.copy2(root / "Vendor/luna-pinyin/AUTHORS", licenses / "luna-pinyin-AUTHORS.txt")
shutil.copy2(root / "Vendor/luna-pinyin/README.md", licenses / "luna-pinyin-README.md")
shutil.copy2(root / "Vendor/essay/LICENSE", licenses / "essay-LGPL-3.txt")
shutil.copy2(root / "Vendor/essay/AUTHORS", licenses / "essay-AUTHORS.txt")
shutil.copy2(root / "Vendor/GPL-3.0.txt", licenses / "GPL-3.0.txt")
shutil.copy2(root / "Vendor/essay/essay.txt", licenses / "essay-source.txt")
shutil.copytree(generate(), resources / "Help", dirs_exist_ok=True)

seen = set()


def dependencies(path):
    output = subprocess.check_output(["otool", "-L", str(path)], text=True)
    return [line.strip().split(" (", 1)[0] for line in output.splitlines()[1:]]


def bundle(path):
    for dependency in dependencies(path):
        if not dependency.startswith("/opt/homebrew/"):
            continue
        source = Path(dependency)
        target = frameworks / source.name
        if source.name not in seen:
            seen.add(source.name)
            shutil.copy2(source, target)
            target.chmod(0o755)
            subprocess.run(["install_name_tool", "-id", "@rpath/" + target.name, str(target)], check=True)
            bundle(target)
        subprocess.run(["install_name_tool", "-change", dependency, "@rpath/" + source.name, str(path)], check=True)


bundle(binary_dir / "guyi")
for formula in ("librime", "glog", "gflags", "yaml-cpp", "leveldb", "snappy", "marisa", "opencc"):
    prefix = Path("/opt/homebrew/opt") / formula
    for pattern in ("*LICENSE*", "*COPYING*", "*NOTICE*"):
        for license_file in prefix.glob(pattern):
            if license_file.is_file():
                shutil.copy2(license_file, licenses / (formula + "-" + license_file.name))
print(f"Bundled {len(seen)} libraries; no Homebrew runtime required.")
