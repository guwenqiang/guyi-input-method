import AppKit
import GuyiCore

@MainActor
final class HotwordStore {
    static let shared = HotwordStore()
    func configure(enabled: Bool) {}
}

@MainActor
final class ScreenshotService {
    static let shared = ScreenshotService()
    func configure(enabled: Bool, key: UInt32, modifiers: UInt32) {}
}

@main
struct PreferencesUpgradeSmoke {
    @MainActor static func main() async throws {
        let suite = "app.guyi.upgrade-fixture." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var settings = TranslationSettings()
        precondition(settings.translateSelection != false, "Selection translation is enabled by default")
        settings.selectionLanguages = [.en, .ja]
        settings.translateSelection = false
        settings.endpoint = "http://127.0.0.1:12345/v1"
        settings.model = "fixture-model"
        settings.enabledLanguages = [.zh, .id, .ja]
        settings.translationCacheDays = 15
        settings.screenshotKey = 8
        let data = try JSONEncoder().encode(settings)
        defaults.set(data, forKey: "translationSettings")
        defaults.set(true, forKey: "configured")
        defaults.set(true, forKey: "realtimeInputMigration")
        let original = Preferences(defaults: defaults, readCredential: { .available("fixture-not-a-real-key") })
        precondition(original.settings == settings && original.apiKey == "fixture-not-a-real-key")
        let updated = Preferences(defaults: defaults, readCredential: { .locked })
        precondition(updated.settings == settings && updated.configured)
        precondition(defaults.data(forKey: "translationSettings") == data)
        precondition(updated.keyStatus.contains("现有文件未被修改"))
        let unlocked = Preferences(defaults: defaults, readCredential: { .available("fixture-not-a-real-key") })
        precondition(unlocked.apiKey == original.apiKey && unlocked.settings == original.settings)
        precondition(unlocked.settings.selectionLanguages == [.en, .ja] && unlocked.settings.translateSelection == false,
                     "Disabling selection translation preserves its independent target languages")
        unlocked.saveSelectionLanguages([.fr, .id])
        let selectionReload = Preferences(defaults: defaults, readCredential: { .available("fixture-not-a-real-key") })
        precondition(selectionReload.settings.selectionLanguages == [.id, .fr] && selectionReload.settings.translateSelection == false)
        precondition(selectionReload.settings.enabledLanguages == settings.enabledLanguages,
                     "Selection targets do not overwrite input translation targets")
        defaults.set(data, forKey: "translationSettings")
        unlocked.toggleSentenceMode()
        precondition(unlocked.settings.sentenceComposition == true)
        precondition(unlocked.apiKey == original.apiKey && unlocked.settings.endpoint == settings.endpoint)
        let toggled = Preferences(defaults: defaults, readCredential: { .available("fixture-not-a-real-key") })
        precondition(toggled.settings.sentenceComposition == true)
        toggled.toggleSentenceMode()
        precondition(toggled.settings.sentenceComposition == false)
        defaults.set(data, forKey: "translationSettings")
        print("PASS · Sentence quick toggle persists without changing credentials or provider settings")
        var previousLocal = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        previousLocal["backend"] = "local"
        defaults.set(try JSONSerialization.data(withJSONObject: previousLocal), forKey: "translationSettings")
        let withdrawn = Preferences(defaults: defaults, readCredential: { .available("fixture-not-a-real-key") })
        precondition(!withdrawn.settings.automatic && withdrawn.settings.translateClipboard == false)
        defaults.set(data, forKey: "translationSettings")
        var changedProvider = settings
        changedProvider.apiProtocol = .anthropic
        do { try await original.save(changedProvider, key: ""); fatalError("Old key was reused for a new provider") }
        catch TranslationError.missingKey {}
        precondition(original.apiKey == "fixture-not-a-real-key" && original.settings == settings)
        print("PASS · Removed local mode does not silently upload; provider change requires an explicit key")
        let missing = Preferences(defaults: defaults, readCredential: { .missing })
        precondition(missing.settings == settings)
        print("PASS · Upgrade preserves endpoint, model, languages, shortcut, TTL and configured state")
        print("PASS · Locked credentials are distinguished from missing; stored settings remain untouched")
        print("PASS · Existing local credential reloads without re-entry")
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("guyi-local-credential-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try LocalCredential.save("fixture-local-key", directory: folder)
        let file = folder.appendingPathComponent("credentials.json")
        let permissions = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as! NSNumber
        precondition(permissions.intValue == 0o600)
        if case .available(let key) = LocalCredential.readResult(directory: folder) { precondition(key == "fixture-local-key") }
        else { fatalError("Local credential did not persist") }
        let before = try Data(contentsOf: file)
        do { try LocalCredential.save("", directory: folder); fatalError("Empty write must be rejected") } catch {}
        let after = try Data(contentsOf: file)
        precondition(after == before)
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: folder.appendingPathComponent("target.json"))
        do { try LocalCredential.save("replacement", directory: folder); fatalError("Symlink write must be rejected") } catch {}
        print("PASS · Local credential persistence, 0600 permissions, empty-write and symlink protection")
    }
}
