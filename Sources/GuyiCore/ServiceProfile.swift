import Foundation

/// Credentials belong only in the app's protected local configuration file.
/// This type must never be written to UserDefaults or diagnostics.
public struct ServiceProfile: Codable, Identifiable, Equatable {
    public let id: String
    public var endpoint: String
    public var model: String
    public var apiProtocol: CloudAPIProtocol
    public var plainJSONOutput: Bool?
    public var apiKey: String
    public var name: String
    public init(settings: TranslationSettings, key: String, name: String? = nil, id: String? = nil) {
        self.id = id ?? Self.profileID(endpoint: settings.endpoint, protocol: settings.effectiveAPIProtocol)
        endpoint = settings.endpoint
        model = settings.model
        apiProtocol = settings.effectiveAPIProtocol
        plainJSONOutput = settings.plainJSONOutput
        apiKey = key
        let supplied = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.name = supplied.isEmpty ? Self.suggestedName(endpoint: settings.endpoint) : supplied
    }
    private enum CodingKeys: String, CodingKey { case id, endpoint, model, apiProtocol, plainJSONOutput, apiKey, name }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        endpoint = try values.decode(String.self, forKey: .endpoint)
        model = try values.decode(String.self, forKey: .model)
        apiProtocol = try values.decode(CloudAPIProtocol.self, forKey: .apiProtocol)
        plainJSONOutput = try values.decodeIfPresent(Bool.self, forKey: .plainJSONOutput)
        apiKey = try values.decode(String.self, forKey: .apiKey)
        let storedName = try values.decodeIfPresent(String.self, forKey: .name)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        name = storedName.isEmpty ? Self.suggestedName(endpoint: endpoint) : storedName
        let storedID = try values.decodeIfPresent(String.self, forKey: .id) ?? ""
        id = UUID(uuidString: storedID) != nil ? storedID : Self.profileID(endpoint: endpoint, protocol: apiProtocol)
    }
    public static func profileID(endpoint: String, protocol kind: CloudAPIProtocol) -> String {
        guard let url = URLComponents(string: endpoint), let scheme = url.scheme?.lowercased(),
              let host = url.host?.lowercased() else { return "" }
        let path = url.path.isEmpty || url.path == "/" ? "" : url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return kind.rawValue + "|" + scheme + "://" + host + (url.port.map { ":\($0)" } ?? "") + (path.isEmpty ? "" : "/" + path)
    }
    public static func identity(endpoint: String) -> String {
        guard let url = URL(string: endpoint), let host = url.host?.lowercased() else { return "" }
        func domain(_ root: String) -> Bool { host == root || host.hasSuffix("." + root) }
        if domain("openai.com") { return "openai" }
        if domain("anthropic.com") { return "anthropic" }
        if domain("volces.com") { return "ark" }
        return (url.scheme?.lowercased() ?? "https") + "://" + host + (url.port.map { ":\($0)" } ?? "")
    }
    public static func suggestedName(endpoint: String) -> String {
        switch Self.identity(endpoint: endpoint) {
        case "openai": return "OpenAI"
        case "anthropic": return "Claude / Anthropic"
        case "ark": return "豆包 / 火山方舟"
        default: return URL(string: endpoint)?.host ?? "API"
        }
    }
    public var title: String {
        let host = URL(string: endpoint)?.host ?? "API"
        return name == host ? name : name + " · " + host
    }
    public func applying(to current: TranslationSettings) -> ProviderDrafts.Form {
        var settings = current
        settings.endpoint = endpoint; settings.model = model; settings.apiProtocol = apiProtocol
        settings.plainJSONOutput = plainJSONOutput
        return .init(settings: settings, key: apiKey)
    }
    public var isComplete: Bool {
        var settings = TranslationSettings(); settings.endpoint = endpoint; settings.model = model
        return !id.isEmpty && (UUID(uuidString: id) != nil || id == Self.profileID(endpoint: endpoint, protocol: apiProtocol)) &&
            !name.isEmpty && name.count <= 64 && !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            apiKey.utf8.count <= 16_384 && (try? settings.validatedURL()) != nil
    }
}

public struct ServiceProfileCollection: Codable {
    public private(set) var profiles: [ServiceProfile] = []
    public init() {}
    private enum CodingKeys: String, CodingKey { case profiles }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let decoded = try values.decode([ServiceProfile].self, forKey: .profiles)
        for profile in decoded { remember(profile) }
    }
    public mutating func remember(_ profile: ServiceProfile) {
        guard profile.isComplete else { return }
        profiles.removeAll { $0.id == profile.id }
        profiles.append(profile)
    }
}
