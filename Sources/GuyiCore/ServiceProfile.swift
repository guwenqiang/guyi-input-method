import Foundation

/// Credentials belong only in the app's protected local configuration file.
/// This type must never be written to UserDefaults or diagnostics.
public struct ServiceProfile: Codable, Identifiable, Equatable {
    public let id: String
    public var endpoint: String
    public var model: String
    public var apiProtocol: CloudAPIProtocol
    public var apiKey: String
    public init(settings: TranslationSettings, key: String) {
        id = Self.identity(endpoint: settings.endpoint)
        endpoint = settings.endpoint
        model = settings.model
        apiProtocol = settings.effectiveAPIProtocol
        apiKey = key
    }
    public static func identity(endpoint: String) -> String {
        guard let url = URL(string: endpoint), let host = url.host?.lowercased() else { return "" }
        func domain(_ root: String) -> Bool { host == root || host.hasSuffix("." + root) }
        if domain("openai.com") { return "openai" }
        if domain("anthropic.com") { return "anthropic" }
        if domain("volces.com") { return "ark" }
        return (url.scheme?.lowercased() ?? "https") + "://" + host + (url.port.map { ":\($0)" } ?? "")
    }
    public var title: String {
        switch id {
        case "openai": return "OpenAI"
        case "anthropic": return "Claude / Anthropic"
        case "ark": return "豆包 / 火山方舟"
        default: return URL(string: endpoint)?.host ?? "API"
        }
    }
    public func applying(to current: TranslationSettings) -> ProviderDrafts.Form {
        var settings = current
        settings.endpoint = endpoint; settings.model = model; settings.apiProtocol = apiProtocol
        return .init(settings: settings, key: apiKey)
    }
    public var isComplete: Bool {
        var settings = TranslationSettings(); settings.endpoint = endpoint; settings.model = model
        return !id.isEmpty && id == Self.identity(endpoint: endpoint) && !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            apiKey.utf8.count <= 16_384 && (try? settings.validatedURL()) != nil
    }
}

public struct ServiceProfileCollection: Codable {
    public private(set) var profiles: [ServiceProfile] = []
    public init() {}
    public mutating func remember(_ profile: ServiceProfile) {
        guard profile.isComplete else { return }
        profiles.removeAll { $0.id == profile.id }
        profiles.append(profile)
    }
}
