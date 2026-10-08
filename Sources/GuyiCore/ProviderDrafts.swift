import Foundation

/// Unsaved provider forms remain in memory; keys are never stored in preferences.
public struct ProviderDrafts {
    public struct Form {
        public var settings: TranslationSettings
        public var key: String
        public init(settings: TranslationSettings, key: String) { self.settings = settings; self.key = key }
    }
    private var forms: [String: Form] = [:]
    private var protocols: [CloudAPIProtocol: String] = [:]
    private var services: [String: String] = [:]
    public init(settings: TranslationSettings, key: String) { remember(Form(settings: settings, key: key)) }
    private func identity(_ settings: TranslationSettings) -> String {
        settings.effectiveAPIProtocol.rawValue + "|" + settings.endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private func service(_ settings: TranslationSettings) -> String {
        let host = URL(string: settings.endpoint)?.host ?? ""
        if host.contains("volces.com") { return "ark" }
        if settings.effectiveAPIProtocol == .anthropic { return "claude" }
        return "openai"
    }
    public mutating func remember(_ form: Form, service named: String? = nil) {
        let id = identity(form.settings)
        forms[id] = form
        protocols[form.settings.effectiveAPIProtocol] = id
        services[named ?? service(form.settings)] = id
    }
    public mutating func switchingProtocol(to kind: CloudAPIProtocol, from current: Form) -> Form {
        remember(current)
        if let id = protocols[kind], let previous = forms[id] { return previous }
        var settings = current.settings
        settings.apiProtocol = kind
        return Form(settings: settings, key: "")
    }
    public mutating func switchingEndpoint(to endpoint: String, from current: Form) -> Form {
        remember(current)
        var settings = current.settings
        settings.endpoint = endpoint
        return forms[identity(settings)] ?? Form(settings: settings, key: "")
    }
    public mutating func switchingService(to name: String, endpoint: String, kind: CloudAPIProtocol, from current: Form) -> Form {
        remember(current)
        if let id = services[name], let previous = forms[id] { return previous }
        var settings = current.settings
        settings.endpoint = endpoint
        settings.apiProtocol = kind
        settings.model = ""
        return Form(settings: settings, key: "")
    }
}
