import Foundation

public enum EmojiCandidates {
    private static let entries: [String: [String]] = [
        "haha": ["😂", "😄"], "hahaha": ["😂", "🤣"], "xiao": ["😄"],
        "kaixin": ["😄", "🥳"], "weixiao": ["😊"], "ku": ["😭"],
        "nanguo": ["😢"], "shengqi": ["😠"], "xiexie": ["🙏"],
        "zan": ["👍"], "aixin": ["❤️"], "xihuan": ["❤️"],
        "guzhang": ["👏"], "jiayou": ["💪"], "qingzhu": ["🎉"],
        "shengri": ["🎂"], "haode": ["👌"], "zaijian": ["👋"],
        "kafei": ["☕"], "meigui": ["🌹"], "baoqian": ["🙏"]
    ]
    public static func matches(_ pinyin: String) -> [String] {
        entries[LearnedPhrases.normalized(pinyin)] ?? []
    }
}
