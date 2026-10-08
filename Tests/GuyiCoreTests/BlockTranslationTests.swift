import Foundation
import GuyiCore

func testBlockTranslation() async throws {
    let settings = TranslationSettings()
    let blocks = ["Please check the number.", "Do not pay twice."]
    let request = try OpenAIBlockTranslator().request(blocks, target: .id, settings: settings, apiKey: "fixture")
    let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
    let input = try JSONSerialization.jsonObject(with: Data((body["input"] as! String).utf8)) as! [String: Any]
    let sent = input["blocks"] as! [[String: Any]]
    try check(sent.count == 2 && sent[0]["text"] as? String == blocks[0] && sent[1]["id"] as? Int == 1, "Screenshot blocks share one request with stable IDs")
    try check(input["target_language"] as? String == "id", "Screenshot batch requests only selected language")
    try check(body["store"] as? Bool == false, "Screenshot batch disables provider storage")
    func envelope(_ blocks: [[String: Any]], status: String = "completed") throws -> Data {
        let text = String(decoding: try JSONSerialization.data(withJSONObject: ["translations": blocks]), as: UTF8.self)
        return try JSONSerialization.data(withJSONObject: ["status": status, "output": [["content": [["type": "output_text", "text": text]]]]])
    }
    let valid = try envelope([["id": 1, "text": "Jangan membayar dua kali."], ["id": 0, "text": "Periksa nomornya."]])
    let reordered = try OpenAIBlockTranslator.decode(valid, count: 2)
    try check(reordered == ["Periksa nomornya.", "Jangan membayar dua kali."], "Out-of-order screenshot responses map back to original rectangles")
    for invalid: [[String: Any]] in [
        [["id": 0, "text": "first"], ["id": 0, "text": "duplicate"]],
        [["id": 0, "text": "missing"]],
        [["id": -1, "text": "invalid"], ["id": 1, "text": "second"]],
        [["id": 0, "text": "first"], ["id": 2, "text": "outside"]],
        [["id": 0, "text": "first"], ["id": 1, "text": "  "]]
    ] {
        do { _ = try OpenAIBlockTranslator.decode(envelope(invalid), count: 2); throw Failure.check("Invalid screenshot mapping") }
        catch is TranslationError { print("PASS · Reject invalid screenshot block mapping") }
    }
    do { _ = try OpenAIBlockTranslator.decode(envelope([], status: "incomplete"), count: 2); throw Failure.check("Incomplete screenshot response") }
    catch TranslationError.incomplete { print("PASS · Incomplete screenshot output cannot be displayed") }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockURLProtocol.self]
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }
    MockURLProtocol.status = 200
    MockURLProtocol.data = valid
    let translated = try await OpenAIBlockTranslator(session: session).translate(blocks, target: .id, settings: settings, apiKey: "fixture")
    try check(translated == reordered, "Screenshot batch network flow preserves region order")
}
