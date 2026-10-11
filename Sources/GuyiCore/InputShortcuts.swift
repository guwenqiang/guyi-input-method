import Foundation

public struct InputShortcut: Codable, Equatable {
    public var key: UInt32
    public var modifiers: UInt32
    public var enabled: Bool
    public init(key: UInt32, modifiers: UInt32, enabled: Bool = true) {
        self.key = key; self.modifiers = modifiers; self.enabled = enabled
    }
    public func matches(key: UInt32, modifiers: UInt32) -> Bool {
        enabled && self.key < 128 && self.key == key && self.modifiers == modifiers
    }
}

public enum InputShortcuts {
    public static func translationAction(_ language: Language) -> String {
        "translate" + language.rawValue.prefix(1).uppercased() + language.rawValue.dropFirst()
    }
    public static func translationLanguage(_ action: String) -> Language? {
        Language.targets.first { translationAction($0) == action }
    }
    public static let actions = ["toggleNativeEnglish", "cycleLanguage", "cycleLanguageAlternate", "inputJapanese", "inputKorean", "sentenceMode", "toggleSelectionTranslation", "emoji"]
        + Language.targets.map(translationAction) + ["previousCandidates", "nextCandidates"]
        + (0...9).map { "copyContent\($0)" } + (0...9).map { "pasteContent\($0)" }
    public static func defaultBinding(_ action: String) -> InputShortcut {
        switch action {
        case "toggleNativeEnglish": return .init(key: 37, modifiers: 4096 | 2048)
        case "emoji": return .init(key: 49, modifiers: 256 | 4096)
        case "cycleLanguage": return .init(key: 29, modifiers: 2048)
        case "cycleLanguageAlternate": return .init(key: 49, modifiers: 4096 | 512)
        case "inputJapanese": return .init(key: 38, modifiers: 4096 | 2048)
        case "inputKorean": return .init(key: 40, modifiers: 4096 | 2048)
        case "sentenceMode": return .init(key: 36, modifiers: 4096 | 2048)
        case "toggleSelectionTranslation": return .init(key: 17, modifiers: 4096 | 2048)
        case "translateZh": return .init(key: 18, modifiers: 2048)
        case "translateEn": return .init(key: 19, modifiers: 2048)
        case "translateId": return .init(key: 20, modifiers: 2048)
        case "previousCandidates": return .init(key: 27, modifiers: 0)
        case "nextCandidates": return .init(key: 24, modifiers: 0)
        default:
            let digits: [UInt32] = [29, 18, 19, 20, 21, 23, 22, 26, 28, 25]
            guard let digit = action.last?.wholeNumberValue, action.hasPrefix("copyContent") || action.hasPrefix("pasteContent") else { return .init(key: UInt32.max, modifiers: 0, enabled: false) }
            return .init(key: digits[digit], modifiers: 4096 | 2048 | (action.hasPrefix("paste") ? 512 : 0))
        }
    }
    public static func binding(_ action: String, settings: TranslationSettings) -> InputShortcut {
        settings.inputShortcuts?[action] ?? defaultBinding(action)
    }
    public static func action(key: UInt32, modifiers: UInt32, settings: TranslationSettings, hasCandidates: Bool) -> String? {
        actions.first {
            if ["previousCandidates", "nextCandidates"].contains($0), !hasCandidates { return false }
            return binding($0, settings: settings).matches(key: key, modifiers: modifiers)
        }
    }
    public static func conflicts(settings: TranslationSettings) -> [String] {
        var seen: [String: String] = [:], result: [String] = []
        for action in actions {
            let binding = binding(action, settings: settings)
            guard binding.enabled, binding.key < 128 else { continue }
            let id = "\(binding.key):\(binding.modifiers)"
            if let other = seen[id] { result.append(other + " / " + action) }
            seen[id] = action
        }
        return result
    }
    public static func display(_ action: String, settings: TranslationSettings) -> String {
        let value = binding(action, settings: settings)
        guard value.enabled, value.key < 128 else { return "" }
        let symbols: [(UInt32, String)] = [(4096, "⌃"), (2048, "⌥"), (512, "⇧"), (256, "⌘")]
        let prefix = symbols.filter { value.modifiers & $0.0 != 0 }.map(\.1).joined()
        let names: [UInt32: String] = [0:"A",1:"S",2:"D",3:"F",4:"H",5:"G",6:"Z",7:"X",8:"C",9:"V",11:"B",12:"Q",13:"W",14:"E",15:"R",16:"Y",17:"T",18:"1",19:"2",20:"3",21:"4",22:"6",23:"5",24:"=",25:"9",26:"7",27:"-",28:"8",29:"0",30:"]",31:"O",32:"U",33:"[",34:"I",35:"P",36:"↩",37:"L",38:"J",39:"'",40:"K",41:";",42:"\\",43:",",44:"/",45:"N",46:"M",47:".",48:"⇥",49:"Space",50:"`",51:"⌫"]
        return prefix + (names[value.key] ?? "Key \(value.key)")
    }
    public static func title(_ action: String) -> String {
        switch action {
        case "toggleNativeEnglish": return "切换常用输入语言与英文"
        case "emoji": return "表情与符号"
        case "cycleLanguage": return "循环输入语言"
        case "cycleLanguageAlternate": return "切换原文语言（备用）"
        case "inputJapanese": return "切换日语输入"
        case "inputKorean": return "切换韩语输入"
        case "sentenceMode": return "切换整句模式"
        case "toggleSelectionTranslation": return "暂停或恢复划词与复制翻译"
        case "translateZh": return "插入中文译文"
        case "translateEn": return "插入英文译文"
        case "translateId": return "插入印尼语译文"
        case "previousCandidates": return "上一组候选"
        case "nextCandidates": return "下一组候选"
        default:
            if let language = translationLanguage(action) { return Localizer.format("插入%@译文", language.title) }
            return (action.hasPrefix("copy") ? "复制常用内容 " : "粘贴常用内容 ") + String(action.suffix(1))
        }
    }
}
