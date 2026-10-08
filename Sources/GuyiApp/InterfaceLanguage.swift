import SwiftUI
import GuyiCore

@MainActor
final class InterfaceLanguage: ObservableObject {
    static let shared = InterfaceLanguage()
    @Published var preference: String {
        didSet {
            UserDefaults.standard.set(preference, forKey: "interfaceLanguage")
            NotificationCenter.default.post(name: .guyiInterfaceLanguageChanged, object: nil)
        }
    }
    var code: String { Localizer.languageCode(preference: preference) }
    var locale: Locale { Locale(identifier: code) }
    private init() { preference = UserDefaults.standard.string(forKey: "interfaceLanguage") ?? "system" }
}

extension Notification.Name {
    static let guyiInterfaceLanguageChanged = Notification.Name("guyiInterfaceLanguageChanged")
}
