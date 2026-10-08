import Foundation
import GuyiCore

@main struct ProfileSmoke {
    @MainActor static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("guyi-profiles-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("profiles.json")
        let store = ServiceProfiles(file: file)
        var openai = TranslationSettings(); openai.endpoint = "https://api.openai.com/v1"; openai.model = "fixture-old"
        var ark = TranslationSettings(); ark.endpoint = "https://ark.cn-beijing.volces.com/api/v3"; ark.model = "ep-fixture"
        let firstOpenAI = openai, firstArk = ark
        async let a: Void = store.remember(settings: firstOpenAI, key: "fixture-a")
        async let b: Void = store.remember(settings: firstArk, key: "fixture-b")
        try await a; try await b
        precondition(store.saved.profiles.count == 2, "Overlapping writes cannot lose another service")
        openai.model = "fixture-new"
        try await store.remember(settings: openai, key: "fixture-a-new")
        let reopened = ServiceProfiles(file: file)
        precondition(reopened.saved.profiles.count == 2)
        precondition(reopened.saved.profiles.first(where: { $0.id == "openai" })?.apiKey == "fixture-a-new")
        precondition(reopened.saved.profiles.first(where: { $0.id == "ark" })?.apiKey == "fixture-b")
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        precondition((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        print("PASS · Concurrent service writes, latest-only replacement, reopen and private file permissions")
        let target = root.appendingPathComponent("untouched.txt")
        try Data("untouched".utf8).write(to: target)
        let link = root.appendingPathComponent("symlink.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let linkedStore = ServiceProfiles(file: link)
        do { try await linkedStore.remember(settings: openai, key: "fixture-only"); fatalError("Followed a symlink") }
        catch { let untouched = try String(contentsOf: target, encoding: .utf8); precondition(untouched == "untouched") }
        print("PASS · Profile persistence rejects symlink targets")
    }
}
