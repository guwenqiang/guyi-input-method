import Foundation
import GuyiCore

func runHangulInputTests() throws {
    var composer = HangulComposer()
    var committed = ""
    for key in "dkssud" {
        guard let update = composer.input(key) else { throw Failure.check("Korean 2-Set rejected a mapped key") }
        committed += update.committed
    }
    try check(committed + composer.commit() == "안녕", "Korean 2-Set composes a word without a system input-source switch")

    composer = HangulComposer()
    for key in "rhk" { _ = composer.input(key) }
    try check(composer.composingText == "과", "Korean compound vowel composes")
    try check(composer.backspace()?.composing == "고" && composer.backspace()?.composing == "ㄱ",
              "Korean Backspace removes the composing jamo, not prior committed text")
    composer.cancel()
    try check(!composer.hasComposition, "Leaving Korean input cancels leftover marked text")
}
