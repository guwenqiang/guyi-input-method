# GuYi Input Method

![GuYi logo](../assets/guyi-logo.png)

[简体中文](../README.md) · [English](README.en.md) · [Bahasa Indonesia](README.id.md)

**Write across languages without leaving the text field.** GuYi is a native macOS input method (IME) for Apple Silicon/macOS 26. Rime handles local Chinese Pinyin; your chosen AI API returns translations near the caret for explicit insertion, copying or speech. Select text in another app to translate it nearby. Optional learning cards explain vocabulary, IPA, grammar and examples.

It is designed for students, multilingual teams, support staff and anyone who alternates between Chinese, English and Indonesian. Short composition stays quick for everyday replies; a customizable shortcut enables whole-sentence composition when needed.

> Development preview. Keep a system input source available. Cross-app selection, Caps Lock source switching and cloud latency still have acceptance gaps. Screenshot and scrolling capture are not offered in this build. The current locally signed DMG is neither Developer ID signed nor notarized; installation alone does not prove that an app works in your target editor.

## What it changes

| Task | Typical workflow | With GuYi |
| --- | --- | --- |
| Reply in another language | Write, switch to a translator, copy, paste | Preview and choose a translation at the caret |
| Understand a message | Copy and switch apps | Select text and read its translation nearby |
| Learn a phrase | Search for pronunciation, words and grammar separately | Open an optional learning card and listen |

Translation accuracy depends on the configured model and context. Review important output; AI translation and IPA are not guaranteed to outperform dedicated language tools.

## Features

- Local Rime Pinyin, horizontal candidates, personal phrase learning, common English candidates and emoji suggestions. Context-aware numbers, decimal points, grouped numbers and web addresses.
- Translation previews with explicit insertion; short and whole-sentence modes. Fourteen independently selectable target languages and Chinese, English and Indonesian interfaces.
- Exact arithmetic such as `5/5=` → `1`; invalid or overflowing expressions never get an invented answer.
- Selected-text translation with remembered target languages, copying a translation, speaking the original or translation, and “Learn how to use it.” Links, number-only selections and likely credentials/IDs are filtered.
- An optional precise-selection compatibility path for apps that do not expose selected text: after an explicit selection or Select All, it briefly copies the selection and restores the clipboard. It is enabled by default and can be disabled. Clipboard history apps may still record the temporary change. “Automatically copy selected original” is a separate setting, off by default.
- Ten reusable text/image/file slots and bounded local memory/SQLite translation caches.

## Install

1. Download the latest accepted DMG from the GitHub **Releases** tab. Open it and double-click `GuYi-Input-Method.pkg`; finish in macOS Installer.
2. Open **GuYi Input Method** from Applications. Configure and test your AI service, then save.
3. Add GuYi in **System Settings → Keyboard → Text Input → Edit**, then select it inside a real text field. Keep system ABC or another IME available.
4. The local development signature is not Apple notarization. If macOS blocks the app, do not disable system security; wait for a Developer ID/notarized build. This preview DMG is not guaranteed to install on every Mac.

Normal upgrades use the same DMG → PKG path and retain local settings, dictionaries and caches without a reboot. Package installation and input-source registration are not proof of operation in WeChat, Office or another host.

## Connect an AI model

In **Settings → Service**, select the API protocol, enter its base URL, model ID and that provider's API key, run the connection/translation test, then save.

| Protocol | Provider type | Example base URL |
| --- | --- | --- |
| Responses | OpenAI or a provider implementing compatible Responses API | `https://api.openai.com/v1` |
| Chat Completions | A provider implementing OpenAI-compatible Chat Completions | Its `/v1` base URL |
| Claude / Anthropic Messages | A provider implementing Messages API | Its documented base URL |

“OpenAI-compatible” **does not mean OpenAI only**. GuYi can use another provider that implements the selected protocol, authentication and required structured output; not every claimed compatible model will work. Volcengine Ark/Doubao cloud APIs can use their supported Responses or Chat Completions route with `https://ark.cn-beijing.volces.com/api/v3`, an enabled model or `ep-` endpoint ID, and a separate Ark API key. GuYi does not access the Doubao desktop login. GuYi remembers the latest configuration per provider; saving a new configuration for the same provider replaces that provider's previous one. A ChatGPT subscription is not API credit.

Keys are stored in an owner-restricted local **plaintext** file. Translation caches are not encrypted. Input, selection and learning requests send relevant text to your configured service; prefer trusted HTTPS endpoints. Never post keys, work chats or private screenshots in public issues.

## Everyday controls

| Action | Default |
| --- | --- |
| Chinese candidates | Pinyin, then Space or `1–5`; `=`/`-` page candidates while composing |
| Source language | `Option+0` cycles Chinese/English/Indonesian |
| Whole-sentence mode | `Control+Option+Return` toggles |
| Translation insertion | `Option+1/2/3` for Chinese/English/Indonesian; assign other targets in Shortcuts |
| Reusable content | `Control+Option+digit` copies; add `Shift` to request paste |
| Selected text | Drag or double-click; Select All with `Command+A` in supported editors |

Feature shortcuts can be changed or disabled in Settings. A selection preview never sends a chat message; speech never inserts text.

Full instructions: [English guide](help/en.md) · [中文帮助](help/zh-Hans.md) · [Panduan Indonesia](help/id.md). The app includes the same offline help.

## Source and license

Built with Swift, InputMethodKit, AppKit/SwiftUI, Rime and SQLite. The current build expects Apple Silicon/macOS 26, a Swift toolchain and Homebrew `librime`. Rime Vendor directories are pinned submodules: clone with `git clone --recurse-submodules`, or run `git submodule update --init --recursive` in an existing checkout:

```sh
bash scripts/build.sh
bash scripts/test.sh
bash scripts/package.sh
```

GuYi-owned source is [MIT licensed](../LICENSE); bundled dependencies and dictionaries retain their own licenses in [third-party notices](../THIRD_PARTY_NOTICES.md). See [contributing](../CONTRIBUTING.md) and [security](../SECURITY.md).
