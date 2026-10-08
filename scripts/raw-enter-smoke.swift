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
                for (codes, expected): ([CGKeyCode], String) in [([23,44,23,24,36], "5/5=1"), ([18,44,20,24,36], "1/3=1/3"), ([29,47,18,69,29,47,19,24,36], "0.1+0.2=0.3"), ([20,43,21,21,21,69,18,24,36], "3,444+1=3,445")] {
                    editor.string = ""
                    // An empty-space boundary also clears context from the previous fixture case.
                    sendKey(49)
                    try? await Task.sleep(for: .milliseconds(150))
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
                            guard let height = heights.first, height <= 260 else { print("FAIL · Calculator panel height", heights); exit(1) }
                        }
                    }
                    guard editor.string == expected, !editor.hasMarkedText() else { print("FAIL · Calculator insertion", editor.string.debugDescription); exit(1) }
                    print("PASS · Calculator Return inserts exact result without newline", expected)
                }
                editor.string = ""
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
                    target.makeFirstResponder(field)
                    try? await Task.sleep(for: .milliseconds(250))
                    guard NSApp.isActive else { print("BLOCKED · Lost focus during switch"); exit(2) }
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
                second.close()
                window.makeKeyAndOrderFront(nil)
                window.makeFirstResponder(editor)
            }
            var panelFrames: [CGRect] = []
            var wrappedSamples = 0
            let identifier = reference ? (source.contains("wetype") ? "com.tencent.inputmethod.wetype" : "com.sogou.inputmethod.sogou") : "app.guyi.inputmethod.Guyi"
            let backendPID = NSRunningApplication.runningApplications(withBundleIdentifier: identifier).first?.processIdentifier
            let repetitions = CommandLine.arguments.contains("--wrap") ? 12 : 5
            for (codes, expected) in [([45,34,4,0,31,36], "nihao"), ([4,14,37,37,31,36], "hello"), (Array(repeating: [45,34,4,0,31], count: repetitions).flatMap { $0 } + [36], String(repeating: "nihao", count: repetitions))] {
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
