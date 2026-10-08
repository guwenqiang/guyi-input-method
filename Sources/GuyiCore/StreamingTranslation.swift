import Foundation

public protocol StreamingTranslating: Translating {
    func stream(_ text: String, settings: TranslationSettings, apiKey: String,
                progress: @escaping @Sendable ([String: String]) async -> Void) async throws -> Translation
}

public enum TranslationPreview {
    public static func partialFields(in json: String) -> [String: String] {
        var values = fields(in: json)
        let pattern = "\"(" + Language.targets.map(\.rawValue).joined(separator: "|") + #")"\s*:\s*"((?:[^"\\]|\\.)*)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return values }
        let string = json as NSString
        guard let match = regex.firstMatch(in: json, range: NSRange(location: 0, length: string.length)) else { return values }
        let language = string.substring(with: match.range(at: 1))
        var partial = string.substring(with: match.range(at: 2))
        // A chunk can end inside a Unicode escape or surrogate pair. Display only
        // the decodable prefix; it remains unselectable until response validation.
        for _ in 0..<13 {
            if let value = try? JSONDecoder().decode(String.self, from: Data(("\"" + partial + "\"").utf8)) {
                if !value.isEmpty { values[language] = value }
                break
            }
            guard !partial.isEmpty else { break }
            partial.removeLast()
        }
        return values
    }
    public static func fields(in json: String) -> [String: String] {
        let pattern = "\"(" + Language.targets.map(\.rawValue).joined(separator: "|") + #")"\s*:\s*"((?:[^"\\]|\\.)*)""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [:] }
        let string = json as NSString
        var fields: [String: String] = [:]
        for match in regex.matches(in: json, range: NSRange(location: 0, length: string.length)) {
            let literal = "\"" + string.substring(with: match.range(at: 2)) + "\""
            if let value = try? JSONDecoder().decode(String.self, from: Data(literal.utf8)), !value.isEmpty {
                fields[string.substring(with: match.range(at: 1))] = value
            }
        }
        return fields
    }
}

public struct ResponseStream {
    private var text = ""
    private let languages: [Language]
    public init(languages: [Language] = [.zh, .en, .id]) { self.languages = languages }
    public mutating func consume(_ data: Data) throws -> (preview: [String: String], completed: Translation?) {
        guard let event = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = event["type"] as? String else { throw TranslationError.invalidResponse }
        switch type {
        case "response.output_text.delta":
            text += event["delta"] as? String ?? ""
            guard text.utf8.count < 256_000 else { throw TranslationError.invalidResponse }
            return (TranslationPreview.partialFields(in: text), nil)
        case "response.completed":
            guard let response = event["response"] as? [String: Any] else { throw TranslationError.invalidResponse }
            return ([:], try OpenAITranslator.decode(JSONSerialization.data(withJSONObject: response), languages: languages))
        case "response.refusal.delta", "response.refusal.done": throw TranslationError.refused
        case "response.incomplete", "response.failed", "error": throw TranslationError.incomplete
        default: return ([:], nil)
        }
    }
}

extension OpenAITranslator {
    public func stream(_ text: String, settings: TranslationSettings, apiKey: String,
                       progress: @escaping @Sendable ([String: String]) async -> Void) async throws -> Translation {
        if settings.effectiveAPIProtocol != .responses {
            return try await translate(text, settings: settings, apiKey: apiKey)
        }
        var request = try request(text, settings: settings, apiKey: apiKey)
        var body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        body["stream"] = true
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let response = response as? HTTPURLResponse else { throw TranslationError.invalidResponse }
            guard (200..<300).contains(response.statusCode) else {
                var errorBody = Data()
                for try await byte in bytes {
                    try Task.checkCancellation()
                    errorBody.append(byte)
                    if errorBody.count > 16_384 { break }
                }
                throw ProviderTransport.responseError(status: response.statusCode, body: errorBody)
            }
            if response.mimeType == "application/json" {
                var data = Data()
                for try await byte in bytes {
                    try Task.checkCancellation()
                    data.append(byte)
                    guard data.count < 512_000 else { throw TranslationError.invalidResponse }
                }
                return preserve(try Self.decode(data, languages: settings.translationTargets), original: text, source: settings.source, wholeSelection: settings.translateWholeSelection == true)
            }
            var stream = ResponseStream(languages: settings.translationTargets)
            var eventLines: [String] = []
            var eventSize = 0
            var lineBytes = Data()
            for try await byte in bytes {
                try Task.checkCancellation()
                if byte != 10 {
                    lineBytes.append(byte)
                    guard lineBytes.count < 512_000 else { throw TranslationError.invalidResponse }
                    continue
                }
                if lineBytes.last == 13 { lineBytes.removeLast() }
                let line = String(decoding: lineBytes, as: UTF8.self)
                lineBytes.removeAll(keepingCapacity: true)
                if line.isEmpty {
                    guard !eventLines.isEmpty else { continue }
                    let payload = eventLines.joined(separator: "\n")
                    eventLines.removeAll(keepingCapacity: true)
                    eventSize = 0
                    if payload == "[DONE]" { break }
                    let update = try stream.consume(Data(payload.utf8))
                    if let completed = update.completed { return preserve(completed, original: text, source: settings.source, wholeSelection: settings.translateWholeSelection == true) }
                    if !update.preview.isEmpty { await progress(update.preview) }
                } else if line.hasPrefix("data:") {
                    let value = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                    eventSize += value.utf8.count
                    guard eventSize < 512_000 else { throw TranslationError.invalidResponse }
                    eventLines.append(value)
                }
            }
            if !eventLines.isEmpty, eventLines.joined() != "[DONE]" {
                let update = try stream.consume(Data(eventLines.joined(separator: "\n").utf8))
                if let completed = update.completed { return preserve(completed, original: text, source: settings.source, wholeSelection: settings.translateWholeSelection == true) }
            }
            throw TranslationError.incomplete
        } catch is CancellationError { throw CancellationError() }
        catch let error as TranslationError { throw error }
        catch {
            if Task.isCancelled { throw CancellationError() }
            throw TranslationError.network
        }
    }

    private func preserve(_ result: Translation, original: String, source: Language, wholeSelection: Bool) -> Translation {
        if wholeSelection { return result }
        let source = source == .auto ? result.source : source
        return Translation(source: source, zh: source == .zh ? original : result.zh,
                           en: source == .en ? original : result.en, id: source == .id ? original : result.id, note: result.note, additional: result.additional).restoringOriginal(original)
    }
}
