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
    try check(profiles.profiles.count == 3, "Each provider retains one latest configuration rather than a history")
    let restoredProfiles = try JSONDecoder().decode(ServiceProfileCollection.self, from: JSONEncoder().encode(profiles))
    try check(restoredProfiles.profiles.first(where: { $0.id == "openai" })?.model == "new-model", "Same-provider edits overwrite the old model")
    try check(restoredProfiles.profiles.first(where: { $0.id == "ark" })?.apiKey == "fixture-d", "Changing another service preserves the Doubao credential")
    var appearance = TranslationSettings(); appearance.candidateTheme = "light"; appearance.selectionLanguages = [.ja, .es]
    let selected = restoredProfiles.profiles.first(where: { $0.id == "anthropic" })!.applying(to: appearance)
    try check(selected.settings.candidateTheme == "light" && selected.settings.selectionLanguages == [.ja, .es], "Service switch retains global appearance and language preferences")
    try check(selected.key == "fixture-c" && selected.settings.effectiveAPIProtocol == .anthropic, "Service switch restores its matching credential and protocol together")
    try check(ServiceProfile.identity(endpoint: "https://api.openai.com.attacker.invalid/v1") != "openai", "Provider identity requires a real domain boundary")
    profiles.remember(.init(settings: a, key: ""))
    try check(profiles.profiles.first(where: { $0.id == "openai" })?.apiKey == "fixture-a-new", "Incomplete form cannot erase an existing complete provider profile")
    let providerError = ProviderTransport.responseError(status: 404, body: Data(#"{"error":{"code":"ModelNotOpen","message":"private-account-details"}}"#.utf8))
    if case .modelNotEnabled = providerError { print("PASS · Inactive provider model gets an actionable message without server account details") }
    else { throw Failure.check("Model activation error incorrectly reported as bad endpoint") }

}
