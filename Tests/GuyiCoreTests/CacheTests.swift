import Foundation
import CryptoKit
import GuyiCore

@MainActor
func runCacheTests() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("guyi-cache-tests-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("cache.sqlite")
    var date = Date(timeIntervalSince1970: 1_700_000_000)
    var settings = TranslationSettings()
    settings.source = .zh
    settings.enabledLanguages = [.en]
    let key = TranslationCache.key(text: "测试", settings: settings)
    let result = try OpenAITranslator.decode(response(text: "测试"))
    let cache = TranslationCache(diskURL: url, now: { date })
    try check(settings.effectiveCacheDays == 7, "Default retention is seven days")
    cache.put(result, key: key, languages: [.en])
    await cache.flush()
    let stored = cache.get(key)
    try check(stored?.en == "Hello" && stored?.id == "" && stored?.zh == "", "Cache stores only enabled translated language, not other language or source")
    let reopened = TranslationCache(diskURL: url, now: { date })
    let persisted = await reopened.getPersisted(key)
    try check(persisted?.en == "Hello", "Disk translation survives cache instance restart")
    date.addTimeInterval(86400)
    let nextDay = await reopened.getPersisted(key)
    try check(nextDay?.en == "Hello", "The same translation remains cached on the next day")
    date.addTimeInterval(-86400)
    var multilingual = settings
    multilingual.enabledLanguages = [.en, .id]
    let multilingualResult = Translation(source: .zh, zh: "", en: "Hello", id: "Halo", note: "")
    cache.putReusable(multilingualResult, text: "测试", settings: multilingual)
    await cache.flush()
    try check(cache.reusable(text: "测试", settings: multilingual)?.en == "Hello" &&
              cache.reusable(text: "测试", settings: multilingual)?.id == "Halo",
              "Completed target languages can be reused after target-set changes")
    let persistedLanguages = await reopened.persistedReusable(text: "测试", settings: multilingual)
    try check(persistedLanguages?.id == "Halo",
              "Per-language cache survives restart")
    multilingual.model = "different-model"
    try check(cache.reusable(text: "测试", settings: multilingual)?.en == "Hello",
              "Completed translations are reusable after switching models")
    try check(TranslationCache.key(text: "测试", settings: settings, credential: "account-a") !=
              TranslationCache.key(text: "测试", settings: settings, credential: "account-b"),
              "Accounts using the same endpoint and model cannot share cached text")
    let legacyURL = directory.appendingPathComponent("legacy.sqlite")
    let legacyWriter = TranslationCache(diskURL: legacyURL, now: { date })
    var legacySettings = TranslationSettings()
    legacySettings.source = .zh; legacySettings.enabledLanguages = [.en]; legacySettings.model = "old-model"
    let oldValues: [String: String] = ["version": "7",
        "credential": Data(SHA256.hash(data: Data())).base64EncodedString(),
        "protocol": legacySettings.effectiveAPIProtocol.rawValue, "note_language": Localizer.code,
        "text": "旧短句", "endpoint": legacySettings.endpoint, "model": legacySettings.model,
        "source": "zh", "tone": legacySettings.tone, "glossary": "", "targets": "en", "whole_selection": "0"]
    let oldData = try JSONSerialization.data(withJSONObject: oldValues, options: .sortedKeys)
    legacyWriter.put(result, key: Data(SHA256.hash(data: oldData)), languages: [.en])
    await legacyWriter.flush()
    let legacyReader = TranslationCache(diskURL: legacyURL, now: { date })
    legacySettings.model = "new-model"
    legacySettings.cachePreviousModels = ["old-model"]
    let migrated = await legacyReader.persistedReusable(text: "旧短句", settings: legacySettings)
    var oldModelSettings = legacySettings
    oldModelSettings.model = "old-model"
    try check(migrated?.en == "Hello" &&
              TranslationCache.key(text: "旧短句", settings: legacySettings) ==
              TranslationCache.key(text: "旧短句", settings: oldModelSettings),
              "Old model-specific disk entries migrate to a model-independent key")
    let wrongAccount = await legacyReader.persistedReusable(text: "旧短句", settings: legacySettings, credential: "other-account")
    try check(wrongAccount == nil,
              "Migrated legacy translations remain isolated by credential")
    var wrongEndpointSettings = legacySettings
    wrongEndpointSettings.endpoint = "https://other.invalid/v1"
    let wrongEndpoint = await legacyReader.persistedReusable(text: "旧短句", settings: wrongEndpointSettings)
    try check(wrongEndpoint == nil, "Model-independent cache stays isolated by API endpoint")
    var compatibleLegacy = legacySettings
    compatibleLegacy.plainJSONOutput = true
    var compatibleOldValues = oldValues
    compatibleOldValues["text"] = "旧兼容短句"
    compatibleOldValues["plain_json_output"] = "1"
    let compatibleOldData = try JSONSerialization.data(withJSONObject: compatibleOldValues, options: .sortedKeys)
    legacyWriter.put(result, key: Data(SHA256.hash(data: compatibleOldData)), languages: [.en])
    await legacyWriter.flush()
    let compatibleMigrated = await legacyReader.persistedReusable(text: "旧兼容短句", settings: compatibleLegacy)
    try check(compatibleMigrated?.en == "Hello", "Existing compatible-output cache survives the model-independent migration")
    var otherProtocolOldValues = oldValues
    otherProtocolOldValues["text"] = "旧协议短句"
    otherProtocolOldValues["protocol"] = CloudAPIProtocol.chatCompletions.rawValue
    let otherProtocolOldData = try JSONSerialization.data(withJSONObject: otherProtocolOldValues, options: .sortedKeys)
    legacyWriter.put(result, key: Data(SHA256.hash(data: otherProtocolOldData)), languages: [.en])
    await legacyWriter.flush()
    let otherProtocolMigrated = await legacyReader.persistedReusable(text: "旧协议短句", settings: legacySettings)
    try check(otherProtocolMigrated?.en == "Hello", "Old cache survives a model and API protocol switch")
    var transitionalValues = oldValues
    transitionalValues["version"] = "8"
    transitionalValues.removeValue(forKey: "model")
    transitionalValues["plain_json_output"] = "0"
    transitionalValues["text"] = "过渡缓存短句"
    let transitionalData = try JSONSerialization.data(withJSONObject: transitionalValues, options: .sortedKeys)
    legacyWriter.put(result, key: Data(SHA256.hash(data: transitionalData)), languages: [.en])
    await legacyWriter.flush()
    var switchedProtocol = legacySettings
    switchedProtocol.apiProtocol = .chatCompletions
    let transitionalMigrated = await legacyReader.persistedReusable(text: "过渡缓存短句", settings: switchedProtocol)
    try check(transitionalMigrated?.en == "Hello", "Model-independent transitional cache survives the protocol-independent migration")
    date.addTimeInterval(7 * 86400)
    try check(cache.get(key) == nil, "Memory TTL expires at boundary")
    let expired = await reopened.getPersisted(key)
    try check(expired == nil, "Disk TTL expires at boundary without sliding on reads")
    cache.configure(days: 15)
    cache.put(result, key: key, languages: [.en])
    await cache.flush()
    date.addTimeInterval(8 * 86400)
    try check(cache.get(key) != nil, "User-selected fifteen-day retention")
    cache.configure(days: 7)
    await cache.flush()
    let shortened = await cache.getPersisted(key)
    try check(shortened == nil, "Shortening retention applies to existing entries")
    cache.put(result, key: key, languages: [.en])
    let oldRevision = cache.revision
    cache.clear()
    cache.put(result, key: key, languages: [.en], expectedRevision: oldRevision)
    await cache.flush()
    let cleared = await cache.getPersisted(key)
    try check(cleared == nil, "Clear cancels queued writes and rejects pre-clear response")
    cache.configure(days: 0)
    cache.put(result, key: key, languages: [.en])
    await cache.flush()
    try check(cache.get(key) == nil && cache.memoryBytes == 0 && !FileManager.default.fileExists(atPath: url.path), "Disabled cache removes local DB and avoids writes")
    settings.enabledLanguages = [.id]
    try check(TranslationCache.key(text: "测试", settings: settings) != key && key.count == 32, "Target languages isolated in hashed cache key")
    settings.enabledLanguages = [.en]
    settings.translationCacheDays = 15
    try check(TranslationCache.key(text: "测试", settings: settings) == key, "UI preferences and retention do not invalidate semantic cache key")
    settings.plainJSONOutput = true
    try check(TranslationCache.key(text: "测试", settings: settings) == key,
              "Output transport format does not invalidate translation cache")
    settings.plainJSONOutput = false
    settings.apiProtocol = .chatCompletions
    try check(TranslationCache.key(text: "测试", settings: settings) == key,
              "API protocol does not invalidate translation cache")
    settings.apiProtocol = .responses
    settings.glossary = "test = example"
    try check(TranslationCache.key(text: "测试", settings: settings) != key, "Glossary changes cannot reuse incompatible translation")
    let memory = TranslationCache()
    for index in 0..<1200 {
        let key = TranslationCache.key(text: "sample \(index)", settings: settings)
        memory.put(result, key: key, languages: [.en])
    }
    try check(memory.entryCount == TranslationCache.entryLimit && memory.memoryBytes <= TranslationCache.memoryLimit, "Memory cache enforces entry and byte budgets")
    let burstURL = directory.appendingPathComponent("burst.sqlite")
    let burst = TranslationCache(diskURL: burstURL)
    for index in 0..<24 {
        burst.put(result, key: TranslationCache.key(text: "burst \(index)", settings: settings), languages: [.en])
    }
    await burst.flush()
    let burstReader = TranslationCache(diskURL: burstURL)
    let burstLast = await burstReader.getPersisted(TranslationCache.key(text: "burst 23", settings: settings))
    try check(burstLast?.en == "Hello", "A burst above the disk-write concurrency limit remains persistent")
    let unavailable = TranslationCache(diskURL: URL(fileURLWithPath: "/dev/null/cache.sqlite"))
    let miss = await unavailable.getPersisted(key)
    try check(miss == nil, "Database failure safely becomes a cache miss")
    await reopened.flush()
}
