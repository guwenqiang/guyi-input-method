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
        precondition(reopened.saved.profiles.first(where: { $0.id == ServiceProfile.profileID(endpoint: openai.endpoint, protocol: openai.effectiveAPIProtocol) })?.apiKey == "fixture-a-new")
        precondition(reopened.saved.profiles.first(where: { $0.id == ServiceProfile.profileID(endpoint: ark.endpoint, protocol: ark.effectiveAPIProtocol) })?.apiKey == "fixture-b")
        let secondAccount = UUID().uuidString
        try await store.remember(settings: openai, key: "fixture-second", name: "Second account", id: secondAccount)
        let independent = ServiceProfiles(file: file)
        precondition(independent.saved.profiles.count == 3)
        precondition(independent.saved.profiles.first(where: { $0.id == secondAccount })?.apiKey == "fixture-second")
        precondition(independent.saved.profiles.first(where: { $0.id == ServiceProfile.profileID(endpoint: openai.endpoint, protocol: openai.effectiveAPIProtocol) })?.apiKey == "fixture-a-new")
        try await store.remember(settings: openai, key: "fixture-second-updated", name: "Second account", id: secondAccount)
        precondition(ServiceProfiles(file: file).saved.profiles.count == 3)
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        precondition((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        print("PASS · Concurrent writes, independent same-endpoint accounts, reopen and private permissions")
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
