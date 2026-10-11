import AppKit
import Combine
import GuyiCore

@MainActor final class ClickFixture: NSObject, NSApplicationDelegate {
    private let translation = TranslationSession(cache: TranslationCache())
    private lazy var model = CandidateModel(translation: translation)
    private var panel: CandidatePanel?
    private var observers: Set<AnyCancellable> = []
    private var tick = 0
    private var lastFrame = CGRect.zero
    private var anchorBottom: CGFloat = 0
    private var jumped = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.language = .zh
        model.translationSource = .zh
        model.original = "你好"
        model.candidates = ["你好", "您好", "逆号", "拟好", "你"]
        model.enabledLanguages = [.zh, .en, .id]
        model.collapsedLanguages = []
        model.learn = { [weak self] _ in
            guard let self else { return }
            self.model.lessonStatus = "正在整理语法说明…"
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                let json = #"{"structure":"Hello：你好","points":["用于日常问候"],"register":"日常","example":"Hello, Lin! 你好，林！","ipa":"/həˈloʊ/","pronunciation":"重音在第二音节。","vocabulary":[{"word":"Hello","ipa":"/həˈloʊ/","meaning":"你好"}]}"#
                self.model.lesson = try? JSONDecoder().decode(GrammarLesson.self, from: Data(json.utf8))
            }
        }
        let panel = CandidatePanel(model: model)
        self.panel = panel
        model.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { self?.showPanel() }
        }.store(in: &observers)
        let caret = CGRect(x: 220, y: 145, width: 2, height: 20)
        panel.present(near: caret)
        anchorBottom = panel.frame.minY
        print("FIXTURE_WINDOW \(panel.windowNumber) FRAME \(panel.frame)")
        fflush(stdout)
        Timer.scheduledTimer(timeInterval: 0.016, target: self, selector: #selector(sample(_:)),
                             userInfo: nil, repeats: true)
    }

    @objc private func sample(_ timer: Timer) {
        guard let panel else { timer.invalidate(); return }
        tick += 1
        if model.expanded && abs(panel.frame.minY - anchorBottom) > 1 { jumped = true }
        if panel.frame != lastFrame {
            lastFrame = panel.frame
            print("FRAME tick=\(tick) visible=\(panel.isVisible) expanded=\(model.expanded) rect=\(panel.frame)")
            fflush(stdout)
        }
        if tick == 115 {
            let top = NSScreen.screens.first?.frame.maxY ?? 0
            let point = CGPoint(x: panel.frame.minX + 384, y: top - panel.frame.maxY + 22)
            print("CLICK \(point)")
            fflush(stdout)
            for type in [CGEventType.leftMouseDown, .leftMouseUp] {
                CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point,
                        mouseButton: .left)?.post(tap: .cghidEventTap)
            }
        }
        if tick == 250 {
            print("RESULT expanded=\(model.expanded) visible=\(panel.isVisible) frame=\(panel.frame)")
            fflush(stdout)
            precondition(model.expanded && panel.isVisible && !jumped,
                         "Clicking learning must not move the popup away from its caret anchor")
            timer.invalidate()
            NSApp.terminate(nil)
        }
    }

    private func showPanel() {
        panel?.present(near: CGRect(x: 220, y: 145, width: 2, height: 20))
    }
}

@main struct Main {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = ClickFixture()
        app.delegate = delegate
        app.run()
        withExtendedLifetime(delegate) {}
    }
}
