# GuYi Input Method

![GuYi logo](../assets/guyi-logo.png)

[简体中文](../README.md) · [English](README.en.md) · [Bahasa Indonesia](README.id.md) · [日本語](help/ja.md) · [한국어](help/ko.md)

**Write across languages without leaving the text field.** GuYi is a native macOS input method (IME) for Apple Silicon/macOS 26. Rime handles local Chinese Pinyin; your chosen AI API returns translations near the caret for explicit insertion, copying or speech. Select text in another app to translate it nearby. Optional learning cards explain vocabulary, IPA, grammar and examples.

It is designed for students, multilingual teams, support staff and anyone who communicates across languages. Its five input modes cover Chinese Pinyin, English, Indonesian, Japanese kana and Korean 2-Set; translation targets are configured separately. Short composition stays quick for everyday replies; a customizable shortcut enables whole-sentence composition when needed.

> Compatibility: Keep a system input source available. In Chrome, Caps Lock switches to system ABC; use “中 / EN” or a custom shortcut to stay in GuYi. Cross-app selection and cloud latency are still being checked.

## What it changes

| Task | Typical workflow | With GuYi |
| --- | --- | --- |
| Reply in another language | Write, switch to a translator, copy, paste | Preview and choose a translation at the caret |
| Understand a message | Copy and switch apps | Select text and read its translation nearby |
| Learn a phrase | Search for pronunciation, words and grammar separately | Open an optional learning card and listen |

Translation accuracy depends on the configured model and context. Review important output; AI translation and IPA are not guaranteed to outperform dedicated language tools.

## Features

- Local Rime Pinyin, English and Indonesian Latin input, Japanese romaji-to-kana, Korean 2-Set, horizontal candidates, Chinese phrase learning, common English candidates and emoji suggestions in all five input modes. Pinyin hints appear only in Chinese mode. Japanese input converts to kana but does not include a Kanji dictionary. Context-aware numbers, decimal points, grouped numbers and web addresses.
- Translation previews with explicit insertion; short and whole-sentence modes. Fourteen independently selectable target languages and Chinese, English, Indonesian, Japanese and Korean interfaces.
- Exact arithmetic such as `5/5=` → `1`; invalid or overflowing expressions never get an invented answer.
- Selected-text translation with remembered target languages, copying a translation, speaking the original or translation, and “Learn how to use it.” Links, number-only selections and likely credentials/IDs are filtered.
- An optional precise-selection compatibility path for apps that do not expose selected text: after an explicit selection or Select All, it briefly copies the selection and restores the clipboard. It is enabled by default and can be disabled. Clipboard history apps may still record the temporary change. “Automatically copy selected original” is a separate setting, off by default.
- Ten reusable text/image/file slots and bounded local memory/SQLite translation caches. The same service account reuses translations across model and API protocol changes; Refresh uses the current model and replaces the cached translation.

## Install

1. Download the DMG for the version you need from GitHub **Releases**. Open it and double-click `GuYi-Input-Method.pkg`; finish in macOS Installer.
2. In a text field, choose GuYi from the menu-bar input menu. If it is absent, follow [installation troubleshooting](help/en.md).
3. For AI translation, open **GuYi Input Method** from Applications, configure and test your model service, then save. Pinyin input does not need an API key.
4. If macOS blocks installation, see [installation troubleshooting](help/en.md).

Normal upgrades use the same DMG → PKG path and retain local settings, dictionaries and caches.

## Connect an AI model

In **Settings → Service**, select the API protocol, enter its base URL, model ID and that provider's API key, run the connection test, then save. If Codex or Claude Code has an explicit model API key on this Mac, **Import local API configuration** fills an unsaved draft for review and testing; subscription and OAuth sign-ins are not imported.

| Protocol | Provider type | Example base URL |
| --- | --- | --- |
| Responses | OpenAI or a provider implementing compatible Responses API | `https://api.openai.com/v1` |
| Chat Completions | A provider implementing OpenAI-compatible Chat Completions | Its `/v1` base URL |
| Claude / Anthropic Messages | A provider implementing Messages API | Its documented base URL |

“OpenAI-compatible” **does not mean OpenAI only**. GuYi can use another provider that implements the selected protocol and authentication; not every claimed compatible model will work. If a gateway rejects JSON Schema output, enable **Compatible output (GuYi validates JSON)** for that service and test before saving. Volcengine Ark/Doubao cloud APIs can use their supported Responses or Chat Completions route with `https://ark.cn-beijing.volces.com/api/v3`, an enabled model or `ep-` endpoint ID, and a separate Ark API key. GuYi does not access the Doubao desktop login. You can save multiple named services even with the same protocol and endpoint; editing an existing service updates only that entry. A ChatGPT subscription is not API credit.

Keys are stored in an owner-restricted local **plaintext** file. Translation caches are not encrypted. Input, selection and learning requests send relevant text to your configured service; prefer trusted HTTPS endpoints. Never post keys or private conversations in public issues.

## Everyday controls

| Action | Default |
| --- | --- |
| Chinese candidates | Pinyin, then Space or `1–5`; `=`/`-` page candidates while composing |
| Input language | `Option+0` cycles Chinese, English, Indonesian, Japanese and Korean; `Control+Option+J/K` selects Japanese/Korean |
| Native/English toggle | Caps Lock in supported apps; customizable `Control+Option+L` provides the same GuYi toggle. The first native choice follows the Chinese, Japanese, Korean or Indonesian system language; saved choices take precedence. |
| Whole-sentence mode | `Control+Option+Return` toggles |
| Translation insertion | `Option+1/2/3` for Chinese/English/Indonesian; assign other targets in Shortcuts |
| Reusable content | `Control+Option+digit` copies; add `Shift` to request paste |
| Selected text | Drag or double-click; Select All with `Command+A` in supported editors |

Feature shortcuts can be changed or disabled in Settings. A selection preview never sends a chat message; speech never inserts text.

Full instructions: [Guide index](使用说明.md) · [English guide](help/en.md) · [中文帮助](help/zh-Hans.md) · [Panduan Indonesia](help/id.md) · [日本語](help/ja.md) · [한국어](help/ko.md). The app includes the same offline help.

See the [release notes](../CHANGELOG.md) for changes in this version.

## Source and license

Built with Swift, InputMethodKit, AppKit/SwiftUI, Rime and SQLite. The current build expects Apple Silicon/macOS 26, a Swift toolchain and Homebrew `librime`. Rime Vendor directories are pinned submodules: clone with `git clone --recurse-submodules`, or run `git submodule update --init --recursive` in an existing checkout:

```sh
bash scripts/build.sh
bash scripts/test.sh
bash scripts/package.sh
```

GuYi-owned source is [MIT licensed](../LICENSE); bundled dependencies and dictionaries retain their own licenses in [third-party notices](../THIRD_PARTY_NOTICES.md). See [contributing](../CONTRIBUTING.md) and [security](../SECURITY.md).
