import Foundation

public enum SentenceBoundary {
    public static func endsSentence(_ text: String) -> Bool {
        guard let last = text.last else { return false }
        return "。？！?!；;".contains(last)
    }
}
