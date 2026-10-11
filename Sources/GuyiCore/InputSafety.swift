import Foundation

public enum InputSafety {
    public static func englishText(_ text: String?, capsLock: Bool, shift: Bool) -> String? {
        guard let text, capsLock, !text.isEmpty,
              text.unicodeScalars.allSatisfy({ $0.isASCII && CharacterSet.letters.contains($0) }) else { return text }
        return shift ? text.uppercased() : text.lowercased()
    }
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

    public static func allowsLocalComposition(bundleIdentifier: String?) -> Bool {
        !bypassInputMethod(bundleIdentifier: bundleIdentifier) &&
            !SensitiveContentPolicy.protectedApplication(bundleIdentifier)
    }


    public static func capsUsesSystemInputSource(bundleIdentifier: String?) -> Bool {
        bundleIdentifier == "com.google.Chrome"
    }

    public static func spaceCommitsSentence(language: Language, sentenceMode: Bool, hasPreedit: Bool, draft: String) -> Bool {
        language == .zh && sentenceMode && !hasPreedit && !draft.isEmpty
    }
}
