import Foundation

public enum LocalPhrases {
    private static let entries: [(String, String, String)] = [
        ("你好", "Hello", "Halo"),
        ("谢谢", "Thank you", "Terima kasih"),
        ("再见", "Goodbye", "Sampai jumpa"),
        ("早上好", "Good morning", "Selamat pagi"),
        ("晚上好", "Good evening", "Selamat malam"),
        ("晚安", "Good night", "Selamat tidur"),
        ("对不起", "I'm sorry", "Maaf"),
        ("不客气", "You're welcome", "Sama-sama"),
        ("没关系", "It's okay", "Tidak apa-apa"),
        ("请稍等", "Please wait", "Mohon tunggu")
    ]

    public static func lookup(_ text: String, settings: TranslationSettings) -> Translation? {
        guard settings.translationTargets.allSatisfy({ [Language.zh, .en, .id].contains($0) }) else { return nil }
        guard settings.glossary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              settings.tone == "忠实自然，保留原文语气" else { return nil }
        for (chinese, english, indonesian) in entries {
            let values: [(Language, String)] = [(.zh, chinese), (.en, english), (.id, indonesian)]
            if let match = values.first(where: { (settings.source == .auto || settings.source == $0.0) && text.caseInsensitiveCompare($0.1) == .orderedSame }) {
                return Translation(source: match.0, zh: match.0 == .zh ? text : chinese,
                                   en: match.0 == .en ? text : english, id: match.0 == .id ? text : indonesian, note: "")
            }
        }
        return nil
    }
}
