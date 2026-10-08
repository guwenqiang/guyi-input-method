import GuyiCore
func runShortcutTests() throws {
 var s=TranslationSettings()
 try check(Language.targets.allSatisfy { InputShortcuts.actions.contains(InputShortcuts.translationAction($0)) }, "Every target language has a configurable translation shortcut")
 try check(InputShortcuts.translationLanguage("translateJa") == .ja, "Japanese shortcut routes to Japanese")
 try check(!InputShortcuts.defaultBinding("translateJa").enabled, "Additional languages do not claim unassigned default keys")
 s.inputShortcuts=["translateJa":.init(key:38,modifiers:2048)]
 try check(InputShortcuts.action(key:38,modifiers:2048,settings:s,hasCandidates:false)=="translateJa", "Custom Japanese binding is recognized")
 s=TranslationSettings()
 try check(InputShortcuts.conflicts(settings:s).isEmpty,"Default functional shortcuts do not conflict")
 try check(InputShortcuts.action(key:24,modifiers:0,settings:s,hasCandidates:true)=="nextCandidates","Equals pages candidates")
 try check(InputShortcuts.action(key:24,modifiers:0,settings:s,hasCandidates:false)==nil,"Equals remains available for arithmetic when idle")
 s.inputShortcuts=["nextCandidates":.init(key:47,modifiers:2048)]
 try check(InputShortcuts.action(key:47,modifiers:2048,settings:s,hasCandidates:true)=="nextCandidates","Custom candidate shortcut overrides the default")
 try check(InputShortcuts.action(key:24,modifiers:0,settings:s,hasCandidates:true)==nil,"Replaced shortcut no longer fires")
 s.inputShortcuts?["nextCandidates"] = .init(key:47,modifiers:2048,enabled:false)
 try check(InputShortcuts.action(key:47,modifiers:2048,settings:s,hasCandidates:true)==nil,"Disabled shortcut passes through")
 s.inputShortcuts?["nextCandidates"] = .init(key:29,modifiers:2048)
 try check(!InputShortcuts.conflicts(settings:s).isEmpty,"Duplicate functional bindings are rejected")
 s.inputShortcuts=["cycleLanguage":.init(key:21,modifiers:4352)]
 try check(InputShortcuts.conflicts(settings:s).isEmpty,"Hidden screenshot shortcut does not reserve a key")
}
