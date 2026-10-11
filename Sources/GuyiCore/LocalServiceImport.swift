import Foundation

public enum LocalServiceImport {
    public enum Source: String {
        case codex
        case claudeCode
    }

    public enum ImportError: LocalizedError {
        case unavailable, unsupportedAuthentication, unsupportedEndpoint, invalidFile

        public var errorDescription: String? {
            switch self {
            case .unavailable: Localizer.text("未找到可导入的 API Key；订阅或 OAuth 登录不能用作模型 API Key。")
            case .unsupportedAuthentication: Localizer.text("本机配置不是 API Key 登录，不能导入订阅凭据。")
            case .unsupportedEndpoint: Localizer.text("本机服务的 API 地址或协议不受支持，请手动核对配置。")
            case .invalidFile: Localizer.text("本机服务配置无法安全读取，请检查文件权限与格式。")
            }
        }
    }

    public static func load(_ source: Source, current: TranslationSettings,
                            home: URL = FileManager.default.homeDirectoryForCurrentUser) throws -> ProviderDrafts.Form {
        switch source {
        case .codex:
            let auth = try json(at: home.appendingPathComponent(".codex/auth.json"))
            guard ["apikey", "api_key"].contains(auth["auth_mode"] as? String ?? "") else {
                throw ImportError.unsupportedAuthentication
            }
            let key = try credential(auth["OPENAI_API_KEY"])
            var settings = current
            settings.apiProtocol = .responses
            settings.endpoint = "https://api.openai.com/v1"
            settings.model = TranslationSettings().model
            if let data = try readData(at: home.appendingPathComponent(".codex/config.toml"), limit: 262_144, required: false),
               let toml = String(data: data, encoding: .utf8) {
                let fields = tomlFields(toml)
                let provider = fields[""]?["model_provider"] ?? "openai"
                if let configured = fields["model_providers." + provider] {
                    guard configured["requires_openai_auth"] == "true",
                          configured["wire_api"] == "responses",
                          let base = configured["base_url"] else { throw ImportError.unsupportedAuthentication }
                    settings.endpoint = try endpoint(base)
                } else if provider.lowercased() != "openai" {
                    throw ImportError.unsupportedEndpoint
                }
                if let model = fields[""]?["model"], !model.isEmpty { settings.model = model }
            }
            return .init(settings: settings, key: key)
        case .claudeCode:
            let config = try json(at: home.appendingPathComponent(".claude/settings.json"))
            let environment = config["env"] as? [String: Any] ?? [:]
            let key = try credential(environment["ANTHROPIC_API_KEY"])
            var settings = current
            settings.apiProtocol = .anthropic
            settings.endpoint = try endpoint((environment["ANTHROPIC_BASE_URL"] as? String) ?? "https://api.anthropic.com/v1")
            let model = (environment["ANTHROPIC_MODEL"] as? String) ?? (config["model"] as? String) ?? ""
            settings.model = validClaudeModel(model) || (URL(string: settings.endpoint)?.host != "api.anthropic.com" && !model.isEmpty)
                ? model : "claude-haiku-4-5-20251001"
            return .init(settings: settings, key: key)
        }
    }

    private static func credential(_ value: Any?) throws -> String {
        guard let value = value as? String else { throw ImportError.unavailable }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.utf8.count <= 16_384 else { throw ImportError.unavailable }
        return trimmed
    }

    private static func validClaudeModel(_ value: String) -> Bool {
        value.hasPrefix("claude-") && value.count <= 100 &&
            value.unicodeScalars.allSatisfy { CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-").contains($0) }
    }

    private static func endpoint(_ text: String) throws -> String {
        guard var components = URLComponents(string: text),
              ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
              let url = components.url,
              url.host != nil, url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil else { throw ImportError.unsupportedEndpoint }
        if components.path.isEmpty || components.path == "/" { components.path = "/v1" }
        guard let normalized = components.url else { throw ImportError.unsupportedEndpoint }
        return normalized.absoluteString
    }

    private static func tomlFields(_ text: String) -> [String: [String: String]] {
        var sections: [String: [String: String]] = [:]
        var section = ""
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("["), let end = line.firstIndex(of: "]") {
                section = String(line[line.index(after: line.startIndex)..<end])
                continue
            }
            guard section.isEmpty || section.hasPrefix("model_providers."),
                  let separator = line.firstIndex(of: "=") else { continue }
            let name = line[..<separator].trimmingCharacters(in: .whitespaces)
            let rawValue = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
            let value: String?
            if rawValue == "true" || rawValue.hasPrefix("true #") { value = "true" }
            else if rawValue == "false" || rawValue.hasPrefix("false #") { value = "false" }
            else { value = tomlString(rawValue) }
            if let value { sections[section, default: [:]][name] = value }
        }
        return sections
    }

    private static func tomlString(_ text: String) -> String? {
        guard let quote = text.first, quote == "\"" || quote == "'" else { return nil }
        var escaped = false
        for index in text.indices.dropFirst() {
            let character = text[index]
            if quote == "\"", character == "\\", !escaped { escaped = true; continue }
            if character == quote, !escaped {
                let value = String(text[...index])
                if quote == "'" { return String(value.dropFirst().dropLast()) }
                return (try? JSONSerialization.jsonObject(with: Data(("[" + value + "]").utf8)))
                    .flatMap { ($0 as? [String])?.first }
            }
            escaped = false
        }
        return nil
    }

    private static func json(at url: URL) throws -> [String: Any] {
        let data = try readData(at: url, limit: 65_536, required: true)!
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ImportError.invalidFile
        }
        return object
    }

    private static func readData(at url: URL, limit: Int, required: Bool) throws -> Data? {
        let values: URLResourceValues
        do { values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]) }
        catch { if !required { return nil }; throw ImportError.unavailable }
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size > 0, size <= limit else { throw ImportError.invalidFile }
        do {
            let data = try Data(contentsOf: url)
            guard data.count <= limit else { throw ImportError.invalidFile }
            return data
        } catch { throw ImportError.invalidFile }
    }
}
