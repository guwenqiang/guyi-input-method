import Foundation

public enum EmojiCandidates {
    private static let pinyin: [String: [String]] = [
        "haha": ["😂", "😄"], "hahaha": ["😂", "🤣"], "xiao": ["😄"],
        "kaixin": ["😄", "🥳"], "weixiao": ["😊"], "ku": ["😭"],
        "nanguo": ["😢"], "shengqi": ["😠"], "xiexie": ["🙏"],
        "zan": ["👍"], "aixin": ["❤️"], "xihuan": ["❤️"],
        "guzhang": ["👏"], "jiayou": ["💪"], "qingzhu": ["🎉"],
        "shengri": ["🎂"], "haode": ["👌"], "zaijian": ["👋"],
        "kafei": ["☕"], "meigui": ["🌹"], "baoqian": ["🙏"]
    ]
    private static let english: [String: [String]] = [
        "haha": ["😂", "😄"], "laugh": ["😂"], "smile": ["😊"],
        "thanks": ["🙏"], "thankyou": ["🙏"], "love": ["❤️"],
        "birthday": ["🎂"], "coffee": ["☕"], "bye": ["👋"],
        "sad": ["😢"], "angry": ["😠"], "celebrate": ["🎉"]
    ]
    private static let indonesian: [String: [String]] = [
        "haha": ["😂", "😄"], "tertawa": ["😂"], "senyum": ["😊"],
        "makasih": ["🙏"], "terimakasih": ["🙏"], "cinta": ["❤️"],
        "ulangtahun": ["🎂"], "kopi": ["☕"], "dadah": ["👋"],
        "sedih": ["😢"], "marah": ["😠"], "semangat": ["💪"]
    ]
    private static let japanese: [String: [String]] = [
        "warai": ["😂"], "egao": ["😊"], "arigatou": ["🙏"],
        "suki": ["❤️"], "tanjoubi": ["🎂"], "koohii": ["☕"],
        "sayonara": ["👋"], "kanashii": ["😢"], "ganbatte": ["💪"]
    ]
    private static let korean: [String: [String]] = [
        "하하": ["😂"], "웃음": ["😄"], "감사": ["🙏"], "고마워": ["🙏"],
        "사랑": ["❤️"], "생일": ["🎂"], "커피": ["☕"],
        "안녕": ["👋"], "슬퍼": ["😢"], "화나": ["😠"], "화이팅": ["💪"]
    ]
    public static func matches(_ text: String, language: Language) -> [String] {
        let normalized = text.lowercased().filter { !$0.isWhitespace && $0 != "'" }
        switch language {
        case .zh: return pinyin[LearnedPhrases.normalized(text)] ?? []
        case .en: return english[normalized] ?? []
        case .id: return indonesian[normalized] ?? []
        case .ja: return japanese[normalized] ?? []
        case .ko: return korean[normalized] ?? []
        default: return []
        }
    }
    public static func matches(_ pinyin: String) -> [String] {
        matches(pinyin, language: .zh)
    }
}
