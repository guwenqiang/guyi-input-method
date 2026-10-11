import Foundation

public enum ProviderTransport {
    public static func responseError(status: Int, body: Data) -> TranslationError {
        if body.count <= 16_384,
           let root = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
           let error = root["error"] as? [String: Any], error["code"] as? String == "ModelNotOpen" {
            return .modelNotEnabled
        }
        return .http(status)
    }
    public static func adapt(_ canonical: URLRequest, settings: TranslationSettings, apiKey: String) throws -> URLRequest {
        guard settings.effectiveAPIProtocol != .responses else { return canonical }
        guard let data = canonical.httpBody,
              let body = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let instructions = body["instructions"] as? String,
              let input = body["input"] as? String else { throw TranslationError.configuration }
        let format = (body["text"] as? [String: Any])?["format"] as? [String: Any]
        let schema = format?["schema"] as? [String: Any]
        guard settings.plainJSONOutput == true || schema != nil else { throw TranslationError.configuration }
        var request = canonical
        let base = try settings.validatedURL().deletingLastPathComponent()
        var adapted: [String: Any]
        switch settings.effectiveAPIProtocol {
        case .responses: return canonical
        case .anthropic:
            guard let schema else { throw TranslationError.configuration }
            request.url = base.appendingPathComponent("messages")
            request.setValue(nil, forHTTPHeaderField: "Authorization")
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            adapted = ["model": settings.model, "max_tokens": body["max_output_tokens"] ?? 8192,
                       "system": instructions, "messages": [["role": "user", "content": input]],
                       "tools": [["name": "guyi_result", "description": "Return the requested structured result. No external action is performed.", "input_schema": schema]],
                       "tool_choice": ["type": "tool", "name": "guyi_result", "disable_parallel_tool_use": true]]
        case .chatCompletions:
            request.url = base.appendingPathComponent("chat/completions")
            adapted = ["model": settings.model, "max_completion_tokens": body["max_output_tokens"] ?? 8192,
                       "messages": [["role": "system", "content": instructions], ["role": "user", "content": input]]]
            if let schema, settings.plainJSONOutput != true {
                adapted["response_format"] = ["type": "json_schema", "json_schema":
                    ["name": format?["name"] ?? "guyi_result", "strict": true, "schema": schema]]
            }
        }
        if settings.effectiveAPIProtocol == .chatCompletions, let reasoning = body["reasoning"] as? [String: String] {
            adapted["reasoning_effort"] = reasoning["effort"]
        }
        if settings.effectiveAPIProtocol == .chatCompletions, let thinking = body["thinking"] {
            adapted["thinking"] = thinking
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: adapted)
        return request
    }

    public static func normalize(_ data: Data, protocol kind: CloudAPIProtocol) throws -> Data {
        guard data.count <= 1_048_576 else { throw TranslationError.invalidResponse }
        guard kind != .responses else { return data }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw TranslationError.invalidResponse }
        let text: String
        switch kind {
        case .responses: return data
        case .anthropic:
            guard root["stop_reason"] as? String != "refusal" else { throw TranslationError.refused }
            guard root["stop_reason"] as? String == "tool_use" else { throw TranslationError.incomplete }
            let content = root["content"] as? [[String: Any]] ?? []
            let results = content.filter { $0["type"] as? String == "tool_use" }
            guard results.count == 1, results[0]["name"] as? String == "guyi_result",
                  let result = results[0]["input"] as? [String: Any] else { throw TranslationError.invalidResponse }
            text = String(decoding: try JSONSerialization.data(withJSONObject: result), as: UTF8.self)
        case .chatCompletions:
            guard let choices = root["choices"] as? [[String: Any]], choices.count == 1,
                  let message = choices[0]["message"] as? [String: Any] else { throw TranslationError.invalidResponse }
            if let refusal = message["refusal"] as? String, !refusal.isEmpty { throw TranslationError.refused }
            guard choices[0]["finish_reason"] as? String == "stop" else { throw TranslationError.incomplete }
            guard let result = message["content"] as? String, !result.isEmpty else { throw TranslationError.invalidResponse }
            text = result
        }
        return try JSONSerialization.data(withJSONObject: ["status": "completed", "output": [["type": "message", "content": [["type": "output_text", "text": text]]]]])
    }
}
