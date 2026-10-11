import Foundation
import GuyiCore
func runLearnedPhraseTests() throws {
    var store=LearnedPhrases()
    store.record(code:"gu yi",text:"古一")
    try check(store.matches("guyi").isEmpty,"One adjacent phrase observation does not override candidates")
    store.record(code:"gu'yi",text:"古一")
    try check(store.matches("guyi").first=="古一","Repeated chosen phrase is promoted for its Pinyin")
    let restored=try JSONDecoder().decode(LearnedPhrases.self,from:JSONEncoder().encode(store))
    try check(restored.matches("guyi").first=="古一","User phrase survives local persistence")
    try check(restored.matches("gu").isEmpty,"Learned phrase is matched only to the complete Pinyin")
    store.record(code:"guyi",text:"故意")
    store.record(code:"guyi",text:"故意")
    store.record(code:"guyi",text:"故意")
    try check(store.matches("guyi").first=="故意","Selection frequency adjusts learned ranking")
    for text in ["abc","3,444","API-Key", "你好！", "这是超过八个汉字的句子"] {
        try check(!LearnedPhrases.valid("guyi",text:text),"Nonphrase content is not added to user vocabulary")
    }
    try check(!LearnedPhrases.valid("gu", text: "古"), "Single characters stay in Rime learning instead of filling phrase memory")
    try check(LearnedPhrases.validObservation("gu", text: "古") &&
              LearnedPhrases.validObservation("yi", text: "一") &&
              LearnedPhrases.consumedCode("guyi", remaining: "yi") == "gu",
              "Single-character selections can form a phrase using only consumed Pinyin")
    var combined = LearnedPhrases()
    combined.record(code: LearnedPhrases.consumedCode("guyi", remaining: "yi"), text: "古")
    combined.record(code: "yi", text: "一")
    try check(combined.matches("guyi").isEmpty,
              "Single characters alone never enter phrase memory without an observed combined selection")
    combined.record(code: "gu" + "yi", text: "古" + "一")
    combined.record(code: "gu" + "yi", text: "古" + "一")
    try check(combined.matches("guyi").first == "古一",
              "Two repeated adjacent character selections promote the combined phrase")
    try check(!LearnedPhrases.valid("qieh", text: "其诶"), "Incomplete trailing Pinyin cannot become a learned phrase")
    try check(LearnedPhrases.valid("qiehuan", text: "切换"), "Complete Pinyin remains learnable")
    for index in 0..<2100 {
        var number = index
        var code = "test"
        for _ in 0..<4 {
            code.append(Character(UnicodeScalar(97 + number % 26)!))
            number /= 26
        }
        store.record(code: code, text: "测试")
    }
    try check(store.matches("guyi").contains("故意"), "Established phrases survive new one-off observations")
    var crowded = LearnedPhrases()
    for index in 0..<1600 {
        var number = index
        var code = "used"
        for _ in 0..<4 {
            code.append(Character(UnicodeScalar(97 + number % 26)!))
            number /= 26
        }
        crowded.record(code: code, text: "常用")
        crowded.record(code: code, text: "常用")
    }
    for index in 0..<600 {
        var number = index
        var code = "new"
        for _ in 0..<3 {
            code.append(Character(UnicodeScalar(97 + number % 26)!))
            number /= 26
        }
        crowded.record(code: code, text: "新词")
    }
    try check(crowded.matches("usedaaaa").first == "常用", "One-off phrases cannot evict established memory")
    try check(!LearnedPhrases.valid("gu1yi",text:"古一"),"Only Pinyin spelling can index learned phrases")
}
