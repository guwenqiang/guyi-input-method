import AppKit
import Carbon

final class RawEnterSmoke: NSObject, NSApplicationDelegate {
    let window = NSWindow(contentRect: NSRect(x: 180, y: 180, width: CommandLine.arguments.contains("--wrap") ? 340 : 760, height: 360), styleMask: [.titled, .closable], backing: .buffered, defer: false)
    let editor = NSTextView(frame: NSRect(x: 0, y: 0, width: CommandLine.arguments.contains("--wrap") ? 340 : 760, height: 360))
    func sendKey(_ code: CGKeyCode) {
        if CommandLine.arguments.contains("--external-events") {
            print("TEST_KEY:\(getpid()):\(code)")
            fflush(stdout)
        } else {
            CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true)?.postToPid(getpid())
            CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false)?.postToPid(getpid())
        }
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard (CGSessionCopyCurrentDictionary() as NSDictionary?)?["CGSSessionScreenIsLocked"] as? Bool != true else {
            print("BLOCKED · Screen is locked")
            exit(2)
        }
        editor.isEditable = true
        editor.font = .systemFont(ofSize: 22)
        editor.isHorizontallyResizable = false
        editor.textContainer?.widthTracksTextView = true
        window.title = "GuYi · Return acceptance fixture"
        window.contentView = editor
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(editor)
        NSApp.activate(ignoringOtherApps: true)
        print("CONTEXT SOURCES", editor.inputContext?.keyboardInputSources ?? [])
        print("CONTEXT LOCALES", editor.inputContext?.allowedInputSourceLocales ?? [])
        fflush(stdout)
        if CommandLine.arguments.contains("--select-context") {
            let requested = CommandLine.arguments.first(where: { $0.hasPrefix("--source=") })?.dropFirst("--source=".count)
            editor.inputContext?.selectedKeyboardInputSource = requested.map(String.init) ?? "app.guyi.inputmethod.Guyi.pinyin"
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(8))
            guard NSApp.isActive else { print("BLOCKED · Fixture lost focus"); exit(2) }
            print("SOURCE", editor.inputContext?.selectedKeyboardInputSource ?? "none")
            let reference = CommandLine.arguments.contains("--reference")
            let source = editor.inputContext?.selectedKeyboardInputSource ?? ""
            if CommandLine.arguments.contains("--diagnose-selection") {
                if CommandLine.arguments.contains("--diagnose-tis") {
                    let matches = TISCreateInputSourceList([kTISPropertyInputSourceID as String: "app.guyi.inputmethod.Guyi.pinyin"] as CFDictionary, false).takeRetainedValue() as? [TISInputSource] ?? []
                    if let source = matches.first { print("DIAGNOSTIC TIS STATUS", TISSelectInputSource(source)) }
                }
                for code: CGKeyCode in [45, 34, 4, 0, 31] {
                    sendKey(code)
                    try? await Task.sleep(for: .milliseconds(200))
                }
                let backend = NSRunningApplication.runningApplications(withBundleIdentifier: "app.guyi.inputmethod.Guyi").first?.processIdentifier
                let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
                print("DIAGNOSTIC TEXT", editor.string.debugDescription, "MARKED", editor.hasMarkedText())
                print("DIAGNOSTIC GUYI PANELS", windows.filter { $0[kCGWindowOwnerPID as String] as? Int32 == backend && ($0[kCGWindowLayer as String] as? Int ?? 0) > 0 }.count)
                print("DIAGNOSTIC SOURCE", editor.inputContext?.selectedKeyboardInputSource ?? "none")
                print("DIAGNOSTIC_DONE")
                fflush(stdout)
                exit(0)
            }
            guard reference ? (source.contains("wetype") || source.contains("sogou")) : source.contains("guyi") else { print("BLOCKED · Expected input method not selected"); exit(2) }
            if CommandLine.arguments.contains("--inspect-emoji") {
                let codes = CommandLine.arguments.first(where: { $0.hasPrefix("--emoji-codes=") })?
                    .dropFirst("--emoji-codes=".count).split(separator: ",").compactMap { UInt16($0) }
                    ?? [4, 0, 4, 0]
                let expected = CommandLine.arguments.first(where: { $0.hasPrefix("--expected-emoji=") })?
                    .dropFirst("--expected-emoji=".count).description ?? "😂"
                for code in codes {
                    sendKey(code)
                    try? await Task.sleep(for: .milliseconds(180))
                }
                print("EMOJI_READY", getpid())
                fflush(stdout)
                for _ in 0..<300 {
                    if editor.string == expected, !editor.hasMarkedText() {
                        print("PASS · Emoji candidate explicitly inserted")
                        fflush(stdout)
                        exit(0)
                    }
                    try? await Task.sleep(for: .milliseconds(100))
                }
                print("FAIL · Emoji candidate insertion", editor.string.debugDescription, "MARKED", editor.hasMarkedText())
                exit(1)
            }
            if CommandLine.arguments.contains("--manual-acceptance") {
                let expected = CommandLine.arguments.first(where: { $0.hasPrefix("--expected=") })?.dropFirst("--expected=".count)
                let codes = CommandLine.arguments.first(where: { $0.hasPrefix("--type-codes=") })?
                    .dropFirst("--type-codes=".count).split(separator: ",").compactMap { UInt16($0) } ?? []
                guard !codes.isEmpty else { print("BLOCKED · Missing manual input key codes"); exit(2) }
                for code in codes + (CommandLine.arguments.contains("--with-return") ? [36] : []) {
                    guard NSApp.isActive, window.firstResponder === editor else {
                        print("BLOCKED · Manual input fixture lost focus"); exit(2)
                    }
                    sendKey(code)
                    try? await Task.sleep(for: .milliseconds(180))
                }
                try? await Task.sleep(for: .milliseconds(350))
                guard let expected, editor.string == expected, !editor.hasMarkedText() else {
                    print("FAIL · Manual input", editor.string.debugDescription, "MARKED", editor.hasMarkedText(),
                          "ACTIVE", NSApp.isActive, "FOCUSED", window.firstResponder === editor)
                    exit(1)
                }
                print("PASS · Manual input committed", expected)
                fflush(stdout)
                exit(0)
            }
            if CommandLine.arguments.contains("--inspect-candidate") {
                if CommandLine.arguments.contains("--english-candidate") {
                    for code: CGKeyCode in [13, 31, 15, 40] {
                        sendKey(code)
                        try? await Task.sleep(for: .milliseconds(120))
                    }
                } else { sendKey(45) }
                print("CANDIDATE_READY", getpid())
                fflush(stdout)
                try? await Task.sleep(for: .seconds(30))
                print("PASS · Candidate inspection completed")
                fflush(stdout)
                exit(0)
            }
            if CommandLine.arguments.contains("--idle-input") {
                for (codes, expected): ([CGKeyCode], String) in [([49], " "), ([43], "，"), ([39], "'"), ([18,47,19], "1.2"), ([20, 47, 18, 21], "3.14"), ([20,43,21,21,21], "3,444")] {
                    editor.string = ""
                    for code in codes {
                        guard NSApp.isActive else { print("BLOCKED · Fixture lost focus"); exit(2) }
                        sendKey(code)
                        try? await Task.sleep(for: .milliseconds(200))
                        let backend = NSRunningApplication.runningApplications(withBundleIdentifier: "app.guyi.inputmethod.Guyi").first?.processIdentifier
                        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
                        let panels = windows.filter { $0[kCGWindowOwnerPID as String] as? Int32 == backend && ($0[kCGWindowLayer as String] as? Int ?? 0) > 0 }
                        guard !editor.hasMarkedText(), panels.isEmpty else { print("FAIL · Idle input opened composition/panel"); exit(1) }
                    }
                    guard editor.string == expected else { print("FAIL · Idle input result", editor.string.debugDescription); exit(1) }
                    print("PASS · Direct input without candidates", expected.debugDescription)
                }
                editor.string = ""
            }
            if CommandLine.arguments.contains("--calculator") {
                for (codes, expected): ([CGKeyCode], String) in [([23,44,23,24,36], "5/5=1"), ([18,44,20,24,36], "1/3=1/3"), ([29,47,18,69,29,47,19,24,36], "0.1+0.2=0.3"), ([20,43,21,21,21,69,18,24,36], "3,444+1=3,445"),
                    ([23,69,23,69,23,69,23,47,18,51,51,24,36], "5+5+5+5=20"),
                    ([23,69,23,69,23,24,36,69,23,24,36], "5+5+5=15+5=20")] {
                    editor.string = ""
                    // An empty-space boundary also clears context from the previous fixture case.
                    sendKey(49)
                    for _ in 0..<20 {
                        if editor.string == " " { break }
                        try? await Task.sleep(for: .milliseconds(50))
                    }
                    guard editor.string == " " else {
                        print("BLOCKED · Calculator fixture boundary was not delivered")
                        exit(2)
                    }
                    editor.string = ""
                    for code in codes {
                        guard NSApp.isActive else { print("BLOCKED · Fixture lost focus"); exit(2) }
                        sendKey(code)
                        try? await Task.sleep(for: .milliseconds(200))
                        if code == 24 {
                            let backend = NSRunningApplication.runningApplications(withBundleIdentifier: "app.guyi.inputmethod.Guyi").first?.processIdentifier
                            let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
                            let heights = windows.filter { $0[kCGWindowOwnerPID as String] as? Int32 == backend && ($0[kCGWindowLayer as String] as? Int ?? 0) > 0 }
                                .compactMap { entry -> CGFloat? in
                                    guard let values = entry[kCGWindowBounds as String] as? [String: Any] else { return nil }
                                    return CGRect(dictionaryRepresentation: values as CFDictionary)?.height
                                }
                            guard let height = heights.first, height <= 260 else {
                                print("FAIL · Calculator panel height", heights,
                                      "TEXT", editor.string.debugDescription, "MARKED", editor.hasMarkedText())
                                exit(1)
                            }
                        }
                    }
                    guard editor.string == expected, !editor.hasMarkedText() else { print("FAIL · Calculator insertion", editor.string.debugDescription); exit(1) }
                    print("PASS · Calculator Return inserts exact result without newline", expected)
                }
                editor.string = ""
            }
            if CommandLine.arguments.contains("--multilingual") {
                for (shortcut, codes, expected): (CGKeyCode, [CGKeyCode], String) in [
                    (38, [45, 34, 4, 31, 45, 5, 31, 49], "にほんご"),
                    (40, [2, 40, 1, 1, 32, 2, 49], "안녕")
                ] {
                    editor.string = ""
                    guard NSApp.isActive, window.firstResponder === editor else {
                        print("BLOCKED · Multilingual fixture lost focus"); exit(2)
                    }
                    let letter = shortcut == 38 ? "j" : "k"
                    guard let shortcutEvent = NSEvent.keyEvent(with: .keyDown, location: .zero,
                        modifierFlags: [.control, .option], timestamp: ProcessInfo.processInfo.systemUptime,
                        windowNumber: window.windowNumber, context: nil, characters: letter,
                        charactersIgnoringModifiers: letter, isARepeat: false, keyCode: shortcut),
                        editor.inputContext != nil else {
                        print("FAIL · Input mode shortcut was not accepted", letter)
                        exit(1)
                    }
                    window.sendEvent(shortcutEvent)
                    try? await Task.sleep(for: .milliseconds(350))
                    for code in codes {
                        guard NSApp.isActive else { print("BLOCKED · Fixture lost focus"); exit(2) }
                        sendKey(code)
                        try? await Task.sleep(for: .milliseconds(160))
                    }
                    guard editor.string == expected else {
                        print("FAIL · Multilingual input", expected, editor.string.debugDescription)
                        exit(1)
                    }
                    print("PASS · GuYi internal input", expected)
                }
                print("PASS · Multilingual fixture completed")
                fflush(stdout)
                exit(0)
            }
            if CommandLine.arguments.contains("--rapid-input") {
                editor.string = ""
                let strokes: [CGKeyCode] = Array(repeating: [45, 34, 4, 0, 31], count: 12).flatMap { $0 }
                for (index, code) in strokes.enumerated() {
                    guard NSApp.isActive else { print("BLOCKED · Rapid fixture lost focus"); exit(2) }
                    sendKey(code)
                    if index == 4 { try? await Task.sleep(for: .milliseconds(350)) }
                    try? await Task.sleep(for: .milliseconds(12))
                }
                try? await Task.sleep(for: .milliseconds(350))
                sendKey(36)
                try? await Task.sleep(for: .milliseconds(500))
                guard editor.string == String(repeating: "nihao", count: 12) else {
                    print("FAIL · Rapid input lost or reordered keys", editor.string.count)
                    exit(1)
                }
                print("PASS · Rapid input preserved 60 Pinyin keystrokes")
                fflush(stdout)
                exit(0)
            }
            if CommandLine.arguments.contains("--selection") {
                let selections = ["Please review this delivery plan before tomorrow.",
                                  "We need confirmation from the supplier today."]
                editor.string = selections.joined(separator: " ")
                window.makeFirstResponder(editor)
                let backend = NSRunningApplication.runningApplications(withBundleIdentifier: "app.guyi.inputmethod.Guyi").first?.processIdentifier
                func frames() -> [CGRect] {
                    let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
                    return windows.filter { $0[kCGWindowOwnerPID as String] as? Int32 == backend &&
                        ($0[kCGWindowLayer as String] as? Int ?? 0) > 0 }
                        .compactMap { ($0[kCGWindowBounds as String] as? [String: Any]).flatMap { CGRect(dictionaryRepresentation: $0 as CFDictionary) } }
                        .filter { $0.width >= 300 }
                }
                for round in 1...2 {
                    guard let range = editor.string.range(of: selections[round - 1]) else {
                        print("FAIL · Selection fixture text missing", round)
                        exit(1)
                    }
                    let location = NSRange(range, in: editor.string).location
                    editor.setSelectedRange(NSRange(location: location, length: selections[round - 1].utf16.count))
                    var observed: [CGRect] = []
                    for _ in 0..<30 {
                        guard NSApp.isActive else { print("BLOCKED · Selection fixture lost focus"); exit(2) }
                        observed += frames()
                        if observed.count >= 4 { break }
                        try? await Task.sleep(for: .milliseconds(100))
                    }
                    guard let first = observed.first, observed.allSatisfy({ $0.height <= 420 && abs($0.minX - first.minX) <= 8 }) else {
                        print("FAIL · Selection panel missing or unstable", round, observed.count)
                        exit(1)
                    }
                    print("PASS · Selection panel appeared near text", round)
                    if round == 1 {
                        sendKey(51)
                        try? await Task.sleep(for: .milliseconds(950))
                        guard frames().isEmpty, !editor.string.contains(selections[0]) else {
                            print("FAIL · Selection panel stayed visible after deleting selected text")
                            exit(1)
                        }
                        print("PASS · Selection panel closed after deleting selected text")
                        continue
                    }
                    NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first?.activate(options: [])
                    try? await Task.sleep(for: .milliseconds(650))
                    guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder" else {
                        print("BLOCKED · Finder did not become foreground for selection regression")
                        exit(2)
                    }
                    guard frames().isEmpty else {
                        print("FAIL · Selection panel remained visible while another app was active")
                        exit(1)
                    }
                    NSRunningApplication.current.activate(options: [.activateAllWindows])
                    NSApp.activate(ignoringOtherApps: true)
                    window.makeKeyAndOrderFront(nil)
                    window.makeFirstResponder(editor)
                    try? await Task.sleep(for: .milliseconds(950))
                    guard NSApp.isActive,
                          NSWorkspace.shared.frontmostApplication?.processIdentifier == getpid(),
                          window.firstResponder === editor else {
                        print("BLOCKED · Selection fixture did not regain foreground editor")
                        exit(2)
                    }
                    guard frames().isEmpty else {
                        print("FAIL · Selection panel reopened after returning to the host")
                        exit(1)
                    }
                    print("PASS · Selection panel stayed closed after returning to the host")
                    editor.setSelectedRange(NSRange(location: editor.string.utf16.count, length: 0))
                    try? await Task.sleep(for: .milliseconds(850))
                    guard frames().isEmpty else { print("FAIL · Selection panel stayed visible after clearing selection"); exit(1) }
                    print("PASS · Selection panel closed after clearing selection", round)
                }
                print("PASS · Selection fixture completed")
                fflush(stdout)
                exit(0)
            }
            if CommandLine.arguments.contains("--switch-windows") {
                let second = NSWindow(contentRect: NSRect(x: 260, y: 220, width: 600, height: 300), styleMask: [.titled, .closable], backing: .buffered, defer: false)
                let secondEditor = NSTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 300))
                second.title = "GuYi · Window switching fixture"
                second.contentView = secondEditor
                second.isReleasedWhenClosed = false
                for round in 0..<10 {
                    if CommandLine.arguments.contains("--switch-apps") {
                        NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first?.activate(options: [])
                        try? await Task.sleep(for: .milliseconds(300))
                        NSRunningApplication.current.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
                        try? await Task.sleep(for: .milliseconds(300))
                    }
                    let target = round.isMultiple(of: 2) ? second : window
                    let field = round.isMultiple(of: 2) ? secondEditor : editor
                    target.makeKeyAndOrderFront(nil)
                    guard target.makeFirstResponder(field) else { print("BLOCKED · Target text field refused focus"); exit(2) }
                    try? await Task.sleep(for: .milliseconds(250))
                    guard NSApp.isActive else { print("BLOCKED · Lost focus during switch"); exit(2) }
                    guard NSApp.keyWindow === target, target.firstResponder === field else {
                        print("BLOCKED · Window switch did not focus target text field")
                        exit(2)
                    }
                    guard field.inputContext?.selectedKeyboardInputSource?.contains("guyi") == true else {
                        print("FAIL · Window switch source", field.inputContext?.selectedKeyboardInputSource ?? "none"); exit(1)
                    }
                    field.string = ""
                    for code: CGKeyCode in [45, 34, 4, 0, 31, 49] {
                        sendKey(code)
                        try? await Task.sleep(for: .milliseconds(100))
                    }
                    if field.string == "你好", field.hasMarkedText() {
                        sendKey(49)
                        try? await Task.sleep(for: .milliseconds(150))
                    }
                    guard field.string == "你好", !field.hasMarkedText() else {
                        print("FAIL · Chinese input after switch", field.string.debugDescription); exit(1)
                    }
                    print("PASS · Window switch and Chinese input", round + 1)
                }
                editor.string = "KEEP"
                editor.setSelectedRange(NSRange(location: editor.string.utf16.count, length: 0))
                window.makeKeyAndOrderFront(nil)
                window.makeFirstResponder(editor)
                for code: CGKeyCode in [45, 0, 37, 34] {
                    sendKey(code)
                    try? await Task.sleep(for: .milliseconds(100))
                }
                guard editor.hasMarkedText() else { print("BLOCKED · No pending Pinyin before focus switch"); exit(2) }
                print("BACKSPACE_BEFORE_SWITCH", editor.string.debugDescription,
                      "MARKED", editor.hasMarkedText(), "SELECTION", editor.selectedRange())
                if CommandLine.arguments.contains("--switch-apps") {
                    NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first?.activate(options: [])
                    try? await Task.sleep(for: .milliseconds(400))
                    NSRunningApplication.current.activate(options: [.activateAllWindows])
                } else {
                    second.makeKeyAndOrderFront(nil)
                    second.makeFirstResponder(secondEditor)
                    try? await Task.sleep(for: .milliseconds(400))
                }
                window.makeKeyAndOrderFront(nil)
                window.makeFirstResponder(editor)
                try? await Task.sleep(for: .milliseconds(400))
                guard NSApp.isActive else { print("BLOCKED · Lost focus before Backspace regression"); exit(2) }
                print("BACKSPACE_AFTER_SWITCH", editor.string.debugDescription,
                      "MARKED", editor.hasMarkedText(), "SELECTION", editor.selectedRange())
                guard editor.hasMarkedText(), editor.string.hasPrefix("KEEP") else {
                    print("FAIL · Pending Pinyin was not preserved across focus return")
                    exit(1)
                }
                let beforeDelete = editor.string
                sendKey(51)
                try? await Task.sleep(for: .milliseconds(300))
                guard editor.string.hasPrefix("KEEP"), editor.hasMarkedText(), editor.string != beforeDelete else {
                    print("FAIL · Backspace did not edit only pending Pinyin after focus return",
                          editor.string.debugDescription, "MARKED", editor.hasMarkedText(),
                          "SELECTION", editor.selectedRange())
                    exit(1)
                }
                sendKey(34)
                try? await Task.sleep(for: .milliseconds(300))
                guard editor.string.hasPrefix("KEEP"), editor.hasMarkedText() else {
                    print("FAIL · Continued Pinyin replaced earlier text after focus return")
                    exit(1)
                }
                print("PASS · Pending Pinyin survives focus return, Backspace and continued typing")
                editor.string = "KEEP"
                editor.setSelectedRange(NSRange(location: editor.string.utf16.count, length: 0))
                for code: CGKeyCode in [45, 0, 37, 34] {
                    sendKey(code)
                    try? await Task.sleep(for: .milliseconds(100))
                }
                second.makeKeyAndOrderFront(nil)
                second.makeFirstResponder(secondEditor)
                try? await Task.sleep(for: .milliseconds(300))
                window.makeKeyAndOrderFront(nil)
                window.makeFirstResponder(editor)
                try? await Task.sleep(for: .milliseconds(300))
                guard editor.hasMarkedText() else { print("FAIL · Pinyin vanished on direct continuation"); exit(1) }
                sendKey(7)
                try? await Task.sleep(for: .milliseconds(300))
                guard editor.string.hasPrefix("KEEP"), editor.string.lowercased().contains("x"), editor.hasMarkedText() else {
                    print("FAIL · Normal typing overwrote pending Pinyin after focus return")
                    exit(1)
                }
                print("PASS · Normal typing extends pending Pinyin after focus return")
                second.close()
                window.makeKeyAndOrderFront(nil)
                window.makeFirstResponder(editor)
            }
            var panelFrames: [CGRect] = []
            var wrappedSamples = 0
            let identifier = reference ? (source.contains("wetype") ? "com.tencent.inputmethod.wetype" : "com.sogou.inputmethod.sogou") : "app.guyi.inputmethod.Guyi"
            let backendPID = NSRunningApplication.runningApplications(withBundleIdentifier: identifier).first?.processIdentifier
            let repetitions = CommandLine.arguments.contains("--wrap") ? 12 : 5
            let cases: [([Int], String)] = CommandLine.arguments.contains("--basic-only")
                ? [([45,34,4,0,31,36], "nihao"), ([4,14,37,37,31,36], "hello")]
                : [([45,34,4,0,31,36], "nihao"), ([4,14,37,37,31,36], "hello"),
                   (Array(repeating: [45,34,4,0,31], count: repetitions).flatMap { $0 } + [36], String(repeating: "nihao", count: repetitions))]
            for (codes, expected) in cases {
                editor.string = ""
                panelFrames = []
                for code in codes {
                    guard NSApp.isActive else { exit(2) }
                    sendKey(UInt16(code))
                    try? await Task.sleep(for: .milliseconds(160))
                    let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
                    for info in windows where (info[kCGWindowOwnerPID as String] as? Int32) == backendPID && (info[kCGWindowLayer as String] as? Int ?? 0) > 0 {
                        if let bounds = info[kCGWindowBounds as String] as? [String: Any], let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary) {
                            panelFrames.append(rect)
                            let marked = editor.markedRange()
                            if marked.location != NSNotFound, marked.length > 0 {
                                let first = editor.firstRect(forCharacterRange: NSRange(location: marked.location, length: 0), actualRange: nil)
                                let last = editor.firstRect(forCharacterRange: NSRange(location: marked.location + marked.length, length: 0), actualRange: nil)
                                let occupied = first.union(last)
                                let panel = NSRect(x: rect.minX, y: NSScreen.screens.first!.frame.maxY - rect.maxY, width: rect.width, height: rect.height)
                                if abs(first.minY - last.minY) > 2 { wrappedSamples += 1 }
                                if panel.maxY > occupied.minY && panel.minY < occupied.maxY {
                                    print("FAIL · Candidate overlaps composition", panel, occupied)
                                    if !reference { exit(1) }
                                }
                            }
                        }
                    }
                }
                print("RESULT", editor.string.debugDescription, "MARKED", editor.hasMarkedText())
                guard editor.string == expected, !editor.hasMarkedText() else { print("FAIL · raw Return"); exit(1) }
                if CommandLine.arguments.contains("--basic-only"), expected == "nihao" {
                    guard !panelFrames.isEmpty else { print("FAIL · Chinese Pinyin candidate never appeared"); exit(1) }
                    print("PASS · Chinese Pinyin candidate appeared", panelFrames.count)
                }
                print("PASS · \(expected) + Return, no newline")
                if codes.count > 20 {
                    print("PANEL SAMPLES", panelFrames.count)
                    guard panelFrames.count >= 10 else { print("BLOCKED · Not enough candidate frames"); exit(2) }
                    let horizontal = panelFrames.map(\.minX)
                    let top = panelFrames.map(\.minY)
                    let bottom = panelFrames.map(\.maxY)
                    let xSpread = horizontal.max()! - horizontal.min()!
                    let maxHorizontalStep = zip(horizontal, horizontal.dropFirst()).map { abs($0 - $1) }.max() ?? 0
                    let anchoredSpread = min(top.max()! - top.min()!, bottom.max()! - bottom.min()!)
                    print("PANEL SPREAD", xSpread, anchoredSpread, "MAX_STEP", maxHorizontalStep)
                    if reference {
                        print("REFERENCE HEIGHTS", Set(panelFrames.map(\.height)).sorted())
                        print("REFERENCE WRAPPED SAMPLES", wrappedSamples)
                        continue
                    }
                    if CommandLine.arguments.contains("--wrap") {
                        guard wrappedSamples > 0 else { print("BLOCKED · No wrapped composition observed"); exit(2) }
                        print("PASS · Candidate avoids multi-line composition, wrapped samples", wrappedSamples)
                    } else {
                        guard maxHorizontalStep <= 80, anchoredSpread <= 2 else { print("FAIL · Candidate anchor jitter"); exit(1) }
                        print("PASS · Candidate tracks caret without jumps during long pinyin composition")
                    }
                }
            }
            if CommandLine.arguments.contains("--basic-only") { print("PASS · Basic input fixture completed") }
            fflush(stdout)
            exit(0)
        }
    }
}

let application = NSApplication.shared
let delegate = RawEnterSmoke()
application.setActivationPolicy(.regular)
application.delegate = delegate
application.run()
