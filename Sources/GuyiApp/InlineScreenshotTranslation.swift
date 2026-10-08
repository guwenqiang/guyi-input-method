import AppKit
import SwiftUI
import GuyiCore

final class ScreenshotTranslationPanel: NSPanel {
    var cancelled: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { cancelled?() }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { cancelOperation(nil) }
        else { super.keyDown(with: event) }
    }
}

@MainActor
final class InlineScreenshotTranslation {
    private var imagePanel: NSPanel?
    private var controlsPanel: NSPanel?
    private var model: ScreenshotTranslation?

    func show(image: CGImage, rect: CGRect) {
        close()
        guard let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { return }
        let model = ScreenshotTranslation(image: NSImage(cgImage: image, size: .zero), data: data, automatic: true)
        self.model = model
        let mainHeight = NSScreen.screens.first?.frame.maxY ?? 0
        let frame = NSRect(x: rect.minX, y: mainHeight - rect.maxY, width: rect.width, height: rect.height)
        let panel = makePanel(frame: frame)
        panel.contentView = NSHostingView(rootView: InlineScreenshotCanvas(model: model).frame(width: frame.width, height: frame.height))
        panel.makeKeyAndOrderFront(nil)
        imagePanel = panel
        let screen = NSScreen.screens.first(where: { $0.frame.intersects(frame) })?.visibleFrame ?? NSScreen.main!.visibleFrame
        let size = NSSize(width: min(520, screen.width - 16), height: 96)
        let below = frame.minY - size.height - 8
        let origin = NSPoint(x: max(screen.minX + 8, min(frame.maxX - size.width, screen.maxX - size.width - 8)),
                             y: max(screen.minY + 8, min(below >= screen.minY + 8 ? below : frame.maxY + 8, screen.maxY - size.height - 8)))
        let controls = makePanel(frame: NSRect(origin: origin, size: size))
        controls.contentView = NSHostingView(rootView: InlineScreenshotControls(model: model, close: { [weak self] in self?.close() }))
        controls.orderFrontRegardless()
        controlsPanel = controls
    }

    func close() {
        model?.cancel()
        model = nil
        imagePanel?.close()
        controlsPanel?.close()
        imagePanel = nil
        controlsPanel = nil
    }

    private func makePanel(frame: NSRect) -> NSPanel {
        let panel = ScreenshotTranslationPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.cancelled = { [weak self] in self?.close() }
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        return panel
    }
}

struct InlineScreenshotCanvas: View {
    @ObservedObject var model: ScreenshotTranslation
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                Image(nsImage: model.image).resizable().frame(width: geometry.size.width, height: geometry.size.height)
                if !model.showOriginal {
                    ForEach(Array(model.regions.enumerated()), id: \.offset) { index, region in
                        if let value = model.translatedRegions[index] {
                            TranslatedRegionView(text: value, bounds: region.bounds, canvas: geometry.size)
                        }
                    }
                }
            }
        }
    }
}

private struct InlineScreenshotControls: View {
    @ObservedObject var model: ScreenshotTranslation
    let close: () -> Void
    @ObservedObject private var language = InterfaceLanguage.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker("翻译为", selection: $model.target) {
                    ForEach(Language.targets) { Text($0.title).tag($0) }
                }.disabled(model.busy)
                Toggle("显示原图", isOn: $model.showOriginal).toggleStyle(.button)
                Button("翻译") { model.translate() }.disabled(model.busy || model.original.isEmpty)
                Button("关闭") { close() }
            }
            Text(Localizer.text(model.status)).font(.caption).lineLimit(2).foregroundStyle(.secondary)
        }.padding(12).frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            .environment(\.locale, language.locale)
    }
}
