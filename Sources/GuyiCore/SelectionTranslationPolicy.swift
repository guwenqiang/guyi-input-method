import Foundation
import NaturalLanguage

/// Local trigger detection only. The caller always translates the unmodified selection.
public enum SelectionTranslationPolicy {
    private static let addressDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    public static func shouldTranslate(_ text: String, settings: TranslationSettings, interfaceLanguage: String) -> Bool {
        guard text.count <= 4_000, !isNonlinguisticSelection(text) else { return false }
        // Unicode letters, not alphanumerics: numbers, punctuation and emoji alone have no language.
        let letters = text.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        guard !letters.isEmpty else { return false }
        guard settings.skipSameLanguageSelection != false else { return true }
        let familiar = normalized(settings.selectionFamiliarLanguage ?? interfaceLanguage)
        // Split by script as well as sentence boundaries, so an English fragment in
        // an otherwise Chinese paragraph cannot disappear behind the dominant language.
        var segments: [String] = [], current = "", lastScript = ""
        for scalar in text.unicodeScalars {
            let script = scriptOf(scalar)
            if !script.isEmpty {
                if !lastScript.isEmpty && script != lastScript { segments.append(current); current = "" }
                lastScript = script; current.unicodeScalars.append(scalar)
            } else if CharacterSet.newlines.contains(scalar) || ".!?。！？;；".unicodeScalars.contains(scalar) {
                if !current.isEmpty { segments.append(current) }; current = ""; lastScript = ""
            } else { current.append(" ") }
        }
        if !current.isEmpty { segments.append(current) }
        for segment in segments {
            let content = segment.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let first = content.unicodeScalars.first(where: { CharacterSet.letters.contains($0) }) else { continue }
            let script = scriptOf(first)
            if script == "han", familiar == "zh" || familiar == "ja" { continue }
            if script == "kana", familiar == "ja" { continue }
            if script == "hangul", familiar == "ko" { continue }
            if ["zh", "ja", "ko"].contains(familiar) { return true }
            if ["han", "kana", "hangul"].contains(script) { return true }
            let recognizer = NLLanguageRecognizer()
            recognizer.processString(content)
            guard let best = recognizer.languageHypotheses(withMaximum: 3).max(by: { $0.value < $1.value }), best.value >= 0.65 else {
                // Ambiguous short words/names are not proof of foreign language.
                continue
            }
            if normalized(best.key.rawValue) != familiar { return true }
        }
        return false
    }
    public static func isAddressOnly(_ text: String) -> Bool {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !value.contains(where: { $0.isWhitespace }) else { return false }
        if value.range(of: #"(?i)^(?:https?|ftp|sftp|file|mailto|tel|about|data|chrome|chrome-extension|edge|safari|javascript):\S+$"#, options: .regularExpression) != nil { return true }
        guard let detector = addressDetector,
              let match = detector.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) else { return false }
        return match.range == NSRange(value.startIndex..., in: value)
    }
    public static func isNonlinguisticSelection(_ text: String) -> Bool {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if SensitiveContentPolicy.resemblesSecret(value) || isAddressOnly(value) { return true }
        func matches(_ pattern: String) -> Bool { value.range(of: pattern, options: .regularExpression) != nil }
        if matches(#"^(?:/|~/|\./|\.\./|[A-Za-z]:[\\/])[^\n]+$"#) { return true }
        if matches(#"(?i)^(?:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}|[0-9a-f]{24,}|0x[0-9a-f]+)$"#) { return true }
        if matches(#"^\d{4}-\d{2}-\d{2}T[0-9:.+-]+Z?$"#) { return true }
        if matches(#"^(?:sk[-_]|ghp_|github_pat_|AKIA)[A-Za-z0-9_-]{12,}$"#) { return true }
        if matches(#"^eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$"#) { return true }
        // Standalone mixed identifiers are not prose. Keep short natural terms
        // such as B2B/5G available, while excluding device IDs and opaque tokens.
        if matches(#"^(?=.*[A-Z])(?=.*[0-9])[A-Z0-9_-]{6,}$"#) { return true }
        if matches(#"^(?=.*[A-Za-z])(?=.*[0-9])[A-Za-z0-9_-]{12,}$"#) { return true }
        if matches(#"^[A-Z][A-Z0-9]*(?:_[A-Z0-9]+)+$"#) { return true }
        if (value.hasPrefix("{") || value.hasPrefix("[")), let data = value.data(using: .utf8),
           (try? JSONSerialization.jsonObject(with: data)) != nil { return true }
        if value.hasPrefix("```"), value.hasSuffix("```") { return true }
        if matches(#"^(?:const|let|var)\s+[A-Za-z_$][A-Za-z0-9_$]*\s*=.+[;}]$"#) { return true }
        let lines = value.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return lines.count > 1 && lines.allSatisfy { isAddressOnly($0) }
    }
    public static func detectedLanguage(_ text: String) -> Language {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let best = recognizer.languageHypotheses(withMaximum: 2).max(by: { $0.value < $1.value }), best.value >= 0.65 else { return .auto }
        return Language(rawValue: normalized(best.key.rawValue)) ?? .auto
    }
    private static func normalized(_ language: String) -> String {
        language.lowercased().split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map(String.init) ?? language
    }
    private static func scriptOf(_ scalar: Unicode.Scalar) -> String {
        guard CharacterSet.letters.contains(scalar) else { return "" }
        switch scalar.value {
        case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0x20000...0x323AF: return "han"
        case 0x3040...0x30FF, 0x31F0...0x31FF, 0xFF66...0xFF9D: return "kana"
        case 0x1100...0x11FF, 0x3130...0x318F, 0xAC00...0xD7AF: return "hangul"
        case 0x0041...0x024F, 0x1E00...0x1EFF: return "latin"
        case 0x0400...0x052F: return "cyrillic"
        case 0x0600...0x06FF: return "arabic"
        default: return "other"
        }
    }
}
