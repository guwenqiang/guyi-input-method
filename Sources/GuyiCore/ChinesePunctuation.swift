import Foundation

public enum ChinesePunctuation {
    public static func convert(_ input: String, preceding: Character?) -> String {
        let numeric = preceding?.unicodeScalars.count == 1 && preceding?.unicodeScalars.first.map {
            (0x30...0x39).contains($0.value) || (0xFF10...0xFF19).contains($0.value)
        } == true
        if numeric && [".", ":", ","].contains(input) { return input }
        return [",": "，", ".": "。", "?": "？", "!": "！", ":": "：", ";": "；"][input] ?? input
    }
}
