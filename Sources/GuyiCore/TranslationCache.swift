import Foundation
import CryptoKit

@MainActor
public final class TranslationCache {
    public static let shared = TranslationCache(diskURL: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("guyi/TranslationCache/translations.sqlite"))
    private struct Entry { let data: Data; let created: Date }
    private var entries: [Data: Entry] = [:]
    private var order: [Data] = []
    public private(set) var memoryBytes = 0
    public private(set) var revision = 0
    public var entryCount: Int { entries.count }
    private let disk: TranslationDiskCache?
    private let now: () -> Date
    private var retentionDays = 7
    private var diskTail: Task<Void, Never>?
    private var pendingWrites = 0
    private var lastMaintenance = Date.distantPast
    public static let memoryLimit = 8 * 1024 * 1024
    public static let entryLimit = 1024
    public init(diskURL: URL? = nil, now: @escaping () -> Date = Date.init) {
        disk = diskURL.map { TranslationDiskCache(url: $0) }
        self.now = now
    }
    public static func key(text: String, settings: TranslationSettings) -> Data {
        let values: [String: String] = ["version": "6", "protocol": settings.effectiveAPIProtocol.rawValue, "note_language": Localizer.code, "text": text, "endpoint": settings.endpoint,
            "model": settings.model, "source": settings.source.rawValue, "tone": settings.tone,
            "glossary": settings.glossary, "targets": settings.translationTargets.map(\.rawValue).sorted().joined(separator: ","), "whole_selection": settings.translateWholeSelection == true ? "1" : "0"]
        let data = (try? JSONSerialization.data(withJSONObject: values, options: .sortedKeys)) ?? Data()
        return Data(SHA256.hash(data: data))
    }
    public func get(_ key: Data) -> Translation? {
        guard retentionDays > 0, let entry = entries[key] else { return nil }
        guard valid(entry.created) else { remove(key); return nil }
        order.removeAll { $0 == key }
        order.append(key)
        guard let result = try? JSONDecoder().decode(Translation.self, from: entry.data) else { remove(key); return nil }
        return result
    }
    public func getPersisted(_ key: Data) async -> Translation? {
        guard retentionDays > 0 else { return nil }
        if let result = get(key) { return result }
        let version = revision
        await diskTail?.value
        guard version == revision, retentionDays > 0 else { return nil }
        let current = now()
        if current.timeIntervalSince(lastMaintenance) >= 3600 {
            await disk?.expire(before: current.addingTimeInterval(-Double(retentionDays) * 86400).timeIntervalSince1970)
            lastMaintenance = current
        }
        guard let (data, created) = await disk?.get(key, cutoff: current.addingTimeInterval(-Double(retentionDays) * 86400).timeIntervalSince1970,
                                                   now: current.timeIntervalSince1970),
              version == revision, retentionDays > 0,
              let result = try? JSONDecoder().decode(Translation.self, from: data), valid(Date(timeIntervalSince1970: created)) else { return nil }
        store(data: data, key: key, created: Date(timeIntervalSince1970: created))
        return result
    }
    public func configure(days: Int) {
        let days = max(0, min(365, days))
        guard days != retentionDays else { return }
        revision += 1
        retentionDays = days
        if days == 0 { clear(); return }
        for key in Array(entries.keys) { if let entry = entries[key], !valid(entry.created) { remove(key) } }
        let cutoff = now().addingTimeInterval(-Double(days) * 86400).timeIntervalSince1970
        let preceding = diskTail
        diskTail = Task { await preceding?.value; await disk?.expire(before: cutoff) }
    }
    public func put(_ result: Translation, key: Data, languages: [Language], expectedRevision: Int? = nil, includeSource: Bool = false) {
        guard expectedRevision == nil || expectedRevision == revision else { return }
        let targets = languages.filter { $0 != .auto && (includeSource || $0 != result.source) }
        guard retentionDays > 0, !targets.isEmpty, (try? result.validated(languages: targets)) != nil else { return }
        let restricted = Translation(source: result.source,
                                     zh: targets.contains(.zh) ? result.zh : "",
                                     en: targets.contains(.en) ? result.en : "",
                                     id: targets.contains(.id) ? result.id : "", note: result.note,
                                     additional: result.additional?.filter { entry in targets.contains(where: { $0.rawValue == entry.key }) })
        guard let data = try? JSONEncoder().encode(restricted), data.count <= 64_000, key.count == 32 else { return }
        let created = now()
        store(data: data, key: key, created: created)
        guard disk != nil, pendingWrites < 16 else { return }
        pendingWrites += 1
        let version = revision
        let preceding = diskTail
        diskTail = Task {
            await preceding?.value
            defer { pendingWrites -= 1 }
            guard version == revision else { return }
            let cutoff = created.addingTimeInterval(-Double(retentionDays) * 86400).timeIntervalSince1970
            await disk?.put(data, key: key, created: created.timeIntervalSince1970, cutoff: cutoff)
        }
    }
    private func store(data: Data, key: Data, created: Date) {
        remove(key)
        entries[key] = Entry(data: data, created: created)
        memoryBytes += data.count + key.count + 512
        order.removeAll { $0 == key }
        order.append(key)
        while order.count > Self.entryLimit || memoryBytes > Self.memoryLimit {
            guard let oldest = order.first else { break }
            remove(oldest)
        }
    }
    private func valid(_ created: Date) -> Bool { now() >= created && now().timeIntervalSince(created) < Double(retentionDays) * 86400 }
    private func remove(_ key: Data) {
        if let entry = entries.removeValue(forKey: key) { memoryBytes -= entry.data.count + key.count + 512 }
        order.removeAll { $0 == key }
    }
    public func clear() {
        revision += 1
        entries.removeAll(); order.removeAll(); memoryBytes = 0
        let preceding = diskTail
        diskTail = Task { await preceding?.value; await disk?.clear() }
    }
    public func flush() async { await diskTail?.value }
}
