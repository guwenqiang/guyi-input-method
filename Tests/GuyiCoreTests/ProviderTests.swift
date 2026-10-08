import Foundation
import GuyiCore

func runProviderTests() throws {
    var settings = TranslationSettings()
    settings.endpoint = "https://example.invalid/v1"
    settings.source = .zh
    settings.enabledLanguages = [.en, .id]
    let result: [String: Any] = ["source": "zh", "zh": "你好", "en": "Hello", "id": "Halo", "note": ""]
    settings.apiProtocol = .anthropic
    let claude = try OpenAITranslator().request("你好", settings: settings, apiKey: "fixture-only")
    try check(claude.url?.path == "/v1/messages", "Claude uses Messages endpoint")
    try check(claude.value(forHTTPHeaderField: "Authorization") == nil && claude.value(forHTTPHeaderField: "x-api-key") == "fixture-only",
              "Claude uses isolated protocol authentication")
    let body = try JSONSerialization.jsonObject(with: claude.httpBody!) as! [String: Any]
    try check(body["tools"] != nil && body["tool_choice"] != nil && body["input"] == nil, "Claude receives schema as structured tool result")
    let valid: [String: Any] = ["stop_reason": "tool_use", "content": [["type": "tool_use", "name": "guyi_result", "input": result]]]
    let normalized = try ProviderTransport.normalize(JSONSerialization.data(withJSONObject: valid), protocol: .anthropic)
    let parsed = try OpenAITranslator.decode(normalized, languages: [.en, .id])
    try check(parsed.en == "Hello" && parsed.id == "Halo", "Claude structured result passes shared translation validation")
    do {
        _ = try ProviderTransport.normalize(JSONSerialization.data(withJSONObject: ["stop_reason": "max_tokens", "content": []]), protocol: .anthropic)
        throw Failure.check("Truncated Claude result accepted")
    } catch TranslationError.incomplete { print("PASS · Reject truncated Claude response") }
    settings.apiProtocol = .chatCompletions
    let chat = try OpenAITranslator().request("你好", settings: settings, apiKey: "fixture-only")
    try check(chat.url?.path == "/v1/chat/completions" && chat.value(forHTTPHeaderField: "x-api-key") == nil, "Chat Completions path and auth remain independent")
    let json = String(decoding: try JSONSerialization.data(withJSONObject: result), as: UTF8.self)
    let chatData = try JSONSerialization.data(withJSONObject: ["choices": [["finish_reason": "stop", "message": ["content": json]]]])
    let normalizedChat = try ProviderTransport.normalize(chatData, protocol: .chatCompletions)
    let parsedChat = try OpenAITranslator.decode(normalizedChat, languages: [.en, .id])
    try check(parsedChat.en == "Hello", "Chat Completions result passes shared validation")
    do {
        let refused = try JSONSerialization.data(withJSONObject: ["choices": [["finish_reason": "stop", "message": ["refusal": "No", "content": json]]]])
        _ = try ProviderTransport.normalize(refused, protocol: .chatCompletions)
        throw Failure.check("Refusal accepted")
    } catch TranslationError.refused { print("PASS · Reject compatible-provider refusal") }
    settings.endpoint = "https://ark.cn-beijing.volces.com/api/v3"
    settings.model = "ep-fixture-only"
    for kind in [CloudAPIProtocol.responses, .chatCompletions] {
        settings.apiProtocol = kind
        let ark = try OpenAITranslator().request("请确认明天的安排。", settings: settings, apiKey: "ark-fixture-only")
        try check(ark.url?.path == (kind == .responses ? "/api/v3/responses" : "/api/v3/chat/completions"), "Doubao base URL preserves api/v3 with selected protocol")
        let arkBody = try JSONSerialization.jsonObject(with: ark.httpBody!) as! [String: Any]
        try check(arkBody["model"] as? String == "ep-fixture-only", "Doubao endpoint ID is passed without rewriting")
        try check(arkBody["reasoning"] == nil && arkBody["reasoning_effort"] == nil, "Opaque Doubao endpoint is not assigned OpenAI-specific reasoning settings")
        try check(ark.value(forHTTPHeaderField: "Authorization") == "Bearer ark-fixture-only", "Doubao request uses the explicitly supplied service credential")
    }
    settings.apiProtocol = .anthropic
    let blocks = try OpenAIBlockTranslator().request(["Hello", "Good morning"], target: .id, settings: settings, apiKey: "fixture-only")
    let blockBody = try JSONSerialization.jsonObject(with: blocks.httpBody!) as! [String: Any]
    let tools = blockBody["tools"] as! [[String: Any]]
    let schema = tools[0]["input_schema"] as! [String: Any]
    try check((schema["properties"] as? [String: Any])?["translations"] != nil, "Screenshot block schema adapts to Claude without losing mapping")
}
