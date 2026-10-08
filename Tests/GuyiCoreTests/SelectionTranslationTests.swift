import Foundation
import GuyiCore
@MainActor func runSelectionTranslationTests() throws {
    var settings = TranslationSettings()
    try check(settings.copySelectionAutomatically != true, "Selecting text never opts into clipboard mutation by default")
    try check(settings.preciseSelectionCompatibility != false, "Exact selection compatibility is enabled unless explicitly disabled")
    func triggers(_ text: String) -> Bool { SelectionTranslationPolicy.shouldTranslate(text, settings: settings, interfaceLanguage: "zh-Hans") }
    for text in ["3,444.50", "5/5=1", "１２３。！？", "😂👍🏽", " \n", "123 + 456 % €", "http://127.0.0.1:8767", "https://example.com/docs", "你好，今天是2026年。"] {
        try check(!triggers(text), "Selection filter skips nonlinguistic or familiar selection: \(text.debugDescription)")
    }
    for text in ["about:blank", "www.example.com/docs", "person@example.com", "/Users/example/My File.txt", "550e8400-e29b-41d4-a716-446655440000", "aabbccddeeff00112233445566778899", "ERR_CONNECTION_RESET", "EPSQPAZN7", "DEVICE-1024", "aB7fK9xP2mQ8", "2026-10-08T09:30:00Z", "{\"status\":\"ready\"}", "const total = 5 / 5;"] {
        try check(!triggers(text), "Structured selection is not automatically translated: \(text)")
    }
    try check(triggers("Device EPSQPAZN7 is ready."), "Prose containing an opaque identifier remains translatable")
    try check(triggers("Please enable 5G."), "Short technical terms inside sentences are not discarded")
    try check(triggers("Documents"), "A normal standalone word still translates")
    try check(triggers("Order AB-102 is ready."), "A sentence containing an identifier still translates")
    try check(triggers("Please review https://example.com/docs tomorrow."), "Text containing a link still translates as a whole")
    try check(triggers("Hello, please review the document."), "English selection triggers for Chinese interface")
    try check(triggers("这是中文介绍，请 review this document，明天处理。"), "Minority English fragment triggers whole mixed selection")
    try check(triggers("日本語のテキストです"), "Japanese kana is not mistaken for Chinese")
    try check(triggers("한국어 텍스트"), "Korean selection triggers")
    settings.skipSameLanguageSelection = false
    try check(triggers("你好"), "Same language filter can be disabled")
    try check(!triggers("3,444 + 5 😂"), "Disabling same-language filter still excludes numbers and symbols")
    settings.skipSameLanguageSelection = true
    settings.selectionFamiliarLanguage = "en"
    try check(!triggers("Please review the document before tomorrow."), "Familiar language can differ from interface language")
    try check(triggers("Please review this 中文 document."), "Chinese fragment triggers in English context")
    let normalKey = TranslationCache.key(text: "Please review 中文", settings: settings)
    settings.translateWholeSelection = true
    try check(normalKey != TranslationCache.key(text: "Please review 中文", settings: settings), "Whole-selection translation does not reuse source-preserving cache")
    let request = try OpenAITranslator().request("Please review 中文", settings: settings, apiKey: "fixture-only")
    let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
    try check((body["instructions"] as? String)?.contains("Translate the ENTIRE selection") == true, "Mixed selection requests complete translation into every target")
    let cache = TranslationCache()
    let mixed = Translation(source: .zh, zh: "请审阅中文。", en: "Please review Chinese.", id: "", note: "")
    let mixedKey = TranslationCache.key(text: "请 review 中文。", settings: settings)
    cache.put(mixed, key: mixedKey, languages: [.zh, .en], includeSource: true)
    try check(cache.get(mixedKey)?.zh == mixed.zh, "Mixed-language cache preserves translated dominant-language target")
    settings.copySelectionAutomatically = true
    let roundtrip = try JSONDecoder().decode(TranslationSettings.self, from: JSONEncoder().encode(settings))
    try check(roundtrip.copySelectionAutomatically == true, "Explicit selection-to-clipboard preference survives storage")
    try check(roundtrip.selectionFamiliarLanguage == "en" && roundtrip.skipSameLanguageSelection == true, "Selection trigger preferences survive storage")
}
