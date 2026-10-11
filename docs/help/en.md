# GuYi Input Method user guide

[简体中文](zh-Hans.md) · [English](en.md) · [Bahasa Indonesia](id.md) · [日本語](ja.md) · [한국어](ko.md)

## 1. Install and update

GuYi currently targets Apple Silicon/macOS 26. Download the DMG for the version you need from GitHub Releases, open it and double-click `GuYi-Input-Method.pkg`. Complete macOS Installer approval. The installer attempts to enable GuYi; choose it from the menu-bar input menu while a text field is active. If GuYi is absent, add it under **System Settings → Keyboard → Text Input → Edit**. For AI translation, open GuYi Input Method from Applications and configure a model service; Pinyin input does not need an API key.

Updates use the same DMG → PKG workflow and normally preserve your provider settings, dictionaries and caches. If macOS says it cannot verify the developer on first open, confirm the file came from this repository. After attempting to open it, use **System Settings → Privacy & Security → Open Anyway** and follow the prompts to allow this file only.

## 2. Configure an AI service

On **Settings → Service**, choose an API protocol, enter its **base URL, model ID and the provider's API key**, run the connection test, then save. The available-model list reflects the provider's catalog; it does not guarantee that every model supports GuYi's structured translation request.

You can also choose **Import local API configuration**. Only after you click it, GuYi reads an explicit API-key login and the selected Responses endpoint/model from Codex, or `ANTHROPIC_API_KEY`, endpoint and model from Claude Code's `~/.claude/settings.json`. Review the endpoint and model after import; an HTTP endpoint shows an unencrypted-connection warning. Import changes only the unsaved form, makes no network request, and does not replace the active service until you test and save. ChatGPT/Claude subscriptions and OAuth sign-ins are not model API keys.

GuYi supports OpenAI Responses, OpenAI-compatible Chat Completions and Claude/Anthropic Messages. “OpenAI-compatible” is **not limited to OpenAI**: another provider can work when it implements the selected endpoint, authentication and required output. For OpenAI Responses, an example base URL is `https://api.openai.com/v1`; for third-party Chat Completions use that provider's documented `/v1` base URL. Do not append an operation path such as `/responses` twice. If a gateway rejects JSON Schema output, enable **Compatible output (GuYi validates JSON)** for that service, test, and save. GuYi still validates complete translation fields; this mode cannot fix an invalid key or unavailable model.

Doubao/Volcengine Ark is a **cloud API**, not the Doubao desktop login. Use its supported Responses or Chat Completions route, `https://ark.cn-beijing.volces.com/api/v3`, an enabled model ID or `ep-` endpoint ID, and a separate Ark API key. To add a service, click **New**, enter its name, protocol, endpoint, model and key, test, then save. Multiple named services can use the same protocol and endpoint and be selected by name in **Configured services**. Editing an existing service updates only that entry; older profiles receive editable default names. Switching a form without saving does not change the active service. A ChatGPT subscription is not an API key or API credit.

Prefer a trusted HTTPS endpoint. HTTP does not encrypt keys or source text. The API key is stored in an owner-restricted local **plaintext** file, not encrypted in Keychain. Enabled translation sends relevant input or selected text to your configured provider.

## 3. Pinyin, candidates and exact arithmetic

In Chinese mode type `nihao`, then use Space or `1–5` for a visible candidate. The candidate row fits 1–5 items according to text width. Left/Right changes the selection; `=`/`-` pages candidates while Pinyin is composing. Page Up/Page Down and mouse selection also work. GuYi learns repeatedly chosen phrases locally; adjacent single-character selections can form a phrase after repeated use, while single characters are not added as phrase candidates. Curated emoji suggestions work in Chinese, English, Indonesian, Japanese romaji and Korean input; selecting an emoji is explicit. Pinyin hints appear only in Chinese input.

Without active composition, spaces, digits and punctuation insert directly. Decimal points, time colons and grouped-number commas stay literal, for example `1.2`, `09:30`, `3,444.50`; web/email addresses stay literal as applicable. With pending Pinyin, Return can insert the raw letters without adding a newline. With no composition, Return belongs to the host and may send a chat message or execute a terminal command.

Continuously type `5/5=` in an empty field or after a space. The compact calculator popup shows the exact result `1`; Return or clicking the result inserts it without a newline. Arithmetic, parentheses, decimals, grouped numbers and integer powers (`^`) are supported. Repeating decimals return exact fractions. Invalid expressions, division by zero and overflow never receive a guessed result. Limits are 256 characters and 32 nesting levels.

## 4. Input translation and sentence mode

The translation panel appears near the caret. Source text and enabled targets have separate rows; choose a translation explicitly to insert it. `Control+Option+Return` toggles sentence mode; long content scrolls inside the panel. Click a language heading to fold its translation. Input candidates and selected-text translation remember folds separately, and a folded language is not requested from the model. Languages disabled in Settings are hidden. Emoji remain available through Pinyin candidates, the input menu, or a customizable shortcut. In Chinese sentence mode, the first Return puts pending raw Pinyin (such as `guyi`) into GuYi's source draft; the second inserts the sentence. If a Chinese candidate is already chosen, one Return inserts it. English sentence mode also needs one Return. No newline is added. Short phrase mode still inserts raw Pinyin with one Return. Practise in a draft field before using Return in a chat app.

Defaults: `Option+0` cycles Chinese Pinyin, English, Indonesian Latin input, Japanese romaji and Korean 2-Set input; `Control+Option+J/K` directly selects Japanese/Korean. Japanese currently converts romaji to kana without a Kanji dictionary. Input modes are separate from translation targets. `Option+1/2/3` selects Chinese/English/Indonesian output. Set shortcuts for other targets in Settings. An unready translation shortcut shows a wait message instead of falling through to a host-app symbol. Every feature shortcut can be changed or disabled. Tab/Shift+Tab retain their host behavior; Esc cancels the current composition.

On first use, Chinese, Japanese, Korean and Indonesian system languages choose the corresponding native/English pair; other languages default to Chinese/English. A saved choice takes precedence. In supported apps, Caps Lock switches between English and the last non-English GuYi input mode. `Control+Option+L` performs the same action and can be customized or disabled in Shortcuts. GuYi does not change the system Caps Lock setting. In Chrome, Caps Lock may switch to the system ABC input source. To stay in GuYi, use the input-language button or a custom shortcut. Switching retains pending composition in the source draft without inserting it early. English is lowercase by default; use Shift with a letter for uppercase. Keep a system input source available as a fallback.

## 5. Selected-text translation and speech

When another app enables macOS Secure Keyboard Entry, GuYi still provides local input in ordinary text fields; a lock notice appears at the top of the candidate panel. Cloud translation, selection and clipboard reading, and personal phrase learning pause while it is active, then resume according to your settings.

For a stretch of copying that needs no translation, press `Control+Option+T` to pause automatic selected-text and clipboard translation; press it again to resume. The shortcut is customizable, and the GuYi menu and Input & Translation settings offer the same toggle. Pausing preserves your existing switches.

Drag-select or double-click ordinary language text to see a separate nearby translation panel. Multiple target languages can be selected and remembered. Same-language auto-translation is skipped by default; mixed-language text is translated as a complete source. Number-only text, formulas, links, obvious credentials/device IDs and file paths are filtered. Clicking away, typing or switching apps closes the preview. The speaker beside the original or a translation starts speech; click again to stop. Speech never inserts text. Translation rows have Copy buttons; the original row does not duplicate the host app's Copy command.

Some custom apps do not expose precise selected text through macOS Accessibility. **Precise selection compatibility** is on by default: only after an explicit drag, double-click or supported `Command+A`, and only when system selection reading fails, GuYi briefly copies the selection, reads it, and restores the previous clipboard. If a complete snapshot cannot be restored, it gives up rather than guessing with OCR. **Clipboard history tools may still record the temporary change.** Turn the option off under Input and Translation if that is unacceptable. “Automatically copy selected original” is a separate option, off by default; turning it on deliberately leaves the original text on the clipboard after preview.

Save-dialog filenames, ordinary single-line fields, contact search and secure fields do not trigger automatic selected-text translation. Natural-language selections in document, email and chat bodies can. App implementations vary; when neither system selection nor the guarded compatibility path gives an exact result, GuYi should not display an unverified translation.

“Translate copied text” is a separate switch. When enabled, it handles a new explicit copy, not an old clipboard item or a paste. Password managers, protected clipboard markers and likely credentials remain excluded.

## 6. Learning, cache and reusable content

The book button opens “Learn how to use it” for on-demand English/Indonesian IPA, key words, grammar, register and examples. These are AI-assisted rather than dictionary-verified. Editing the source clears the old lesson. Speech uses available macOS voices; no specific natural male/female voice is promised.

GuYi checks bounded memory and SQLite caches before the network. Retention defaults to seven days, can be set to 1–365 days, disabled or cleared, and stores only complete translations for enabled targets. Switching models or API protocols reuses translations for the same service account, source text and translation settings. Refresh uses the current model and replaces the cached translation. Different API addresses or keys do not share cache entries. Online vocabulary can update daily; failure keeps the local lexicon. Rime personal word learning is separate from the translation cache.

**Tools → Reusable Content** stores up to ten local text/image/file slots. `Control+Option+digit` copies; adding `Shift` requests paste. Multiline text and attachments in terminals are copy-only; GuYi never sends an automatic Return. Text is limited to 64 KiB and a file to 10 MiB. Slots are not encrypted; do not store passwords or API keys.

## 7. Privacy and troubleshooting

Provider credentials reside under `~/Library/Application Support/guyi/Configuration` in owner-restricted plaintext files. Dictionaries, caches and reusable content are also local to your user account; normal upgrades preserve them. Caches are not encrypted, and a hashed source index is not a guarantee of anonymity. Translation and learning send relevant text to your chosen provider under its data policy.

For API errors: 401 suggests a key issue, 403 provider permissions, 400 protocol/model/structured-output compatibility, 404 URL or model ID, 429 quota/rate limits, and timeouts a network or service issue. A model appearing in a list is not proof it works. Full cloud translations can still take seconds; a cache hit is not network latency. Report GuYi/macOS/host versions and redacted steps, never a key, password or private chat.

To uninstall, switch to another IME, remove GuYi from the system input-source list, then remove `/Applications/GuYi输入法.app` and `/Library/Input Methods/GuYi输入法.app`. Never remove the whole Input Methods directory. Delete your personal data only if you explicitly intend to.
