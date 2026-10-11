import Foundation

public enum ModelCatalog {
    public static func fetch(settings: TranslationSettings, apiKey: String) async throws -> [String] {
        guard !apiKey.isEmpty else { throw TranslationError.missingKey }
        let url = try settings.validatedBaseURL().appendingPathComponent("models")
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        if settings.effectiveAPIProtocol == .anthropic {
            request.setValue(nil, forHTTPHeaderField: "Authorization")
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        }
        let (data, response) = try await NetworkSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw TranslationError.invalidResponse }
        guard (200..<300).contains(response.statusCode) else { throw TranslationError.http(response.statusCode) }
        struct Catalog: Decodable {
            struct Model: Decodable { let id: String }
            let data: [Model]
        }
        return try Array(Set(JSONDecoder().decode(Catalog.self, from: data).data.map(\.id))).sorted()
    }
}
