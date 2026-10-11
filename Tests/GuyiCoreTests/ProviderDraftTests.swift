import Foundation
import GuyiCore
func runProviderDraftTests() throws {
    var original = TranslationSettings()
    original.endpoint = "https://example.invalid/v1"
    original.model = "original-model"
    var forms = ProviderDrafts(settings: original, key: "fixture-openai")
    let first = ProviderDrafts.Form(settings: original, key: "fixture-openai")
    var claude = forms.switchingProtocol(to: .anthropic, from: first)
    try check(claude.key.isEmpty, "Protocol change does not reuse credentials")
    claude.settings.endpoint = "https://anthropic.invalid/v1"
    claude.settings.model = "claude-fixture"
    claude.key = "fixture-claude"
    let restored = forms.switchingProtocol(to: .responses, from: claude)
    try check(restored.settings.endpoint == original.endpoint && restored.settings.model == original.model && restored.key == first.key,
              "Protocol round trip restores original endpoint, model and key")
    let again = forms.switchingProtocol(to: .anthropic, from: restored)
    try check(again.settings.endpoint == claude.settings.endpoint && again.key == claude.key,
              "Protocol round trip preserves the other unsaved draft")
    let changed = forms.switchingEndpoint(to: "https://different.invalid/v1", from: restored)
    try check(changed.key.isEmpty, "New destination cannot receive previous service key")
    let returned = forms.switchingEndpoint(to: original.endpoint, from: changed)
    try check(returned.key == first.key && returned.settings.model == first.settings.model, "Returning to original URL restores its form")
    let newService = ProviderDrafts.Form(settings: original, key: "")
    let sameAddress = forms.switchingEndpoint(to: original.endpoint, from: newService, reuseSaved: false)
    try check(sameAddress.key.isEmpty, "New service at a saved protocol and address never inherits its old API key")
    let sameProtocol = forms.switchingProtocol(to: .responses, from: sameAddress, reuseSaved: false)
    try check(sameProtocol.key.isEmpty && forms.switchingEndpoint(to: original.endpoint, from: changed).key == first.key,
              "New service edits do not overwrite the existing saved draft")
    let ark = forms.switchingService(to: "ark", endpoint: "https://ark.cn-beijing.volces.com/api/v3", kind: .responses, from: returned)
    try check(ark.key.isEmpty && ark.settings.model.isEmpty, "New provider template starts without unrelated credentials")
    let back = forms.switchingService(to: "openai", endpoint: "https://api.openai.com/v1", kind: .responses, from: ark)
    try check(back.settings.endpoint == original.endpoint && back.key == first.key && back.settings.model == original.model,
              "OpenAI template restores configured custom OpenAI endpoint")
    var profiles = ServiceProfileCollection()
    var a = TranslationSettings(); a.endpoint = "https://api.openai.com/v1"; a.model = "old-model"
    profiles.remember(.init(settings: a, key: "fixture-a"))
    var c = a; c.endpoint = "https://api.anthropic.com/v1"; c.apiProtocol = .anthropic; c.model = "claude-fixture"
    profiles.remember(.init(settings: c, key: "fixture-c"))
    var d = a; d.endpoint = "https://ark.cn-beijing.volces.com/api/v3"; d.model = "ep-fixture"
    profiles.remember(.init(settings: d, key: "fixture-d"))
    a.apiProtocol = .chatCompletions; a.model = "new-model"
    profiles.remember(.init(settings: a, key: "fixture-a-new"))
    try check(profiles.profiles.count == 4, "Different protocols at one endpoint retain separate service profiles")
    a.model = "latest-model"
    profiles.remember(.init(settings: a, key: "fixture-a-latest"))
    try check(profiles.profiles.count == 4, "Saving one protocol and endpoint replaces only that service")
    var second = a; second.endpoint = "https://other.example/v1"; second.model = "other-model"
    profiles.remember(.init(settings: second, key: "fixture-other", name: "Team gateway"))
    try check(profiles.profiles.count == 5, "Several services sharing one protocol remain selectable")
    let independentID = UUID().uuidString
    var independent = a; independent.model = "independent-model"
    profiles.remember(.init(settings: independent, key: "fixture-independent", name: "Second account", id: independentID))
    try check(profiles.profiles.count == 6 && profiles.profiles.first(where: { $0.id == independentID })?.name == "Second account",
              "The same protocol and endpoint can hold an independent named account")
    profiles.remember(.init(settings: independent, key: "fixture-updated", name: "Second account", id: independentID))
    try check(profiles.profiles.count == 6 && profiles.profiles.first(where: { $0.id == independentID })?.apiKey == "fixture-updated" &&
              profiles.profiles.first(where: { $0.id == ServiceProfile.profileID(endpoint: a.endpoint, protocol: a.effectiveAPIProtocol) })?.apiKey == "fixture-a-latest",
              "Editing one named account preserves the other account at the same endpoint")
    try check(profiles.profiles.first(where: { $0.id == ServiceProfile.profileID(endpoint: second.endpoint, protocol: second.effectiveAPIProtocol) })?.title == "Team gateway · other.example",
              "Saved service picker shows the user name and host")
    let restoredProfiles = try JSONDecoder().decode(ServiceProfileCollection.self, from: JSONEncoder().encode(profiles))
    var compatibleSettings = a
    compatibleSettings.plainJSONOutput = true
    let compatibleProfile = try JSONDecoder().decode(ServiceProfile.self,
        from: JSONEncoder().encode(ServiceProfile(settings: compatibleSettings, key: "fixture-compatible")))
    try check(compatibleProfile.applying(to: TranslationSettings()).settings.plainJSONOutput == true,
              "Compatible JSON output choice survives service profile storage and selection")
    try check(restoredProfiles.profiles.first(where: { $0.id == ServiceProfile.profileID(endpoint: a.endpoint, protocol: a.effectiveAPIProtocol) })?.model == "latest-model", "Same-service edits overwrite the old model")
    try check(restoredProfiles.profiles.first(where: { $0.id == ServiceProfile.profileID(endpoint: d.endpoint, protocol: d.effectiveAPIProtocol) })?.apiKey == "fixture-d", "Changing another service preserves the Doubao credential")
    var appearance = TranslationSettings(); appearance.candidateTheme = "light"; appearance.selectionLanguages = [.ja, .es]
    let selected = restoredProfiles.profiles.first(where: { $0.id == ServiceProfile.profileID(endpoint: c.endpoint, protocol: c.effectiveAPIProtocol) })!.applying(to: appearance)
    try check(selected.settings.candidateTheme == "light" && selected.settings.selectionLanguages == [.ja, .es], "Service switch retains global appearance and language preferences")
    try check(selected.key == "fixture-c" && selected.settings.effectiveAPIProtocol == .anthropic, "Service switch restores its matching credential and protocol together")
    try check(ServiceProfile.identity(endpoint: "https://api.openai.com.attacker.invalid/v1") != "openai", "Provider identity requires a real domain boundary")
    profiles.remember(.init(settings: a, key: ""))
    try check(profiles.profiles.first(where: { $0.id == ServiceProfile.profileID(endpoint: a.endpoint, protocol: a.effectiveAPIProtocol) })?.apiKey == "fixture-a-latest", "Incomplete form cannot erase an existing complete service profile")
    let legacy = #"{"profiles":[{"id":"openai","endpoint":"https://api.openai.com/v1","model":"old","apiProtocol":"responses","apiKey":"fixture-legacy"},{"id":"ark","endpoint":"https://ark.cn-beijing.volces.com/api/v3","model":"ep-old","apiProtocol":"responses","apiKey":"fixture-ark"}]}"#
    let migrated = try JSONDecoder().decode(ServiceProfileCollection.self, from: Data(legacy.utf8))
    try check(migrated.profiles.count == 2 &&
              migrated.profiles.contains(where: { $0.id == ServiceProfile.profileID(endpoint: "https://api.openai.com/v1", protocol: .responses) && $0.apiKey == "fixture-legacy" && $0.name == "OpenAI" }) &&
              migrated.profiles.contains(where: { $0.id == ServiceProfile.profileID(endpoint: "https://ark.cn-beijing.volces.com/api/v3", protocol: .responses) && $0.apiKey == "fixture-ark" && !$0.name.isEmpty }),
              "Legacy provider profiles gain editable names without losing model or credential")
    let providerError = ProviderTransport.responseError(status: 404, body: Data(#"{"error":{"code":"ModelNotOpen","message":"private-account-details"}}"#.utf8))
    if case .modelNotEnabled = providerError { print("PASS · Inactive provider model gets an actionable message without server account details") }
    else { throw Failure.check("Model activation error incorrectly reported as bad endpoint") }

}
