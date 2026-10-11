import AppKit
import SwiftUI
import GuyiCore

@MainActor
final class AppDelegate {
    static let shared = AppDelegate()
    let preferences = Preferences()
}

@main
struct SettingsUISmoke {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let previous = InterfaceLanguage.shared.preference
        defer { InterfaceLanguage.shared.preference = previous }
        for language in ["zh-Hans", "en", "id", "ja", "ko"] {
            InterfaceLanguage.shared.preference = language
            let expected = ["en": "Settings", "id": "Pengaturan", "ja": "設定", "ko": "설정"][language] ?? "设置"
            guard Localizer.text("设置") == expected else { fatalError("Localization bundle failed") }
            let host = NSHostingView(rootView: SettingsView(preferences: AppDelegate.shared.preferences))
            host.frame = NSRect(origin: .zero, size: host.fittingSize)
            host.layoutSubtreeIfNeeded()
            let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: ".build/settings-\(language).png"))
            print("PASS · Settings render in \(language), title \(expected)")
        }
    }
}
