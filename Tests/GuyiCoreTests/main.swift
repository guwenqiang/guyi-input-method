import Foundation
import CoreGraphics
import GuyiCore

enum Failure: Error { case check(String) }

func check(_ condition: @autoclosure () -> Bool, _ name: String) throws {
    guard condition() else { throw Failure.check(name) }
    print("PASS · " + name)
}

func response(text: String = "你好", status: String = "completed") throws -> Data {
    let result: [String: Any] = ["source": "zh", "zh": text, "en": "Hello", "id": "Halo", "note": ""]
    let json = String(decoding: try JSONSerialization.data(withJSONObject: result), as: UTF8.self)
    return try JSONSerialization.data(withJSONObject: ["status": status, "output": [["type": "message", "content": [["type": "output_text", "text": json]]]]])
}

actor StubTranslator: Translating {
    private(set) var calls = 0
    func translate(_ text: String, settings: TranslationSettings, apiKey: String) async throws -> Translation {
        calls += 1
        if text == "old" { try? await Task.sleep(nanoseconds: 180_000_000) }
        else { try? await Task.sleep(nanoseconds: 20_000_000) }
        return try OpenAITranslator.decode(response(text: text))
    }
}

final class MockURLProtocol: URLProtocol {
    static var status = 200
    static var data = Data()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

struct StagedTranslator: StreamingTranslating {
    func translate(_ text: String, settings: TranslationSettings, apiKey: String) async throws -> Translation {
        try OpenAITranslator.decode(response(text: text))
    }
    func stream(_ text: String, settings: TranslationSettings, apiKey: String,
                progress: @escaping @Sendable ([String: String]) async -> Void) async throws -> Translation {
        await progress(["en": "Hello", "_ready_en": "1"])
        try await Task.sleep(nanoseconds: 250_000_000)
        return try OpenAITranslator.decode(response(text: text))
    }
}

@main
struct Tests {
    @MainActor static func main() async throws {
        try check(InputSafety.allowsClientAccess(active: true, currentController: true, hasClient: true, sessionHostPID: 10, foregroundPID: 10),
                  "IMK session may access its captured foreground host without a bundle-ID match")
        try check(!InputSafety.allowsClientAccess(active: true, currentController: true, hasClient: true, sessionHostPID: 10, foregroundPID: 11),
                  "Different processes cannot share input ownership even when their bundle IDs match")
        try check(!InputSafety.allowsClientAccess(active: false, currentController: true, hasClient: true, sessionHostPID: 10, foregroundPID: 10),
                  "Deactivated input session cannot write")
        try check(!InputSafety.allowsClientAccess(active: true, currentController: false, hasClient: true, sessionHostPID: 10, foregroundPID: 10),
                  "Stale input controller cannot write")
        try check(!InputSafety.allowsClientAccess(active: true, currentController: true, hasClient: false, sessionHostPID: 10, foregroundPID: 10),
                  "Missing IMK client cannot receive input")
        try check(!InputSafety.allowsClientAccess(active: true, currentController: true, hasClient: true, sessionHostPID: nil, foregroundPID: nil),
                  "Missing host identity does not match an absent foreground app")
        try check(EmojiCandidates.matches("ha ha").contains("😂"), "Pinyin haha offers a laughing emoji")
        try check(EmojiCandidates.matches("xie xie").contains("🙏"), "Pinyin emoji matching normalizes syllable spaces")
        try check(EmojiCandidates.matches("unknownword").isEmpty, "Unmatched Pinyin does not inject unrelated emoji")
        var scrolling = ScrollStepQueue()
        scrolling.add(-950)
        var forwarded = 0, steps = 0
        while let step = scrolling.take(viewportHeight: 300) {
            try check(abs(step) <= 100, "Fast scrolling retains at least two thirds overlap")
            forwarded += Int(step); steps += 1
        }
        try check(forwarded == -950 && steps == 10, "Queued fast gesture is drained without losing distance")
        scrolling.add(-90); scrolling.add(40)
        try check(scrolling.take(viewportHeight: 300) == -50 && scrolling.take(viewportHeight: 300) == nil, "Direction reversal coalesces pending movement")
        scrolling.add(.infinity)
        try check(scrolling.take(viewportHeight: 300) == nil, "Nonfinite scroll events are ignored")
        try runSelectionTranslationTests()
        try await runPrivacyRegressionTests()
        try runShortcutTests()
        try runLearnedPhraseTests()
        try runProviderDraftTests()
        try runCalculatorTests()
        try check(InputSafety.candidatePageDirection("=", language: .zh, hasPreedit: true) == true, "Equals pages forward during Pinyin composition")
        try check(InputSafety.candidatePageDirection("-", language: .zh, hasPreedit: true) == false, "Minus pages backward during Pinyin composition")
        try check(InputSafety.candidatePageDirection("=", language: .zh, hasPreedit: false) == nil, "Equals retains calculator and literal meaning without Pinyin")
        try check(InputSafety.candidatePageDirection("-", language: .zh, hasPreedit: false) == nil, "Minus retains arithmetic meaning without Pinyin")
        try check(InputSafety.candidatePageDirection("=", language: .en, hasPreedit: true) == nil, "English equals is not a candidate shortcut")
        try check(InputSafety.candidatePageDirection("+", language: .zh, hasPreedit: true) == nil, "Shift-equals does not page candidates")
        try runProviderTests()
        var cloudSettings = TranslationSettings()
        let legacyData = try JSONEncoder().encode(cloudSettings)
        let legacySettings = try JSONDecoder().decode(TranslationSettings.self, from: legacyData)
        try check(legacySettings.effectiveAPIProtocol == .responses,
                  "Existing provider settings retain Responses protocol")
        let cloudKey = TranslationCache.key(text: "provider-isolation", settings: cloudSettings)
        cloudSettings.apiProtocol = .anthropic
        try check(TranslationCache.key(text: "provider-isolation", settings: cloudSettings) != cloudKey,
                  "Provider protocol translation caches are isolated")
        try check(Localizer.languageCode(preference: "system", systemLanguages: ["zh-Hans-CN"]) == "zh-Hans", "Chinese system UI language")
        try check(Localizer.languageCode(preference: "system", systemLanguages: ["id-ID"]) == "id", "Indonesian system UI language")
        try check(Localizer.languageCode(preference: "en", systemLanguages: ["zh-Hans-CN"]) == "en", "Manual UI language overrides system")
        try check(Localizer.languageCode(preference: "system", systemLanguages: ["fr-FR"]) == "en", "Unsupported system language falls back to English")
        try await runCacheTests()
        var settings = TranslationSettings()
        for text in [" ", "  ", "'", ",", ".", "!", "@", "3", "😀", "。"] {
            try check(InputSafety.insertsWithoutComposition(text, hasComposition: false), "Idle input does not start composition: " + text)
            try check(!InputSafety.insertsWithoutComposition(text, hasComposition: true), "Existing composition retains input: " + text)
        }
        for text in ["", "n", "H", "é", "你好"] {
            try check(!InputSafety.insertsWithoutComposition(text, hasComposition: false), "Text input retains composition: " + text)
        }
        try check(ChinesePunctuation.convert(".", preceding: "3") == ".", "Decimal point after a digit")
        try check(ChinesePunctuation.convert(":", preceding: "9") == ":", "Time separator after a digit")
        try check(ChinesePunctuation.convert(".", preceding: "２") == ".", "Decimal point after full-width digit")
        try check(ChinesePunctuation.convert(".", preceding: "好") == "。", "Chinese sentence retains full stop")
        try check(ChinesePunctuation.convert(".", preceding: "三") == "。", "Chinese numeral is not treated as decimal digit")
        try check(ChinesePunctuation.convert(",", preceding: "3") == ",", "Numeric comma preserves thousands grouping")
        try check(ChinesePunctuation.convert(",", preceding: "好") == "，", "Chinese prose retains Chinese comma")
        for text in ["1.2", "3.14", "192.168.1.1", "0.2.5", "09:30", "3%", "2026-10-04", "1/2", "3,444", "3,444.50"] {
            var rendered = ""
            for character in text { rendered += ChinesePunctuation.convert(String(character), preceding: rendered.last) }
            try check(rendered == text, "Numeric punctuation preserves " + text)
        }
        let visible = CGRect(x: 0, y: 0, width: 1000, height: 700)
        try check(!CandidatePlacement.validCaret(CGRect(x: 1.6e-314, y: 0, width: 1.6e-314, height: 1.6e-314)), "Reject terminal garbage subnormal geometry")
        try check(!CandidatePlacement.validCaret(CGRect(x: 0, y: 0, width: 0, height: 1)), "Reject non-line caret sentinel")
        try check(CandidatePlacement.validCaret(CGRect(x: 21, y: 97, width: 1, height: 19)), "Accept real terminal line rectangle")
        for caret in [CGRect(x: 100, y: 200, width: 1, height: 20), CGRect(x: 990, y: 680, width: 1, height: 20), CGRect(x: 100, y: 300, width: 1, height: 20)] {
            let frame = CandidatePlacement.frame(caret: caret, desired: CGSize(width: 380, height: 500), visible: visible)!
            try check(!frame.intersects(caret.insetBy(dx: 0, dy: -4)) && visible.contains(frame), "Candidate frame avoids current text line and remains onscreen")
        }
        try check(InputSafety.returnCommitsRaw(language: .zh, rawInput: "nihao", selectedTranslation: false, clipboard: false), "Return commits raw pinyin")
        try check(InputSafety.returnCommitsRaw(language: .zh, rawInput: "hello", selectedTranslation: false, clipboard: false), "Return commits English in Chinese mode")
        try check(!InputSafety.returnCommitsRaw(language: .zh, rawInput: "nihao", selectedTranslation: true, clipboard: false), "Explicit translation selection retains Return priority")
        try check(!InputSafety.returnCommitsRaw(language: .zh, rawInput: "", selectedTranslation: false, clipboard: false), "Empty composition does not consume application Return")
        try check(CandidatePlacement.frame(caret: CGRect(x: 413, y: 17000, width: 2, height: 20), desired: CGSize(width: 460, height: 300), visible: CGRect(x: 0, y: 0, width: 1512, height: 982)) == nil, "Offscreen accessibility anchors cannot place panels outside the screen")
        try check(CandidatePlacement.frame(caret: CGRect(x: 21, y: 49, width: 0, height: 19), desired: CGSize(width: 460, height: 300), visible: CGRect(x: 0, y: 0, width: 1512, height: 982)) != nil, "Fullscreen terminal zero-width caret near hidden Dock remains visible")
        var caretCalibration = CaretGeometry()
        caretCalibration.calibrate(primary: CGRect(x: 1145.168, y: 219, width: 0, height: 19), legacy: CGRect(x: 1145.1682, y: 200, width: 1, height: 19))
        try check(caretCalibration.adjusted(CGRect(x: 1178, y: 219, width: 0, height: 19)).minY == 200, "WeCom one-line cursor offset stays corrected during composition")
        caretCalibration.calibrate(primary: CGRect(x: 1178, y: 219, width: 0, height: 19), legacy: .zero)
        try check(caretCalibration.adjusted(CGRect(x: 1178, y: 219, width: 0, height: 19)).minY == 200, "Missing legacy geometry during composition does not erase calibration")
        try check(caretCalibration.adjusted(CGRect(x: 1178, y: 219, width: 0, height: 28)).minY == 219, "Font-size changes cannot reuse an old vertical correction")
        var emptyCaretCalibration = CaretGeometry()
        emptyCaretCalibration.calibrate(primary: CGRect(x: 427, y: 219, width: 0, height: 18), legacy: CGRect(x: 427, y: 201, width: 1, height: 18))
        try check(emptyCaretCalibration.adjusted(CGRect(x: 438, y: 219, width: 0, height: 19)).minY == 200, "Empty WeCom editor 18-to-19pt first-character transition retains one-line calibration")
        let anchor = CGRect(x: 300, y: 350, width: 1, height: 20)
        let screen = CGRect(x: 0, y: 0, width: 1200, height: 800)
        let small = CandidatePlacement.frame(caret: anchor, desired: CGSize(width: 380, height: 180), visible: screen)!
        let expanded = CandidatePlacement.frame(caret: anchor, desired: CGSize(width: 380, height: 550), visible: screen, preferredAbove: small.minY > anchor.maxY)!
        try check(small.minY == expanded.minY && small.minX == expanded.minX, "Translation expansion preserves placement side and anchored edge")
        let upperCaret = CGRect(x: 120, y: 500, width: 2, height: 20)
        let fixedSide = CandidatePlacement.frame(caret: upperCaret, desired: CGSize(width: 460, height: 420), visible: screen, preferredAbove: true, keepSide: true)!
        try check(fixedSide.minY >= upperCaret.maxY && fixedSide.height < 420, "Selection popup keeps its side and scrolls when translation grows")
        let movedBelow = CandidatePlacement.frame(caret: upperCaret, desired: CGSize(width: 460, height: 330), visible: screen, preferredAbove: true)!
        try check(movedBelow.maxY < upperCaret.minY && movedBelow.height == 330,
                  "Insufficient space above moves the complete panel below despite previous anchor")
        let lowerCaret = CGRect(x: 120, y: 200, width: 2, height: 20)
        let movedAbove = CandidatePlacement.frame(caret: lowerCaret, desired: CGSize(width: 460, height: 330), visible: screen, preferredAbove: false)!
        try check(movedAbove.minY > lowerCaret.maxY && movedAbove.height == 330,
                  "Insufficient space below moves the complete panel above")
        let neither = CandidatePlacement.frame(caret: upperCaret, desired: CGSize(width: 460, height: 900), visible: screen, preferredAbove: true)!
        try check(neither.maxY < upperCaret.minY && screen.contains(neither),
                  "When neither side fits, use the larger available area")
        let multiline = CGRect(x: 100, y: 250, width: 650, height: 160)
        let multilineCaret = CGRect(x: 450, y: 250, width: 2, height: 22)
        for height in [120.0, 350.0, 600.0] {
            let placed = CandidatePlacement.frame(caret: multilineCaret, desired: CGSize(width: 380, height: height), visible: screen, preferredAbove: true, avoiding: multiline)!
            try check(!placed.intersects(multiline.insetBy(dx: 0, dy: -4)), "Candidate avoids every line of active composition at height \(height)")
        }
        try check(InputSafety.spaceCommitsSentence(language: .zh, sentenceMode: true, hasPreedit: false, draft: "哈哈哈"), "Space commits composed Chinese sentence")
        try check(!InputSafety.spaceCommitsSentence(language: .zh, sentenceMode: true, hasPreedit: true, draft: "哈哈哈"), "Space still selects pending Pinyin")
        try check(!InputSafety.spaceCommitsSentence(language: .en, sentenceMode: true, hasPreedit: false, draft: "hello"), "English spaces stay word separators")
        try check(!InputSafety.spaceCommitsSentence(language: .id, sentenceMode: true, hasPreedit: false, draft: "selamat"), "Indonesian spaces stay word separators")
        try check(!InputSafety.spaceCommitsSentence(language: .zh, sentenceMode: false, hasPreedit: false, draft: "你好"), "Normal mode unaffected by sentence-space rule")
        try check(!InputSafety.bypassInputMethod(bundleIdentifier: "com.apple.Terminal") && !InputSafety.bypassInputMethod(bundleIdentifier: "com.googlecode.iterm2"), "Terminals retain Chinese input support")
        try check(!InputSafety.bypassInputMethod(bundleIdentifier: "com.apple.TextEdit"), "Other apps retain input support")
        try check(InputSafety.bypassInputMethod(bundleIdentifier: "app.guyi.inputmethod.Guyi"), "GuYi settings are not composed or translated by their own backend")
        try check(!InputSafety.bypassInputMethod(bundleIdentifier: "com.tencent.xinWeChat") && !InputSafety.bypassInputMethod(bundleIdentifier: "com.tencent.WeWorkMac"),
                  "WeChat and WeCom are not bypassed as a workaround")
        let request = try OpenAITranslator().request("你好", settings: settings, apiKey: "test-not-a-real-key")
        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        try check(request.url?.absoluteString == "https://api.openai.com/v1/responses", "Responses endpoint")
        try check(body["store"] as? Bool == false, "Server storage disabled")
        try check((body["text"] as? [String: Any])?["format"] != nil, "Structured output requested")
        let instructions = body["instructions"] as? String ?? ""
        try check(instructions.contains("Never warn merely that it is incomplete"), "Live typing fragments are not treated as errors")
        try check(instructions.contains("never invent its continuation"), "Incomplete input must not be silently completed")
        let requestInput = try JSONSerialization.jsonObject(with: Data((body["input"] as! String).utf8)) as! [String: Any]
        try check(requestInput["note_language"] as? String == Localizer.code, "Translation explanation follows interface language")
        try check(tryDecode() == "Hello", "Decode complete three-language response")
        for status in ["incomplete", "failed", "in_progress"] {
            do { _ = try OpenAITranslator.decode(response(status: status)); throw Failure.check(status) }
            catch is TranslationError { print("PASS · Reject " + status) }
        }
        do { _ = try OpenAITranslator.decode(response(text: "")); throw Failure.check("blank translation") }
        catch is TranslationError { print("PASS · Reject blank translation") }
        let refusal = try JSONSerialization.data(withJSONObject: ["status": "completed", "output": [["content": [["type": "refusal"]]]]])
        do { _ = try OpenAITranslator.decode(refusal); throw Failure.check("refusal") }
        catch is TranslationError { print("PASS · Reject refusal") }
        settings.endpoint = "http://example.com/v1"
        let httpURL = try settings.validatedURL()
        try check(httpURL.absoluteString == "http://example.com/v1/responses", "Allow HTTP endpoint")
        settings.endpoint = "http://127.0.0.1:8080/v1"
        let localRequest = try OpenAITranslator().request("你好", settings: settings, apiKey: "test")
        try check(localRequest.url?.absoluteString == "http://127.0.0.1:8080/v1/responses", "Preserve HTTP host and port")
        for endpoint in ["ftp://example.com/v1", "file:///tmp/v1", "https://user:password@example.com/v1", "https://example.com/v1?token=test", "https://example.com/v1#fragment"] {
            settings.endpoint = endpoint
            do { _ = try settings.validatedURL(); throw Failure.check(endpoint) }
            catch is TranslationError { print("PASS · Reject invalid API endpoint") }
        }
        settings = TranslationSettings()
        let roundTrip = try JSONDecoder().decode(TranslationSettings.self, from: JSONEncoder().encode(settings))
        try check(roundTrip == settings, "Persist all settings")
        try check(InsertionText.singleLine("hello\r\nworld\u{1b}\t\u{2028}!") == "hello world!", "Strip newlines and terminal control characters")

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let client = OpenAITranslator(session: URLSession(configuration: configuration))
        MockURLProtocol.data = try response(text: "rewritten source")
        settings.source = .zh
        let translated = try await client.translate("原文不改写", settings: settings, apiKey: "test")
        try check(translated.zh == "原文不改写", "Original text always preserved")
        MockURLProtocol.status = 429
        do { _ = try await client.translate("test", settings: settings, apiKey: "test"); throw Failure.check("429") }
        catch TranslationError.http(429) { print("PASS · Rate limit is actionable") }
        let stub = StubTranslator()
        let session = TranslationSession(translator: stub, cache: TranslationCache())
        session.update(text: "old", composing: false, settings: settings, apiKey: "test", immediate: true)
        try await Task.sleep(nanoseconds: 30_000_000)
        session.update(text: "new", composing: false, settings: settings, apiKey: "test", immediate: true)
        try check(session.result == nil, "Old candidate immediately invalidated")
        try await Task.sleep(nanoseconds: 230_000_000)
        try check(session.result?.zh == "new", "Late response cannot overwrite newer text")
        let beforeCache = await stub.calls
        session.update(text: "new", composing: false, settings: settings, apiKey: "test", immediate: true)
        let afterCache = await stub.calls
        try check(beforeCache == afterCache && session.result?.zh == "new", "Memory cache avoids repeat request")
        session.update(text: "marked", composing: true, settings: settings, apiKey: "test")
        try await Task.sleep(nanoseconds: 250_000_000)
        let afterComposing = await stub.calls
        try check(afterComposing == afterCache && session.result == nil, "Uncommitted composition not sent")
        settings.automatic = false
        session.update(text: "manual", composing: false, settings: settings, apiKey: "test")
        try check(!session.busy && session.result == nil, "Manual mode does not request")
        session.update(text: "manual", composing: false, settings: settings, apiKey: "test", immediate: true)
        session.invalidate()
        try await Task.sleep(nanoseconds: 60_000_000)
        try check(session.result == nil && !session.busy, "Deactivation cancels pending candidate")
        print("All checks passed. No network requests were made.")
        var multilingual = TranslationSettings()
        multilingual.source = .zh
        multilingual.enabledLanguages = [.ja, .fr]
        try check(multilingual.translationTargets == [.ja, .fr], "Only explicitly enabled extended languages are requested")
        try check(LocalPhrases.lookup("你好", settings: multilingual) == nil, "Three-language local phrase cannot bypass extended translation")
        let extended = Translation(source: .zh, zh: "你好", en: "", id: "", note: "", additional: ["ja": "こんにちは", "fr": "Bonjour"])
        let extendedData = try JSONEncoder().encode(extended)
        let restored = try JSONDecoder().decode(Translation.self, from: extendedData)
        try check(restored.text(for: .ja) == "こんにちは", "Extended translation survives cache encoding")
        try check(TranslationPreview.fields(in: #"{"ja":"こんにちは"}"#)["ja"] == "こんにちは", "Extended language streaming preview")
        let completeField = TranslationPreview.fields(in: #"{"en":"Hello","id":"Ha"#)
        for source in Language.targets {
            var mode = TranslationSettings()
            mode.source = source
            mode.enabledLanguages = [.zh, .en, .id, .ja, .fr]
            try check(mode.translationTargets == [.zh, .en, .id, .ja, .fr].filter { $0 != source }, "Enabled targets remain active for source \(source.rawValue)")
        }
        var englishMode = TranslationSettings()
        englishMode.source = .en
        englishMode.enabledLanguages = [.zh, .id]
        let englishSession = TranslationSession(cache: TranslationCache())
        englishSession.update(text: "Hello", composing: false, settings: englishMode, apiKey: "")
        try check(englishSession.result?.zh == "你好" && englishSession.result?.id == "Halo", "English mode displays enabled Chinese and Indonesian translations")
        englishMode.source = .id
        englishMode.enabledLanguages = [.zh, .en]
        englishSession.update(text: "Halo", composing: false, settings: englishMode, apiKey: "")
        try check(englishSession.result?.zh == "你好" && englishSession.result?.en == "Hello", "Indonesian mode displays enabled Chinese and English translations")
        try check(completeField["en"] == "Hello" && completeField["id"] == nil, "Stream shows finished language before entire response")
        try check(TranslationPreview.partialFields(in: #"{"en":"Hel"#)["en"] == "Hel", "Streaming displays unfinished text without making it selectable")
        try check(TranslationPreview.partialFields(in: #"{"en":"Hi \u4F"#)["en"] == "Hi ", "Streaming omits incomplete Unicode escape")
        let escaped = TranslationPreview.fields(in: #"{"en":"Say \"hello\"","id":"Halo"}"#)
        try check(escaped["en"] == "Say \"hello\"", "Streaming handles escaped quotes")
        var parser = ResponseStream()
        let delta = try JSONSerialization.data(withJSONObject: ["type": "response.output_text.delta", "delta": "{\"en\":\"Hello\","])
        let update = try parser.consume(delta)
        try check(update.preview["en"] == "Hello" && update.completed == nil, "Partial result not selectable before completion")
        let incomplete = try JSONSerialization.data(withJSONObject: ["type": "response.incomplete"])
        do { _ = try parser.consume(incomplete); throw Failure.check("stream incomplete") }
        catch is TranslationError { print("PASS · Stream failure cannot become a completed translation") }
        settings = TranslationSettings()
        let localSession = TranslationSession(translator: stub, cache: TranslationCache())
        localSession.update(text: "谢谢", composing: false, settings: settings, apiKey: "")
        try check(localSession.result?.en == "Thank you" && localSession.result?.id == "Terima kasih", "Common phrase translates immediately without API")
        settings.glossary = "谢谢 = custom"
        try check(LocalPhrases.lookup("谢谢", settings: settings) == nil, "Glossary overrides local phrase fast path")
        settings = TranslationSettings()
        settings.debounceMilliseconds = 0
        let duplicateSession = TranslationSession(translator: stub, cache: TranslationCache())
        let beforeDuplicate = await stub.calls
        duplicateSession.update(text: "duplicate", composing: false, settings: settings, apiKey: "test")
        try await Task.sleep(nanoseconds: 5_000_000)
        duplicateSession.update(text: "duplicate", composing: false, settings: settings, apiKey: "test")
        try await Task.sleep(nanoseconds: 80_000_000)
        let afterDuplicate = await stub.calls
        try check(afterDuplicate == beforeDuplicate + 1 && duplicateSession.result?.zh == "duplicate", "Same candidate does not restart in-flight request")
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as! [String: Any]
        legacy.removeValue(forKey: "sentenceComposition")
        let migrated = try JSONDecoder().decode(TranslationSettings.self, from: JSONSerialization.data(withJSONObject: legacy))
        try check(migrated.sentenceComposition != true, "Old settings default to standard typing without losing provider")
        settings.enabledLanguages = []
        let beforeDisabled = await stub.calls
        duplicateSession.update(text: "disabled targets", composing: false, settings: settings, apiKey: "test", immediate: true)
        try await Task.sleep(nanoseconds: 80_000_000)
        let afterDisabled = await stub.calls
        try check(afterDisabled == beforeDisabled && !duplicateSession.busy && duplicateSession.result == nil, "All translations collapsed means zero model requests")
        settings.source = .zh
        settings.enabledLanguages = [.en]
        let targetRequest = try OpenAITranslator().request("测试", settings: settings, apiKey: "test")
        let targetBody = try JSONSerialization.jsonObject(with: targetRequest.httpBody!) as! [String: Any]
        let format = (targetBody["text"] as! [String: Any])["format"] as! [String: Any]
        let properties = (format["schema"] as! [String: Any])["properties"] as! [String: Any]
        try check((properties["id"] as? [String: Any])?["enum"] as? [String] == [""], "Disabled Indonesian is not generated")
        let payload: [String: Any] = ["status": "completed", "output": [["content": [["type": "output_text", "text": "{\"source\":\"zh\",\"zh\":\"测试\",\"en\":\"Test\",\"id\":\"\",\"note\":\"\"}"]]]]]
        let singleLanguage = try OpenAITranslator.decode(JSONSerialization.data(withJSONObject: payload), languages: [.en])
        try check(singleLanguage.en == "Test" && singleLanguage.id.isEmpty, "Single-language result validates without disabled field")
        let staged = TranslationSession(translator: StagedTranslator(), cache: TranslationCache())
        settings.enabledLanguages = [.en, .id]
        staged.update(text: "staged", composing: false, settings: settings, apiKey: "test", immediate: true)
        try await Task.sleep(nanoseconds: 50_000_000)
        try check(staged.selectableText(for: .en) == "Hello" && staged.result == nil && staged.selectableText(for: .id) == nil, "Finished English can commit while Indonesian is still pending")
        settings.enabledLanguages = []
        staged.update(text: "staged", composing: false, settings: settings, apiKey: "test", immediate: true)
        try check(staged.selectableText(for: .en) == nil && !staged.busy, "Collapsing all targets cancels early selectable output")
        try check(migrated.translateClipboard != false, "Clipboard translation defaults on for existing settings")
        try check(migrated.showPinyin != true, "Pinyin hint defaults hidden for existing users")
        try check(SentenceBoundary.endsSentence("明天见。") && SentenceBoundary.endsSentence("Really?"), "Sentence-ending punctuation triggers translation")
        try check(!SentenceBoundary.endsSentence("先确认，") && !SentenceBoundary.endsSentence("3.14") && !SentenceBoundary.endsSentence(""), "Commas and decimal numbers do not split sentences")
        let words = try HotwordLexicon.parse("# metadata\n新词\txin ci\t100\n坏词\t$(command)\n新词\txin ci\t100")
        try check(words.count == 1 && words[0].pinyin == "xinci", "Network dictionary accepts only data and removes duplicates")
        MockURLProtocol.status = 200
        let lesson: [String: Any] = ["structure": "Hello 是问候语", "points": ["用于问候"], "register": "日常",
            "example": "Hello, Lin! 你好，林！", "ipa": "/həˈloʊ/", "pronunciation": "重音在第二音节。",
            "vocabulary": [["word": "Hello", "ipa": "/həˈloʊ/", "meaning": "你好"]]]
        func lessonResponse(_ value: [String: Any]) throws -> Data {
            let text = String(decoding: try JSONSerialization.data(withJSONObject: value), as: UTF8.self)
            return try JSONSerialization.data(withJSONObject: ["status": "completed", "output": [["content": [["type": "output_text", "text": text]]]]])
        }
        MockURLProtocol.data = try lessonResponse(lesson)
        let teacher = GrammarTeacher(session: URLSession(configuration: configuration))
        let learning = try await teacher.explain(original: "你好", translation: "Hello", language: .en, settings: settings, apiKey: "test")
        try check(learning.ipa == "/həˈloʊ/" && learning.vocabulary?.first?.word == "Hello", "IPA learning fields decode")
        var unrelated = lesson
        unrelated["vocabulary"] = [["word": "unrelated", "ipa": "", "meaning": "不应出现"]]
        MockURLProtocol.data = try lessonResponse(unrelated)
        do {
            _ = try await teacher.explain(original: "你好", translation: "Hello", language: .en, settings: settings, apiKey: "test")
            throw Failure.check("Unrelated vocabulary")
        } catch is TranslationError { print("PASS · Reject learning words not in current translation") }
        do {
            _ = try await teacher.explain(original: "你好", translation: "", language: .en, settings: settings, apiKey: "test")
            throw Failure.check("Empty learning input")
        } catch is TranslationError { print("PASS · Empty translation cannot trigger a lesson") }
        try await testBlockTranslation()
    }
    static func tryDecode() -> String { (try? OpenAITranslator.decode(response()).en) ?? "" }
}
