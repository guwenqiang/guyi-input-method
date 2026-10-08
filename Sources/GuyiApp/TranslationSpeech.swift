import AppKit
import AVFoundation
import Combine
import GuyiCore

@MainActor
final class TranslationSpeech: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    static let shared = TranslationSpeech()
    @Published private(set) var language: Language?
    @Published private(set) var spokenText = ""
    @Published private(set) var status = ""
    private let synthesizer = AVSpeechSynthesizer()
    private var current: AVSpeechUtterance?
    override init() { super.init(); synthesizer.delegate = self }
    static func locale(_ language: Language) -> String {
        [Language.zh:"zh-CN",.en:"en-US",.id:"id-ID",.ja:"ja-JP",.ko:"ko-KR",.es:"es-ES",.fr:"fr-FR",.de:"de-DE",.pt:"pt-BR",.ru:"ru-RU",.ar:"ar-SA",.hi:"hi-IN",.th:"th-TH",.vi:"vi-VN"][language] ?? language.rawValue
    }
    func voice(for language: Language) -> AVSpeechSynthesisVoice? {
        AVSpeechSynthesisVoice(language: Self.locale(language))
    }
    func toggle(_ text: String, language: Language) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if self.language == language, spokenText == text { stop(); return }
        stop()
        guard let voice = voice(for: language) else { status = Localizer.text("此语言语音尚不可用"); return }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        current = utterance
        self.language = language
        spokenText = text
        status = ""
        synthesizer.speak(utterance)
    }
    func stop() {
        current = nil
        synthesizer.stopSpeaking(at: .immediate)
        language = nil
        spokenText = ""
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) { Task { @MainActor in self.finish(utterance) } }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) { Task { @MainActor in self.finish(utterance) } }
    private func finish(_ utterance: AVSpeechUtterance) {
        guard current === utterance else { return }
        current = nil; language = nil; spokenText = ""
    }
}
