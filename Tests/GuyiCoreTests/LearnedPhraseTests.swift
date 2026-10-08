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
    try check(!LearnedPhrases.valid("gu1yi",text:"古一"),"Only Pinyin spelling can index learned phrases")
}
