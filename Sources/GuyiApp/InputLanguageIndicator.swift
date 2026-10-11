import AppKit
import SwiftUI
import GuyiCore

@MainActor final class InputLanguageIndicator {
    static let shared = InputLanguageIndicator()
    private let panel: NSPanel
    private var dismissTask: Task<Void, Never>?
    private let size = NSSize(width: 34, height: 34)

    private init() {
        panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
    }

    func show(_ language: Language, near caret: NSRect, avoiding candidate: NSRect?, accent: Color) {
        guard caret.width.isFinite, caret.height.isFinite, caret.height > 0,
              let screen = NSScreen.screens.first(where: { $0.frame.intersects(caret.insetBy(dx: -1, dy: 0)) }) else { return }
        let label: String = switch language {
        case .zh: "中"
        case .ja: "日"
        case .ko: "한"
        case .id: "ID"
        default: "EN"
        }
        let content = Text(label)
            .font(.system(size: language == .en || language == .id ? 11 : 14, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size.width, height: size.height)
            .background(accent, in: Circle())
        panel.contentView = NSHostingView(rootView: content)
        let visible = screen.visibleFrame
        let positions = [
            NSPoint(x: caret.midX - size.width / 2, y: caret.minY - size.height - 6),
            NSPoint(x: caret.midX - size.width / 2, y: caret.maxY + 6),
            NSPoint(x: caret.maxX + 6, y: caret.midY - size.height / 2),
            NSPoint(x: caret.minX - size.width - 6, y: caret.midY - size.height / 2)
        ]
        guard let origin = positions.first(where: { point in
            let frame = NSRect(origin: point, size: size)
            return visible.contains(frame) && (candidate?.intersects(frame) != true)
        }) else { return }
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.orderFrontRegardless()
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
            self?.panel.orderOut(nil)
        }
    }

    func hide() {
        dismissTask?.cancel()
        panel.orderOut(nil)
    }
}
