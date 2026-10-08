import Foundation
import GuyiCore

actor ForbiddenNetwork: Translating {
    private(set) var calls = 0
    func translate(_ text: String, settings: TranslationSettings, apiKey: String) async throws -> Translation {
        calls += 1
        throw TranslationError.network
    }
}

@main
struct CacheLatency {
    @MainActor static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("guyi-benchmark-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("cache.sqlite")
        var settings = TranslationSettings()
        settings.source = .zh
        settings.enabledLanguages = [.en, .id]
        let sample = Data(#"{"source":"zh","zh":"","en":"Please confirm tomorrow.","id":"Mohon konfirmasi besok.","note":""}"#.utf8)
        let result = try JSONDecoder().decode(Translation.self, from: sample)
        let writer = TranslationCache(diskURL: url)
        for index in 0..<1000 {
            writer.put(result, key: TranslationCache.key(text: "基准样本 \(index)", settings: settings), languages: [.en, .id])
            await writer.flush()
        }
        let network = ForbiddenNetwork()
        for tier in ["disk", "memory"] {
            let reader = TranslationCache(diskURL: url)
            if tier == "memory" {
                reader.put(result, key: TranslationCache.key(text: "基准样本 0", settings: settings), languages: [.en, .id])
                await reader.flush()
            }
            let session = TranslationSession(translator: network, cache: reader)
            var milliseconds: [Double] = []
            var failures = 0
            for index in 0..<1000 {
                session.invalidate()
                let start = DispatchTime.now().uptimeNanoseconds
                session.update(text: "基准样本 \(tier == "memory" ? 0 : index)", composing: false, settings: settings, apiKey: "", immediate: false)
                await session.waitForCurrentRequest()
                let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
                milliseconds.append(elapsed)
                if session.result?.en != result.en || session.result?.id != result.id { failures += 1 }
            }
            milliseconds.sort()
            let within = milliseconds.filter { $0 <= 1000 }.count
            print(String(format: "%@: n=1000 p50=%.3fms p95=%.3fms p99=%.3fms max=%.3fms <=1s=%d/1000 correctness_failures=%d", tier, milliseconds[499], milliseconds[949], milliseconds[989], milliseconds[999], within, failures))
            guard within >= 990 && failures == 0 else { exit(1) }
        }
        let calls = await network.calls
        print("Network requests: \(calls). Local cache benchmark only; not cloud SLA acceptance.")
        guard calls == 0 else { exit(1) }
    }
}
