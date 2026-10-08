import AppKit
import SwiftUI
import GuyiCore
import UniformTypeIdentifiers

@MainActor
final class ScreenshotTranslation: ObservableObject {
    @Published var original = ""
    @Published var output = ""
    @Published var status = "识别中…"
    @Published var busy = true
    @Published var regions: [ScreenshotOCR.Region] = []
    @Published var translatedRegions: [Int: String] = [:]
    @Published var showOriginal = false
    @Published var target: Language {
        didSet {
            UserDefaults.standard.set(target.rawValue, forKey: "screenshotTarget")
            cancel()
            if automatic, !original.isEmpty { translate() }
        }
    }
    let image: NSImage
    private let automatic: Bool
    private var task: Task<Void, Never>?
    private var revision = 0
    init(image: NSImage, data: Data, automatic: Bool = false) {
        self.image = image
        self.automatic = automatic
        let saved = Language(rawValue: UserDefaults.standard.string(forKey: "screenshotTarget") ?? "en") ?? .en
        target = saved == .auto ? .en : saved
        task = Task { [weak self] in
            do {
                let regions = try await Task.detached { try ScreenshotOCR.recognize(data) }.value
                guard let self, !Task.isCancelled else { return }
                self.regions = regions
                self.original = regions.map(\.text).joined(separator: "\n")
                self.busy = false
                self.status = regions.isEmpty ? "未识别到文字" : ""
                if self.automatic, !regions.isEmpty { self.translate() }
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.busy = false
                self.status = "文字识别失败，请重新截图"
            }
        }
    }
    func cancel() {
        revision += 1
        task?.cancel()
        output = ""
        translatedRegions = [:]
        busy = false
        status = ""
    }
    func translate() {
        cancel()
        guard !original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let current = revision
        var settings = AppDelegate.shared.preferences.settings
        settings.source = .auto
        settings.enabledLanguages = [target]
        let key = AppDelegate.shared.preferences.apiKey
        let text = original
        let language = target
        let regions = regions
        busy = true
        status = "翻译中…"
        task = Task { [weak self] in
            do {
                guard regions.count <= 100, text.count <= 4_000 else { throw TranslationError.tooLong }
                let translated = try await OpenAIBlockTranslator().translate(regions.map(\.text), target: language, settings: settings, apiKey: key)
                let results = Dictionary(uniqueKeysWithValues: translated.enumerated().map { ($0.offset, $0.element) })
                guard let self, !Task.isCancelled, self.revision == current else { return }
                self.translatedRegions = results
                self.output = regions.indices.compactMap { results[$0] }.joined(separator: "\n")
                self.status = ""
                self.busy = false
            } catch {
                guard let self, !Task.isCancelled, self.revision == current else { return }
                self.status = error.localizedDescription
                self.busy = false
            }
        }
    }
}

struct ScreenshotTranslationView: View {
    @ObservedObject var model: ScreenshotTranslation
    var scrollNext: (() -> Void)? = nil
    var close: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var interfaceLanguage = InterfaceLanguage.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button("取消") { model.cancel(); if let close { close() } else { dismiss() } }
                Button("保存原图…") {
                    let panel = NSSavePanel()
                    panel.allowedContentTypes = [.png]
                    panel.nameFieldStringValue = "GuYi-Screenshot.png"
                    panel.begin { response in
                        guard response == .OK, let url = panel.url,
                              let tiff = model.image.tiffRepresentation,
                              let bitmap = NSBitmapImageRep(data: tiff),
                              let data = bitmap.representation(using: .png, properties: [:]) else { return }
                        do { try data.write(to: url, options: .atomic) }
                        catch { model.status = error.localizedDescription }
                    }
                }
                Button("复制截图") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.writeObjects([model.image])
                }
                Spacer()
            }
            GeometryReader { geometry in
                let scale = min(geometry.size.width / model.image.size.width, geometry.size.height / model.image.size.height)
                let width = model.image.size.width * scale
                let height = model.image.size.height * scale
                ZStack(alignment: .topLeading) {
                    Image(nsImage: model.image).resizable().frame(width: width, height: height)
                    if !model.showOriginal {
                        ForEach(Array(model.regions.enumerated()), id: \.offset) { index, region in
                            if let translated = model.translatedRegions[index] {
                                TranslatedRegionView(text: translated, bounds: region.bounds, canvas: CGSize(width: width, height: height))
                            }
                        }
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }.frame(height: 320)
            HStack {
                Picker("翻译为", selection: $model.target) {
                    ForEach(Language.targets) { Text(Localizer.text($0.title)).tag($0) }
                }.disabled(model.busy)
                Button(Localizer.text(model.busy ? "处理中…" : "翻译")) { model.translate() }
                    .disabled(model.busy || model.original.isEmpty).buttonStyle(.borderedProminent)
            }
            Toggle("显示原图", isOn: $model.showOriginal)
            ScrollView { Text(model.output).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                .frame(minHeight: 100)
            HStack {
                Text(Localizer.text(model.status)).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("复制译文") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.output, forType: .string)
                }.disabled(model.output.isEmpty)
            }
        }.padding(20).frame(width: 720, height: 660)
        .environment(\.locale, interfaceLanguage.locale)
        .onDisappear { model.cancel() }
    }
}
