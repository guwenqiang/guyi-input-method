import Foundation
import GuyiCore

actor SwitchingTranslator: Translating {
    private(set) var calls = 0
    func translate(_ text: String, settings: TranslationSettings, apiKey: String) async throws -> Translation {
        calls += 1
        return Translation(source: .zh, zh: text,
                           en: settings.model == "model-b" ? "Second translation" : "First translation",
                           id: "", note: "")
    }
}

@main
struct CacheModelSwitchSmoke {
    @MainActor static func main() async {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("guyi-model-switch-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let cache = TranslationCache(diskURL: url)
        let translator = SwitchingTranslator()
        var first = TranslationSettings()
        first.source = .zh
        first.enabledLanguages = [.en]
        first.model = "model-a"
        let initial = TranslationSession(translator: translator, cache: cache)
        initial.update(text: "合成缓存测试", composing: false, settings: first, apiKey: "fixture", immediate: true)
        await initial.waitForCurrentRequest()
        await cache.flush()
        var second = first
        second.model = "model-b"
        second.apiProtocol = .chatCompletions
        second.plainJSONOutput = true
        let reopened = TranslationCache(diskURL: url)
        let switched = TranslationSession(translator: translator, cache: reopened)
        switched.update(text: "合成缓存测试", composing: false, settings: second, apiKey: "fixture", immediate: true)
        await switched.waitForCurrentRequest()
        let reusedCalls = await translator.calls
        let reused = switched.result?.en == "First translation" && reusedCalls == 1
        switched.update(text: "合成缓存测试", composing: false, settings: second, apiKey: "fixture",
                        immediate: true, forceRefresh: true)
        await switched.waitForCurrentRequest()
        await reopened.flush()
        let refreshedCalls = await translator.calls
        let refreshed = switched.result?.en == "Second translation" && refreshedCalls == 2
        let finalCache = TranslationCache(diskURL: url)
        let finalSession = TranslationSession(translator: translator, cache: finalCache)
        finalSession.update(text: "合成缓存测试", composing: false, settings: first, apiKey: "fixture", immediate: true)
        await finalSession.waitForCurrentRequest()
        let finalCalls = await translator.calls
        let persisted = finalSession.result?.en == "Second translation" && finalCalls == 2
        print("DISK_REUSE \(reused) REFRESH_REPLACES \(refreshed) RESTART_READS_NEW \(persisted)")
        if !reused || !refreshed || !persisted { exit(1) }
    }
}
