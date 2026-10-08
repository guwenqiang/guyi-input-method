import AppKit
import SwiftUI
import InputMethodKit
import Carbon
import GuyiCore
import CInputMethodBridge

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    static let shared = AppDelegate()
    lazy var preferences = Preferences()
    weak var currentController: GuyiInputController?
    private var server: IMKServer?
    private var settingsWindow: NSWindow?
    private var statusItem: NSStatusItem?
    private var sentenceMenuItem: NSMenuItem?

    func prepareInputServer() -> Bool {
        if CommandLine.arguments.contains("--self-test") { return true }
        if let identifier = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: identifier).contains(where: { $0.processIdentifier != getpid() }) {
            if CommandLine.arguments.contains("--settings") {
                DistributedNotificationCenter.default().postNotificationName(Notification.Name("guyi.showSettings"), object: nil, deliverImmediately: true)
            }
            return false
        }
        guard let identifier = Bundle.main.bundleIdentifier,
              let connectionName = Bundle.main.object(forInfoDictionaryKey: "InputMethodConnectionName") as? String,
              connectionName == identifier + ".Connection",
              let inputServer = IMKServer(name: connectionName, bundleIdentifier: identifier) else {
            NSLog("GuYi: unable to register InputMethodKit connection")
            exit(1)
        }
        server = inputServer
        let alias = identifier + ".Connection"
        let registered = alias.withCString { guyi_register_imk_connection_alias(Unmanaged.passUnretained(inputServer).toOpaque(), $0) }
        if !registered { NSLog("GuYi: IMK compatibility connection unavailable; XPC service remains active") }
        return true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--self-test") { selfTest(); return }
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(showSettings), name: Notification.Name("guyi.showSettings"), object: nil)
        EditingMenu.install()
        // Older releases did not honor concealed clipboard metadata. Clear all
        // derived translations once; never inspect or preserve possible secrets.
        if !UserDefaults.standard.bool(forKey: "sensitiveClipboardCacheMigration51") {
            TranslationCache.shared.clear()
            Task {
                await TranslationCache.shared.flush()
                UserDefaults.standard.set(true, forKey: "sensitiveClipboardCacheMigration51")
            }
        }
        NotificationCenter.default.addObserver(self, selector: #selector(interfaceLanguageChanged), name: .guyiInterfaceLanguageChanged, object: nil)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(inputSourceChanged),
            name: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String), object: nil, suspensionBehavior: .deliverImmediately)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(frontApplicationChanged),
            name: NSWorkspace.didActivateApplicationNotification, object: nil)
        HotwordStore.shared.configure(enabled: preferences.settings.hotwordsEnabled != false)
        SelectionTranslationService.shared.start(preferences: preferences)
        TerminalCapsLockSwitch.shared.prepareSwitch = { [weak self] in self?.currentController?.prepareExternalSourceSwitch() }
        TerminalCapsLockSwitch.shared.allowsSwitch = {
            !TranslationPrivacy.protectedContext() && !InputSafety.bypassInputMethod(bundleIdentifier: NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
        }
        TerminalCapsLockSwitch.shared.start()
        ScreenshotService.shared.configure(enabled: false,
            key: preferences.settings.screenshotKey ?? 21, modifiers: preferences.settings.screenshotModifiers ?? 4352)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.button?.image = Bundle.main.image(forResource: "input-badge")
        statusItem?.button?.image?.isTemplate = false
        statusItem?.button?.image?.size = NSSize(width: 22, height: 18)
        statusItem?.button?.toolTip = Brand.name
        let menu = NSMenu()
        let settings = NSMenuItem(title: Brand.settings + "…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        let help = NSMenuItem(title: Localizer.text("使用说明"), action: #selector(showHelp), keyEquivalent: "")
        help.target = self
        menu.addItem(help)
        menu.addItem(.separator())
        let sentence = NSMenuItem(title: Localizer.text("整句翻译模式"), action: #selector(toggleSentenceMode), keyEquivalent: "")
        sentence.target = self
        sentenceMenuItem = sentence
        menu.addItem(sentence)
        NotificationCenter.default.addObserver(self, selector: #selector(updateSentenceMenu), name: .guyiSentenceModeChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(updateSentenceMenu), name: .guyiSettingsChanged, object: nil)
        updateSentenceMenu()
        statusItem?.menu = menu
        if CommandLine.arguments.contains("--settings") { showSettings() }
        if CommandLine.arguments.contains("--preview") { preview() }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        false
    }
    @objc func showSettings() {
        if settingsWindow == nil {
            let window = SettingsWindow(contentRect: NSRect(x: 0, y: 0, width: 660, height: 610), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = Brand.settings
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.level = .normal
            window.hidesOnDeactivate = false
            window.collectionBehavior = [.managed]
            window.contentView = NSHostingView(rootView: SettingsView(preferences: preferences))
            window.center()
            settingsWindow = window
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.unhide(nil)
        if settingsWindow?.isMiniaturized == true { settingsWindow?.deminiaturize(nil) }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
    func windowWillClose(_ notification: Notification) {
        if notification.object as? NSWindow === settingsWindow { NSApp.setActivationPolicy(.accessory) }
    }
    @objc private func interfaceLanguageChanged() {
        settingsWindow?.title = Brand.settings
        if let items = statusItem?.menu?.items, items.count >= 2 {
            items[0].title = Brand.settings + "…"
            items[1].title = Localizer.text("使用说明")
        }
        EditingMenu.install()
        updateSentenceMenu()
    }
    @objc private func toggleSentenceMode() { preferences.toggleSentenceMode() }
    @objc private func updateSentenceMenu() {
        sentenceMenuItem?.title = Localizer.text("整句翻译模式")
        sentenceMenuItem?.state = preferences.settings.sentenceComposition == true ? .on : .off
    }
    @objc private func showHelp() {
        let language = InterfaceLanguage.shared.code
        if let url = Bundle.main.url(forResource: language, withExtension: "html", subdirectory: "Help")
            ?? Bundle.main.url(forResource: "en", withExtension: "html", subdirectory: "Help") {
            NSWorkspace.shared.open(url)
        }
    }
    @objc private func captureScreen() { ScreenshotService.shared.capture() }
    func prepareForScreenshot() {
        SelectionTranslationService.shared.close()
        settingsWindow?.orderOut(nil)
        currentController?.hideCandidatePanel()
    }
    @objc private func inputSourceChanged() {
        TerminalCapsLockSwitch.shared.sourceChanged()
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return }
        let identifier = Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
        if !identifier.hasPrefix("app.guyi.inputmethod.Guyi") { currentController?.hideCandidatePanel() }
    }
    @objc private func frontApplicationChanged() { currentController?.hideIfClientInactive(); ScreenshotService.shared.hostDidChange(); TerminalCapsLockSwitch.shared.refreshHardwareAccess() }
    private var previewPanel: CandidatePanel?
    private func preview() {
        let model = CandidateModel()
        model.preedit = "ming tian jian"
        model.original = "明天见"
        model.candidates = ["明天见", "明天", "名田"]
        model.translation.invalidate(message: "界面预览 · 实际译文需配置 API Key")
        previewPanel = CandidatePanel(model: model)
        previewPanel?.present(near: .zero)
    }
    private func selfTest() {
        let engine = RimeEngine()
        var success = true
        for (pinyin, expected) in [("nihao", "你好"), ("zhongwen", "中文"), ("mingtian", "明天")] {
            engine.clear()
            for scalar in pinyin.unicodeScalars { _ = engine.key(Int32(scalar.value)) }
            let state = engine.state()
            let passed = state.candidates.contains(expected)
            success = success && passed
            print("Rime \(pinyin): \(passed ? "PASS" : "FAIL") · \(state.candidates.joined(separator: ", "))")
        }
        engine.clear()
        for scalar in "nihao".unicodeScalars { _ = engine.key(Int32(scalar.value)) }
        let preedit = engine.state().preedit
        let rawPreserved = engine.rawInput == "nihao"
        success = success && rawPreserved
        print("Rime raw Latin input preserved: \(rawPreserved ? "PASS" : "FAIL")")
        let cursorAtEnd = engine.cursor(in: preedit) == preedit.utf16.count
        success = success && cursorAtEnd
        print("Rime typing cursor at end: \(cursorAtEnd ? "PASS" : "FAIL")")
        let third = engine.state().candidates[2]
        engine.highlight(2)
        let highlighted = engine.state().selected == 2
        engine.select(2)
        let selectedThird = engine.commit() == third
        success = success && highlighted && selectedThird
        print("Rime third candidate navigation: \(highlighted && selectedThird ? "PASS" : "FAIL")")
        for scalar in "ni".unicodeScalars { _ = engine.key(Int32(scalar.value)) }
        _ = engine.key(0xff56)
        let paged = engine.page == 1
        success = success && paged
        print("Rime more than five candidates: \(paged ? "PASS" : "FAIL")")
        engine.clear()
        for scalar in "nihao".unicodeScalars { _ = engine.key(Int32(scalar.value)) }
        engine.select(1)
        let learned = engine.commit()
        for scalar in "nihao".unicodeScalars { _ = engine.key(Int32(scalar.value)) }
        let promoted = engine.state().candidates.first == learned
        success = success && promoted
        print("Rime user frequency promotion: \(promoted ? "PASS" : "FAIL")")
        engine.clear()
        engine.learning(false)
        for scalar in "nihao".unicodeScalars { _ = engine.key(Int32(scalar.value)) }
        let privateMode = engine.state().candidates.first == "你好"
        success = success && privateMode
        print("Rime learning-off isolation: \(privateMode ? "PASS" : "FAIL")")
        fflush(stdout)
        exit(success ? 0 : 1)
    }
}

MainActor.assumeIsolated {
    if CommandLine.arguments.contains("--register-input-source") {
        exit(InputSourceRegistration.run())
    }
    let delegate = AppDelegate.shared
    guard delegate.prepareInputServer() else { exit(0) }
    let application = NSApplication.shared
    application.setActivationPolicy(.accessory)
    application.delegate = delegate
    application.run()
}
