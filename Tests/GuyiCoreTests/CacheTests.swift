import Foundation
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
    settings.screenshotKey = 99
    settings.translationCacheDays = 15
    try check(TranslationCache.key(text: "测试", settings: settings) == key, "UI preferences and retention do not invalidate semantic cache key")
    settings.glossary = "test = example"
    try check(TranslationCache.key(text: "测试", settings: settings) != key, "Glossary changes cannot reuse incompatible translation")
    let memory = TranslationCache()
    for index in 0..<1200 {
        let key = TranslationCache.key(text: "sample \(index)", settings: settings)
        memory.put(result, key: key, languages: [.en])
    }
    try check(memory.entryCount == TranslationCache.entryLimit && memory.memoryBytes <= TranslationCache.memoryLimit, "Memory cache enforces entry and byte budgets")
    let unavailable = TranslationCache(diskURL: URL(fileURLWithPath: "/dev/null/cache.sqlite"))
    let miss = await unavailable.getPersisted(key)
    try check(miss == nil, "Database failure safely becomes a cache miss")
    await reopened.flush()
}
