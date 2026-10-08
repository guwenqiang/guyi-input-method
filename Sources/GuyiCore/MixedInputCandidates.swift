import Foundation

public enum MixedInputCandidates {
    // Deliberately excludes ambiguous pinyin such as shi, wo, an, ai, can and men.
    // Matching is local, bounded, and never sends unfinished keystrokes to a model.
    private static let words: Set<String> = Set("""
    ok okay yes no hello hi hey bye goodbye thanks thank please sorry welcome
    good morning night today tomorrow yesterday meeting email mail work home
    office team project plan review approve approved pending done cancel save
    open close copy paste delete update download upload file folder browser
    computer phone keyboard mouse screen screenshot password login logout
    account settings search test debug build code commit branch merge pull push
    github git swift python javascript java typescript html css json sql api
    http https url wifi usb mac windows linux iphone ipad android apple google
    chatgpt openai gpt ai sorry happy birthday love nice great cool fine sure
    true false null undefined return function class import export print
    issue bug fix todo readme markdown docker kubernetes server client
    weekend lunch dinner coffee tea water food hotel airport flight ticket
    english chinese translation translate language message text video audio
    pdf excel word powerpoint outlook slack zoom wechat
    """.split(whereSeparator: \.isWhitespace).map(String.init)).subtracting(["ai", "shi", "wo", "an", "can", "men"])
    public static func preferredEnglish(_ raw: String) -> String? {
        guard raw.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) }),
              words.contains(raw.lowercased()) else { return nil }
        return raw
    }
}
