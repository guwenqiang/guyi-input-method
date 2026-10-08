import Foundation
import GuyiCore

@MainActor
final class HotwordStore: ObservableObject {
    static let shared = HotwordStore()
    @Published private(set) var status = "尚未更新"
    @Published private(set) var updating = false
    private var index: [String: [String]] = [:]
    private var timer: Timer?
    private var task: Task<Void, Never>?
    private var enabled = false
    private let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("guyi/Hotwords")
    private let source = URL(string: "https://raw.githubusercontent.com/iDvel/rime-ice/main/cn_dicts/others.dict.yaml")!

    private init() {
        if let data = try? Data(contentsOf: directory.appendingPathComponent("words.json")),
           let entries = try? JSONDecoder().decode([HotwordEntry].self, from: data) { apply(entries) }
    }
    func configure(enabled: Bool) {
        if self.enabled == enabled, timer != nil { return }
        self.enabled = enabled
        timer?.invalidate()
        guard enabled else { task?.cancel(); timer = nil; status = "已关闭"; return }
        if !index.isEmpty { status = "本地词库已启用" }
        check()
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.check() }
        }
    }
    func matches(_ preedit: String) -> [String] {
        guard enabled else { return [] }
        let key = preedit.lowercased().filter { $0 != " " && $0 != "'" }
        return index[key] ?? []
    }
    func check(force: Bool = false) {
        guard enabled, !updating else { return }
        let last = UserDefaults.standard.object(forKey: "hotwordsLastAttempt") as? Date ?? .distantPast
        guard force || Date().timeIntervalSince(last) >= 86400 else { return }
        updating = true
        status = "更新中…"
        UserDefaults.standard.set(Date(), forKey: "hotwordsLastAttempt")
        task = Task { [weak self] in
            guard let self else { return }
            defer { self.updating = false }
            do {
                let configuration = URLSessionConfiguration.ephemeral
                configuration.timeoutIntervalForRequest = 20
                configuration.timeoutIntervalForResource = 30
                let session = URLSession(configuration: configuration)
                defer { session.invalidateAndCancel() }
                let (bytes, response) = try await session.bytes(from: self.source)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw TranslationError.network }
                var data = Data()
                for try await byte in bytes {
                    try Task.checkCancellation()
                    data.append(byte)
                    guard data.count <= 2_000_000 else { throw TranslationError.invalidResponse }
                }
                let entries = try await Task.detached { try HotwordLexicon.parse(String(decoding: data, as: UTF8.self)) }.value
                try Task.checkCancellation()
                guard self.enabled else { return }
                try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
                try JSONEncoder().encode(entries).write(to: self.directory.appendingPathComponent("words.json"), options: .atomic)
                self.apply(entries)
                UserDefaults.standard.set(Date(), forKey: "hotwordsLastSuccess")
            } catch {
                if !Task.isCancelled { self.status = self.index.isEmpty ? "更新失败，可稍后重试" : "更新失败，继续使用本地词库" }
            }
        }
    }
    private func apply(_ entries: [HotwordEntry]) {
        index = Dictionary(grouping: entries, by: \.pinyin).mapValues { Array($0.prefix(5)).map(\.text) }
        status = Localizer.format("已加载 %d 个词条", entries.count)
    }
}
