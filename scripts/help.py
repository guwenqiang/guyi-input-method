from pathlib import Path
import html
import re

ROOT = Path(__file__).resolve().parent.parent
LANGUAGES = {"zh-Hans": "简体中文", "en": "English", "id": "Bahasa Indonesia", "ja": "日本語", "ko": "한국어"}


def inline(value):
    value = html.escape(value)
    value = re.sub(r"`([^`]+)`", r"<code>\1</code>", value)
    value = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", value)
    return re.sub(r"\[([^\]]+)\]\((zh-Hans|en|id|ja|ko)\.md\)", r'<a href="\2.html">\1</a>', value)


def generate():
    destination = ROOT / ".build/help"
    destination.mkdir(parents=True, exist_ok=True)
    for language in LANGUAGES:
        source = (ROOT / "docs/help" / (language + ".md")).read_text()
        blocks = []
        navigation = []
        for paragraph in source.strip().split("\n\n"):
            if paragraph.startswith("# "):
                blocks.append("<h1>" + inline(paragraph[2:]) + "</h1>")
            elif paragraph.startswith("## "):
                heading = paragraph[3:]
                anchor = "section-" + str(len(navigation) + 1)
                navigation.append(f'<li><a href="#{anchor}">{inline(heading)}</a></li>')
                blocks.append(f'<h2 id="{anchor}">{inline(heading)}</h2>')
            else:
                blocks.append("<p>" + inline(paragraph) + "</p>")
        title = source.splitlines()[0][2:]
        page = f'''<!doctype html>
<html lang="{language}"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>{html.escape(title)}</title><style>
:root{{color-scheme:light dark;font-family:system-ui,-apple-system,sans-serif;line-height:1.75}}
body{{max-width:880px;margin:48px auto;padding:0 24px}}h1{{line-height:1.2}}h2{{margin-top:2.5em;scroll-margin-top:20px}}
nav{{padding:16px 24px;border:1px solid #8886;border-radius:12px}}nav ul{{margin:0;padding-left:20px}}
a{{color:light-dark(#1456aa,#92c5ff)}}code{{overflow-wrap:anywhere;background:#8882;padding:2px 5px;border-radius:4px}}
p{{overflow-wrap:anywhere}}@media print{{nav{{display:none}}body{{margin:0;max-width:none}}}}
</style></head><body>{blocks[0]}{blocks[1]}<nav aria-label="Contents"><ul>{''.join(navigation)}</ul></nav>{''.join(blocks[2:])}</body></html>'''
        (destination / (language + ".html")).write_text(page)
    links = "".join(
        f'<a href="Help/{language}.html">{html.escape(label)}</a>'
        for language, label in LANGUAGES.items()
    )
    guide = f'''<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>GuYi Help</title><style>
:root{{color-scheme:light dark;font-family:system-ui,-apple-system,sans-serif;line-height:1.7}}
body{{max-width:680px;margin:8vh auto;padding:0 24px}}h1{{font-size:28px}}
a{{display:block;margin:12px 0;color:light-dark(#1456aa,#92c5ff)}}
</style></head><body><h1>GuYi</h1>{links}</body></html>'''
    (destination.parent / "User Guide.html").write_text(guide)
    return destination


if __name__ == "__main__":
    print(generate())
