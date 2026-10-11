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
    private var queuedWrites: [Data: Entry] = [:]
    private var queuedOrder: [Data] = []
    private var drainingQueuedWrites = false
    private var lastMaintenance = Date.distantPast
    public static let memoryLimit = 8 * 1024 * 1024
    public static let entryLimit = 1024
    public init(diskURL: URL? = nil, now: @escaping () -> Date = Date.init) {
        disk = diskURL.map { TranslationDiskCache(url: $0) }
        self.now = now
    }
    public static func key(text: String, settings: TranslationSettings, credential: String = "") -> Data {
        makeKey(text: text, settings: settings, credential: credential, legacyModel: nil,
                legacyProtocol: nil, includePlainOutput: false)
    }
    private static func makeKey(text: String, settings: TranslationSettings, credential: String,
                                legacyModel: String?, legacyProtocol: CloudAPIProtocol?,
                                includePlainOutput: Bool) -> Data {
        let credentialHash = Data(SHA256.hash(data: Data(credential.utf8))).base64EncodedString()
        let version = legacyModel != nil ? "7" : legacyProtocol != nil ? "8" : "9"
        var values: [String: String] = ["version": version, "credential": credentialHash,
            "note_language": Localizer.code, "text": text, "endpoint": settings.endpoint,
            "source": settings.source.rawValue, "tone": settings.tone,
            "glossary": settings.glossary, "targets": settings.translationTargets.map(\.rawValue).sorted().joined(separator: ","), "whole_selection": settings.translateWholeSelection == true ? "1" : "0"]
        if let legacyModel { values["model"] = legacyModel }
        if let legacyProtocol { values["protocol"] = legacyProtocol.rawValue }
        if includePlainOutput { values["plain_json_output"] = settings.plainJSONOutput == true ? "1" : "0" }
        let data = (try? JSONSerialization.data(withJSONObject: values, options: .sortedKeys)) ?? Data()
        return Data(SHA256.hash(data: data))
    }
    private static func legacyKeys(text: String, settings: TranslationSettings, credential: String) -> [Data] {
        var seen = Set<String>()
        let models = ([settings.model] + (settings.cachePreviousModels ?? []))
            .filter { !$0.isEmpty && seen.insert($0).inserted }.prefix(5)
        let protocols = [settings.effectiveAPIProtocol] + CloudAPIProtocol.allCases.filter { $0 != settings.effectiveAPIProtocol }
        return protocols.flatMap { kind -> [Data] in
            var keys: [Data] = []
            for plain in [settings.plainJSONOutput == true, settings.plainJSONOutput != true] {
                var legacySettings = settings
                legacySettings.plainJSONOutput = plain
                keys.append(makeKey(text: text, settings: legacySettings, credential: credential,
                                    legacyModel: nil, legacyProtocol: kind, includePlainOutput: true))
            }
            for model in models {
                for plain in [settings.plainJSONOutput == true, settings.plainJSONOutput != true] {
                    var legacySettings = settings
                    legacySettings.plainJSONOutput = plain
                    keys.append(makeKey(text: text, settings: legacySettings, credential: credential,
                                        legacyModel: model, legacyProtocol: kind, includePlainOutput: true))
                }
                keys.append(makeKey(text: text, settings: settings, credential: credential,
                                    legacyModel: model, legacyProtocol: kind, includePlainOutput: false))
            }
            return keys
        }
    }
    public func reusable(text: String, settings: TranslationSettings, credential: String = "") -> Translation? {
        var combined: Translation?
        for language in settings.translationTargets {
            var single = settings
            single.enabledLanguages = [language]
            let sharedKey = Self.key(text: text, settings: single, credential: credential)
            var value = get(sharedKey)
            if value == nil {
                for oldKey in Self.legacyKeys(text: text, settings: single, credential: credential) {
                    if let old = get(oldKey) {
                        value = old
                        put(old, key: sharedKey, languages: [language], includeSource: settings.translateWholeSelection == true)
                        break
                    }
                }
            }
            guard let value else { continue }
            combined = combined?.merging(value) ?? value
        }
        return combined
    }
    public func persistedReusable(text: String, settings: TranslationSettings, credential: String = "") async -> Translation? {
        var combined: Translation?
        for language in settings.translationTargets {
            var single = settings
            single.enabledLanguages = [language]
            let sharedKey = Self.key(text: text, settings: single, credential: credential)
            var value = await getPersisted(sharedKey)
            if value == nil {
                for oldKey in Self.legacyKeys(text: text, settings: single, credential: credential) {
                    if let old = await getPersisted(oldKey) {
                        value = old
                        put(old, key: sharedKey, languages: [language], includeSource: settings.translateWholeSelection == true)
                        break
                    }
                }
            }
            guard let value else { continue }
            combined = combined?.merging(value) ?? value
        }
        return combined
    }
    public func putReusable(_ result: Translation, text: String, settings: TranslationSettings,
                            credential: String = "",
                            expectedRevision: Int? = nil) {
        for language in settings.translationTargets {
            var single = settings
            single.enabledLanguages = [language]
            put(result, key: Self.key(text: text, settings: single, credential: credential), languages: [language],
                expectedRevision: expectedRevision, includeSource: settings.translateWholeSelection == true)
        }
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
        guard disk != nil else { return }
        if pendingWrites >= 16 || drainingQueuedWrites {
            queuedWrites[key] = Entry(data: data, created: created)
            queuedOrder.removeAll { $0 == key }
            queuedOrder.append(key)
            if queuedOrder.count > Self.entryLimit, let oldest = queuedOrder.first {
                queuedOrder.removeFirst()
                queuedWrites.removeValue(forKey: oldest)
            }
            return
        }
        pendingWrites += 1
        let version = revision
        let preceding = diskTail
        diskTail = Task {
            await preceding?.value
            defer {
                pendingWrites -= 1
                drainQueuedWrites()
            }
            guard version == revision else { return }
            let cutoff = created.addingTimeInterval(-Double(retentionDays) * 86400).timeIntervalSince1970
            await disk?.put(data, key: key, created: created.timeIntervalSince1970, cutoff: cutoff)
        }
    }
    private func drainQueuedWrites() {
        guard !drainingQueuedWrites else { return }
        drainingQueuedWrites = true
        defer { drainingQueuedWrites = false }
        while pendingWrites < 16, !queuedOrder.isEmpty {
            let key = queuedOrder.removeFirst()
            guard let entry = queuedWrites.removeValue(forKey: key) else { continue }
            pendingWrites += 1
            let version = revision
            let preceding = diskTail
            diskTail = Task {
                await preceding?.value
                defer {
                    pendingWrites -= 1
                    drainQueuedWrites()
                }
                guard version == revision else { return }
                let cutoff = entry.created.addingTimeInterval(-Double(retentionDays) * 86400).timeIntervalSince1970
                await disk?.put(entry.data, key: key, created: entry.created.timeIntervalSince1970, cutoff: cutoff)
            }
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
        queuedWrites.removeAll(); queuedOrder.removeAll()
        let preceding = diskTail
        diskTail = Task { await preceding?.value; await disk?.clear() }
    }
    public func flush() async {
        while let tail = diskTail {
            await tail.value
            if queuedOrder.isEmpty, pendingWrites == 0 { return }
        }
    }
}
