import Foundation
import GuyiCore

enum Brand {
    static var name: String { Localizer.code == "zh-Hans" ? "GuYi输入法" : "GuYi Input Method" }
    static var settings: String { name + " · " + Localizer.text("设置") }
    static var version: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "v\(version) (\(build))"
    }
}
