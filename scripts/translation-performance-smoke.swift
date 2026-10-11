import Foundation
import Combine
import GuyiCore

actor PreviewClock {
    private var first: TimeInterval?
    func record(_ elapsed: TimeInterval) { if first == nil { first = elapsed } }
    func value() -> TimeInterval? { first }
}

@main
struct TranslationPerformanceSmoke {
    @MainActor static func main() async {
        guard let saved = UserDefaults(suiteName: "app.guyi.inputmethod.Guyi")?.data(forKey: "translationSettings"),
              var settings = try? JSONDecoder().decode(TranslationSettings.self, from: saved),
              case .available(let key) = LocalCredential.readResult() else {
            print("BLOCKED · Local translation service is unavailable")
            return
        }
        let cacheURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("guyi-perf-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: cacheURL) }
        let cache = TranslationCache(diskURL: cacheURL)
        settings.enabledLanguages = [.en]
        settings.source = .zh
        settings.debounceMilliseconds = 0
        settings.timeoutSeconds = min(settings.timeoutSeconds, 20)
        let text = "请明天下午确认设备到货时间。"
        let session = TranslationSession(cache: cache)
        let start = Date()
        session.update(text: text, composing: false, settings: settings, apiKey: key, immediate: true)
        await session.waitForCurrentRequest()
        print(String(format: "INPUT_CLOUD_SECONDS %.2f SUCCESS %@",
                     Date().timeIntervalSince(start), session.result?.en.isEmpty == false ? "true" : "false"))
        if session.result?.en.isEmpty != false {
            let directStarted = Date()
            let previewClock = PreviewClock()
            do {
                let direct = try await OpenAITranslator().stream(text, settings: settings, apiKey: key) { fields in
                    if !fields.isEmpty { await previewClock.record(Date().timeIntervalSince(directStarted)) }
                }
                print(String(format: "DIRECT_CLOUD_FIRST_PREVIEW_SECONDS %.2f COMPLETE_SECONDS %.2f SUCCESS %@",
                             await previewClock.value() ?? -1, Date().timeIntervalSince(directStarted), direct.en.isEmpty ? "false" : "true"))
            } catch {
                print(String(format: "DIRECT_CLOUD_FIRST_PREVIEW_SECONDS %.2f COMPLETE_SECONDS %.2f FAILED",
                             await previewClock.value() ?? -1, Date().timeIntervalSince(directStarted)))
            }
            return
        }
        await cache.flush()
        let diskSession = TranslationSession(cache: TranslationCache(diskURL: cacheURL))
        let hit = Date()
        diskSession.update(text: text, composing: false, settings: settings, apiKey: key, immediate: true)
        await diskSession.waitForCurrentRequest()
        print(String(format: "INPUT_DISK_CACHE_MS %.2f HIT %@",
                     Date().timeIntervalSince(hit) * 1_000,
                     diskSession.status.contains("缓存") ? "true" : "false"))
        settings.source = .auto
        settings.enabledLanguages = [.zh]
        settings.translateWholeSelection = true
        settings.timeoutSeconds = 45
        let selection = TranslationSession(cache: cache)
        let selectedStart = Date()
        selection.update(text: "Please confirm the delivery date tomorrow.", composing: false,
                         settings: settings, apiKey: key, immediate: true)
        await selection.waitForCurrentRequest()
        print(String(format: "SELECTION_CLOUD_SECONDS %.2f SUCCESS %@",
                     Date().timeIntervalSince(selectedStart),
                     selection.result?.zh.isEmpty == false ? "true" : "false"))
    }
}
