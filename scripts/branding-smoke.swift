import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "dist/.build.noindex/Guyi.app")
for name in ["logo.png", "input-badge.png", "input-badge@2x.png", "input-badge-template.png", "input-badge-template@2x.png"] {
    let url = root.appendingPathComponent("Contents/Resources/" + name)
    let image = NSBitmapImageRep(data: try Data(contentsOf: url))!
    var black = 0, white = 0, cutout = 0
    for row in 0..<image.pixelsHigh {
        for column in 0..<image.pixelsWide {
            guard let pixel = image.colorAt(x: column, y: row)?.usingColorSpace(.sRGB) else { continue }
            if pixel.alphaComponent < 0.01,
               column > image.pixelsWide * 3 / 10, column < image.pixelsWide * 7 / 10,
               row > image.pixelsHigh * 3 / 10, row < image.pixelsHigh * 7 / 10 { cutout += 1 }
            guard pixel.alphaComponent > 0.99 else { continue }
            if pixel.redComponent == 0 && pixel.greenComponent == 0 && pixel.blueComponent == 0 { black += 1 }
            if pixel.redComponent > 0.99 && pixel.greenComponent > 0.99 && pixel.blueComponent > 0.99 { white += 1 }
        }
    }
    precondition(black > 0 && white > 0 && cutout == 0, "Pure black background and opaque white digit required: \(name)")
    print("PASS · Pure black background and opaque white 1:", name)
}
let info = try PropertyListSerialization.propertyList(from: Data(contentsOf: root.appendingPathComponent("Contents/Info.plist")), format: nil) as! [String: Any]
precondition(info["TISIconIsTemplate"] as? Bool == false)
precondition(info["TICapsLockLanguageSwitchCapable"] == nil)
precondition(info["TISIntendedLanguage"] == nil)
precondition(info["tsInputMethodCharacterRepertoireKey"] as? [String] == ["Latn", "Hans", "Hira", "Kana", "Hang"])
let chinese = try String(contentsOf: root.appendingPathComponent("Contents/Resources/zh-Hans.lproj/InfoPlist.strings"), encoding: .utf8)
precondition(chinese.contains("GuYi输入法"))
print("PASS · Fixed-color menu metadata and Chinese display name")
precondition(info["CFBundleInfoDictionaryVersion"] as? String == "6.0")
precondition(info["CFBundleSupportedPlatforms"] as? [String] == ["MacOSX"])
precondition(info["InputMethodServerControllerClass"] as? String == "GuyiInputController")
precondition(info["InputMethodServerDelegateClass"] as? String == "GuyiInputController")
let identifier = info["CFBundleIdentifier"] as! String
precondition(identifier == "app.guyi.inputmethod.Guyi", "Changing the input-method identity requires an explicit migration")
precondition(info["CFBundleExecutable"] as? String == "guyi")
precondition(info["InputMethodConnectionName"] as? String == identifier + ".Connection", "Client lookup must match the system-derived .Connection alias")
for language in ["zh-Hans", "en", "id", "ja", "ko"] {
    let strings = try Data(contentsOf: root.appendingPathComponent("Contents/Resources/\(language).lproj/InfoPlist.strings"))
    let localized = try PropertyListSerialization.propertyList(from: strings, format: nil) as! [String: String]
    let expected = language == "zh-Hans" ? "GuYi输入法" : ["ja", "ko"].contains(language) ? "GuYi" : "GuYi Input Method"
    precondition(localized[identifier] == expected)
    precondition(localized[identifier + ".pinyin"] == expected)
}
print("PASS · IMK controller/delegate declarations, connection identity, and localized source names")
let menuData = try Data(contentsOf: root.appendingPathComponent("Contents/Resources/input-menu.tiff"))
let representations = NSBitmapImageRep.imageReps(with: menuData)
precondition(representations.count == 2)
precondition(Set(representations.map(\.pixelsWide)) == [22, 44])
precondition(representations.allSatisfy { abs($0.size.width - 22) < 0.1 && abs($0.size.height - 18) < 0.1 })
precondition(info["tsInputMethodIconFileKey"] as? String == "input-menu.tiff")
let modeContainer = info["ComponentInputModeDict"] as! [String: Any]
let modes = modeContainer["tsInputModeListKey"] as! [String: [String: Any]]
precondition(modes.values.allSatisfy { $0["TICapsLockLanguageSwitchCapable"] == nil })
precondition(modes.values.allSatisfy { $0["TISIntendedLanguage"] == nil && $0["tsInputModeCharacterRepertoireKey"] == nil })
precondition(Set(modes.keys) == ["app.guyi.inputmethod.Guyi.pinyin"], "Keep the registered input-mode identity stable across updates")
precondition(modes.values.allSatisfy { $0["tsInputModeMenuIconFileKey"] as? String == "input-menu.tiff" })
print("PASS · TSM-compatible menu TIFF contains 1x and 2x representations with matching logical size")
