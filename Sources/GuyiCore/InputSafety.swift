import Foundation

public enum InputSafety {
    public static func candidatePageDirection(_ text: String, language: Language, hasPreedit: Bool) -> Bool? {
        guard language == .zh, hasPreedit else { return nil }
        if text == "=" { return true }
        if text == "-" { return false }
        return nil
    }
    public static func insertsWithoutComposition(_ text: String, hasComposition: Bool) -> Bool {
        !hasComposition && !text.isEmpty && text.rangeOfCharacter(from: .letters) == nil
    }
    public static func allowsClientAccess(active: Bool, currentController: Bool, hasClient: Bool,
                                          sessionHostPID: Int32?, foregroundPID: Int32?) -> Bool {
        guard active, currentController, hasClient, let sessionHostPID, let foregroundPID else { return false }
        return sessionHostPID == foregroundPID
    }
    public static func returnCommitsRaw(language: Language, rawInput: String, selectedTranslation: Bool, clipboard: Bool) -> Bool {
        language == .zh && !rawInput.isEmpty && !selectedTranslation && !clipboard
    }
    public static func bypassInputMethod(bundleIdentifier: String?) -> Bool {
        bundleIdentifier == "app.guyi.inputmethod.Guyi" || bundleIdentifier == "app.guyi.launcher"
    }

    public static func spaceCommitsSentence(language: Language, sentenceMode: Bool, hasPreedit: Bool, draft: String) -> Bool {
        language == .zh && sentenceMode && !hasPreedit && !draft.isEmpty
    }
}
