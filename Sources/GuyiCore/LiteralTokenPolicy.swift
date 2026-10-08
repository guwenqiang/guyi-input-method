import Foundation

public enum LiteralTokenPolicy {
    public static func latinWord(_ text: String) -> String {
        String(text.reversed().prefix { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }.reversed())
    }
    public static func begins(raw: String, selected: String?, precedingLatin: String, punctuation: String) -> Bool {
        let token = precedingLatin + raw
        guard !token.isEmpty, token.count <= 253,
              token.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }) else { return false }
        if punctuation == "@" { return true }
        if punctuation == ":" { return ["http", "https", "ftp", "mailto"].contains(token.lowercased()) }
        guard punctuation == "." else { return false }
        return token.lowercased() == "www" || !raw.isEmpty && selected == raw ||
            raw.isEmpty && !precedingLatin.isEmpty ||
            !precedingLatin.isEmpty && MixedInputCandidates.preferredEnglish(token) != nil
    }
    public static func continues(_ text: String) -> Bool {
        !text.isEmpty && text.allSatisfy {
            $0.isASCII && ($0.isLetter || $0.isNumber || ".-_/:@?&=#%+~".contains($0))
        }
    }
}
