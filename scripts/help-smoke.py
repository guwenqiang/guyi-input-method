from html.parser import HTMLParser
from pathlib import Path
import re
from help import generate, LANGUAGES, ROOT


class Links(HTMLParser):
    def __init__(self):
        super().__init__()
        self.links = []
        self.ids = set()
        self.headings = 0

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag == "a":
            self.links.append(attrs["href"])
        if "id" in attrs:
            self.ids.add(attrs["id"])
        if tag == "h2":
            self.headings += 1


directory = generate()
guide = Links()
guide.feed((directory.parent / "User Guide.html").read_text())
assert set(guide.links) == {"Help/" + language + ".html" for language in LANGUAGES}
for language in LANGUAGES:
    page = directory / (language + ".html")
    parser = Links()
    parser.feed(page.read_text())
    expected = (ROOT / "docs/help" / (language + ".md")).read_text().count("\n## ")
    assert parser.headings == expected and expected > 0, language
    assert len(parser.ids) == expected, language
    for link in parser.links:
        assert link[1:] in parser.ids if link.startswith("#") else (directory / link).is_file(), link
    assert all(other + ".html" in parser.links for other in LANGUAGES)
    print("PASS · Offline help sections, anchors and language links:", language)
for path in [ROOT / "README.md", ROOT / "docs/README.en.md", ROOT / "docs/README.id.md"]:
    for target in re.findall(r"\]\(([^)]+)\)", path.read_text()):
        assert (path.parent / target.split("#")[0]).exists(), (path, target)
    print("PASS · README local links:", path.name)
for target in re.findall(r"\]\(([^)]+)\)", (ROOT / "docs/使用说明.md").read_text()):
    assert (ROOT / "docs" / target).is_file(), target
print("PASS · GitHub help index and offline guide links")
