import Foundation
import GuyiCore

struct DelayedPrivacyFixture: Translating {
    func translate(_ text: String, settings: TranslationSettings, apiKey: String) async throws -> Translation {
        try? await Task.sleep(nanoseconds: 400_000_000)
        return Translation(source: .zh, zh: text, en: "late", id: "lambat", note: "")
    }
}
struct SlowValidTranslationFixture: Translating {
    func translate(_ text: String, settings: TranslationSettings, apiKey: String) async throws -> Translation {
        try await Task.sleep(for: .milliseconds(8_500))
        return Translation(source: .zh, zh: text, en: "Delayed result", id: "", note: "")
    }
}
@MainActor func runPrivacyRegressionTests() async throws {
    try check(ShortcutMessages.language(preference: "system", systemLanguages: ["fr-FR"]) == "fr", "Shortcut feedback follows French system language")
    try check(ShortcutMessages.language(preference: "system", systemLanguages: ["ja-JP"]) == "ja", "Shortcut feedback follows Japanese system language")
    try check(ShortcutMessages.language(preference: "system", systemLanguages: ["zh-Hant-TW"]) == "zh-Hant", "Shortcut feedback preserves Traditional Chinese")
    try check(ShortcutMessages.language(preference: "en", systemLanguages: ["zh-Hans-CN"]) == "en", "Explicit interface language also applies to shortcut feedback")
    let fixture = "demo-X7!q9"
    for types in [["org.nspasteboard.ConcealedType"], ["org.nspasteboard.TransientType"], ["com.agilebits.onepassword"]] {
        try check(SensitiveContentPolicy.blocksClipboard(types: types, source: nil, foreground: nil), "Confidential clipboard metadata blocks reading")
    }
    try check(SensitiveContentPolicy.blocksClipboard(types: [], source: "com.1password.1password", foreground: "com.apple.TextEdit"), "Password manager clipboard stays protected after application switch")
    try check(!SensitiveContentPolicy.blocksClipboard(types: ["public.utf8-plain-text"], source: "com.apple.TextEdit", foreground: "com.apple.TextEdit"), "Ordinary clipboard text remains eligible")
    for text in [fixture, "-----BEGIN PRIVATE KEY-----\nsynthetic\n-----END PRIVATE KEY-----", "password=synthetic-example", "YWJjZGVmZ2hpamtsbW5vcHFyc3R1dnd4eXo="] {
        try check(SensitiveContentPolicy.resemblesSecret(text), "Synthetic secret or encoded payload is rejected")
    }
    for text in ["Documents", "Please confirm order AB-102.", "3,444.50", "1.2", "Please reset my password."] {
        try check(!SensitiveContentPolicy.resemblesSecret(text), "Normal prose and numeric input is preserved")
    }
    let cache = TranslationCache()
    let settings = TranslationSettings()
    let key = TranslationCache.key(text: fixture, settings: settings)
    cache.put(Translation(source: .zh, zh: "", en: "stale synthetic result", id: "hasil", note: ""), key: key, languages: [.en, .id])
    let session = TranslationSession(cache: cache)
    session.update(text: fixture, composing: false, settings: settings, apiKey: "fixture-key", immediate: true)
    await session.waitForCurrentRequest()
    try check(!session.busy && session.result == nil && session.currentText.isEmpty, "Sensitive text cannot reuse cached results or start a request")
    do { _ = try OpenAITranslator().request(fixture, settings: settings, apiKey: "fixture-key"); throw Failure.check("Secret request accepted") }
    catch TranslationError.sensitiveContent { print("PASS · Secret rejected before constructing network payload") }
    var shortDeadline = settings
    shortDeadline.timeoutSeconds = 0.05
    let timeoutCache = TranslationCache()
    let waiting = TranslationSession(translator: DelayedPrivacyFixture(), cache: timeoutCache)
    waiting.update(text: "ordinary uncached fixture", composing: false, settings: shortDeadline, apiKey: "fixture-key", immediate: true)
    try await Task.sleep(nanoseconds: 150_000_000)
    try check(!waiting.busy && waiting.result == nil && timeoutCache.entryCount == 0, "Deadline stops waiting and late response never enters cache")
    var slowDeadline = settings
    slowDeadline.source = .zh
    slowDeadline.enabledLanguages = [.en]
    slowDeadline.timeoutSeconds = 20
    let slow = TranslationSession(translator: SlowValidTranslationFixture(), cache: TranslationCache())
    slow.update(text: "Slow valid sentence", composing: false, settings: slowDeadline, apiKey: "fixture-key", immediate: true)
    let noticeDeadline = Date().addingTimeInterval(10)
    while slow.status != Localizer.text("翻译仍在处理…"), Date() < noticeDeadline {
        try await Task.sleep(for: .milliseconds(50))
    }
    try check(slow.busy && slow.status == Localizer.text("翻译仍在处理…"),
              "No preview after eight seconds informs the user without discarding the request")
    await slow.waitForCurrentRequest()
    try check(slow.result?.en == "Delayed result" && !slow.busy,
              "A valid response after eight seconds remains usable before the configured deadline")
    var fast = settings
    fast.model = "gpt-6"
    let request = try OpenAITranslator().request("ordinary fixture", settings: fast, apiKey: "fixture-key")
    let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
    try check((body["reasoning"] as? [String: String])?["effort"] == "low", "Live translation bounds reasoning without changing model")
    fast.model = "custom-provider-model"
    let custom = try OpenAITranslator().request("ordinary fixture", settings: fast, apiKey: "fixture-key")
    let customBody = try JSONSerialization.jsonObject(with: custom.httpBody!) as! [String: Any]
    try check(customBody["reasoning"] == nil, "Unknown provider model does not receive unsupported reasoning option")
    try check(LiteralTokenPolicy.begins(raw: "google", selected: "google", precedingLatin: "", punctuation: "."), "English domain prefix keeps a literal dot")
    try check(LiteralTokenPolicy.begins(raw: "www", selected: "万万", precedingLatin: "", punctuation: "."), "Explicit www prefix takes priority over pinyin")
    try check(LiteralTokenPolicy.begins(raw: "guwen", selected: "古文", precedingLatin: "", punctuation: "@"), "Email marker preserves raw Latin username")
    try check(LiteralTokenPolicy.begins(raw: "https", selected: "", precedingLatin: "", punctuation: ":"), "Protocol colon begins literal address input")
    try check(!LiteralTokenPolicy.begins(raw: "nihao", selected: "你好", precedingLatin: "", punctuation: "."), "Ordinary pinyin still ends with Chinese punctuation")
    try check(!LiteralTokenPolicy.begins(raw: "google", selected: "谷歌", precedingLatin: "", punctuation: "."), "Explicit Chinese candidate selection is respected")
    try check(LiteralTokenPolicy.continues("com/path?q=5&n=1") && !LiteralTokenPolicy.continues(" ") && !LiteralTokenPolicy.continues("，"), "Address continuation stops at natural boundaries")
    for word in ["ok", "hello", "thanks", "github", "OK"] { try check(MixedInputCandidates.preferredEnglish(word) == word, "Common English has a direct first candidate") }
    try check(MixedInputCandidates.translationSource(for: "work", inputLanguage: .zh) == .en,
              "English first candidate in Chinese input requests translations from English")
    try check(MixedInputCandidates.translationSource(for: "guyi", inputLanguage: .zh) == .zh &&
              MixedInputCandidates.translationSource(for: "中文 work", inputLanguage: .zh) == .zh,
              "Pinyin and mixed composition keep the Chinese translation source")
    for code in ["nihao", "shi", "guyi", "an", "wo", "can", "men", "randomunknownvalue"] { try check(MixedInputCandidates.preferredEnglish(code) == nil, "Pinyin and unknown tokens are not forced to English") }
}
