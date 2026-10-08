import AppKit
import SwiftUI
import GuyiCore

@main
struct LearningUISmoke {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let model = CandidateModel()
        model.original = "你好"
        model.candidates = ["你好", "拟好", "你", "妳", "尼"]
        model.expanded = true
        model.lessonLanguage = .en
        model.translation.update(text: "你好", composing: false, settings: TranslationSettings(), apiKey: "")
        let data = Data(#"{"structure":"Hello 是问候语。","points":["可单独作为一句问候。"],"register":"日常、自然","example":"Hello, Lin! 你好，林！","ipa":"/həˈloʊ/","pronunciation":"第二音节重读；结尾是双元音 /oʊ/。","vocabulary":[{"word":"Hello","ipa":"/həˈloʊ/","meaning":"你好"}]}"#.utf8)
        model.lesson = try JSONDecoder().decode(GrammarLesson.self, from: data)
        let host = NSHostingView(rootView: CandidateView(model: model, translation: model.translation))
        let size = host.fittingSize
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { fatalError("Cannot render") }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: ".build/learning-preview.png"))
        print("PASS · Learning panel renders \(Int(size.width)) × \(Int(size.height))")
    }
}
