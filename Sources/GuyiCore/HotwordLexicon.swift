import Foundation

public struct HotwordEntry: Codable, Equatable {
    public let text: String
    public let pinyin: String
}

public enum HotwordLexicon {
    public static func parse(_ content: String) throws -> [HotwordEntry] {
        guard content.utf8.count <= 2_000_000 else { throw TranslationError.invalidResponse }
        var entries: [HotwordEntry] = []
        var seen: Set<String> = []
        for line in content.split(whereSeparator: \.isNewline) {
            guard !line.hasPrefix("#") else { continue }
            let columns = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard columns.count >= 2 else { continue }
            let word = String(columns[0])
            let syllables = columns[1].lowercased().split(separator: " ")
            let pinyin = syllables.joined()
            guard (2...32).contains(word.count), !pinyin.isEmpty, pinyin.count <= 128,
                  word.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }),
                  pinyin.utf8.allSatisfy({ (97...122).contains($0) }), seen.insert(word).inserted else { continue }
            entries.append(HotwordEntry(text: word, pinyin: pinyin))
            if entries.count >= 20_000 { break }
        }
        guard !entries.isEmpty else { throw TranslationError.invalidResponse }
        return entries
    }
}
