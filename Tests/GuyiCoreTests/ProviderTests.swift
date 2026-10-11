import Foundation
import GuyiCore

func runProviderTests() throws {
    var settings = TranslationSettings()
    settings.endpoint = "https://example.invalid/v1"
    settings.model = ""
    let modelsURL = try settings.validatedBaseURL().appendingPathComponent("models")
    try check(modelsURL.path == "/v1/models",
              "Model list address is valid before a model ID is selected")
    do {
        _ = try settings.validatedURL()
        throw Failure.check("Translation accepted an empty model ID")
    } catch TranslationError.configuration { print("PASS · Translation still requires a model ID") }
    settings.model = "fixture-model"
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
    settings.apiProtocol = .responses
    settings.plainJSONOutput = true
    let compatible = try OpenAITranslator().request("请确认明天的安排。", settings: settings, apiKey: "fixture-only")
    let compatibleBody = try JSONSerialization.jsonObject(with: compatible.httpBody!) as! [String: Any]
    try check(compatibleBody["text"] == nil && (compatibleBody["instructions"] as? String)?.contains("raw JSON object") == true,
              "Compatible Responses omits unsupported format parameters but requires JSON fields")
    settings.apiProtocol = .chatCompletions
    let compatibleChat = try OpenAITranslator().request("请确认明天的安排。", settings: settings, apiKey: "fixture-only")
    let compatibleChatBody = try JSONSerialization.jsonObject(with: compatibleChat.httpBody!) as! [String: Any]
    try check(compatibleChatBody["response_format"] == nil,
              "Compatible Chat Completions omits unsupported response_format")
}
