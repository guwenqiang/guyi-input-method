import Foundation

public struct LearnedPhrases: Codable {
    public struct Entry: Codable { public let pinyin: String; public let text: String; public var count: Int; public var lastUsed: Date }
    public private(set) var entries: [Entry] = []
    public init() {}
    public static func normalized(_ code: String) -> String { code.lowercased().filter { $0 != " " && $0 != "'" } }
    public static func consumedCode(_ raw: String, remaining: String) -> String {
        let raw = normalized(raw), remaining = normalized(remaining)
        guard !remaining.isEmpty, raw.hasSuffix(remaining), raw.count > remaining.count else { return raw }
        return String(raw.dropLast(remaining.count))
    }
    public static func validObservation(_ code: String, text: String) -> Bool {
        !code.isEmpty && code.count <= 64 && code.utf8.allSatisfy { (97...122).contains($0) } &&
        code.last.map { "aeioungr".contains($0) } == true &&
        (1...8).contains(text.count) && text.unicodeScalars.allSatisfy { (0x3400...0x9fff).contains($0.value) }
    }
    public static func valid(_ code: String, text: String) -> Bool {
        validObservation(code, text: text) && text.count >= 2
    }
    public mutating func record(code: String, text: String, now: Date = Date()) {
        let code = Self.normalized(code)
        guard Self.valid(code, text: text) else { return }
        if let i=entries.firstIndex(where: { $0.pinyin == code && $0.text == text }) {
            entries[i].count=min(10000,entries[i].count+1);entries[i].lastUsed=now
        } else { entries.append(.init(pinyin:code,text:text,count:1,lastUsed:now)) }
        compact()
    }
    public mutating func compact() {
        entries.removeAll { !Self.valid($0.pinyin, text: $0.text) }
        guard entries.count > 2048 else { return }
        let established = entries.filter { $0.count >= 2 }.sorted {
            $0.count == $1.count ? $0.lastUsed > $1.lastUsed : $0.count > $1.count
        }
        let pending = entries.filter { $0.count < 2 }.sorted { $0.lastUsed > $1.lastUsed }
        let keptEstablished = Array(established.prefix(2048))
        entries = keptEstablished + Array(pending.prefix(min(512, 2048 - keptEstablished.count)))
    }
    public func matches(_ code:String) -> [String] {
        let normalized=Self.normalized(code)
        guard !normalized.isEmpty,normalized.utf8.allSatisfy({(97...122).contains($0)}) else{return []}
        return entries.filter { $0.pinyin == normalized && $0.count >= 2 }.sorted {
            $0.count == $1.count ? $0.lastUsed > $1.lastUsed : $0.count > $1.count
        }.prefix(3).map(\.text)
    }
}
