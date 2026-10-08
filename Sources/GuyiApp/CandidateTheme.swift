import SwiftUI
import GuyiCore

struct CandidateTheme {
    let background: Color
    let accent: Color
    let dark: Bool
    private let custom: Bool
    var selectedText: Color { custom && Self.luminance(NSColor(accent)) > 0.179 ? .black : .white }
    init(settings: TranslationSettings) {
        custom = settings.candidateTheme == "custom"
        switch settings.candidateTheme ?? "dark" {
        case "light": background = Color(red:0.98,green:0.98,blue:0.99);accent = Color(red:0.02,green:0.40,blue:0.90);dark=false
        case "custom":
            let base=Self.color(settings.candidateBackgroundHex ?? "1C1C1C") ?? .init(white:0.11,alpha:1)
            background=Color(nsColor:base)
            accent=Color(nsColor:Self.color(settings.candidateAccentHex ?? "087BFF") ?? .systemBlue)
            dark=Self.luminance(base)<0.179
        default: background=Color(red:0.11,green:0.11,blue:0.11);accent=Color(red:0.02,green:0.48,blue:1);dark=true
        }
    }
    static func color(_ hex:String)->NSColor? {
        let text=hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard text.count==6,let number=UInt32(text,radix:16) else{return nil}
        return NSColor(srgbRed:CGFloat((number>>16)&255)/255,green:CGFloat((number>>8)&255)/255,blue:CGFloat(number&255)/255,alpha:1)
    }
    static func hex(_ color:Color)->String {
        let c=NSColor(color).usingColorSpace(.sRGB) ?? .systemBlue
        return String(format:"%02X%02X%02X",Int(c.redComponent*255),Int(c.greenComponent*255),Int(c.blueComponent*255))
    }
    static func luminance(_ color:NSColor)->CGFloat {
        let c=color.usingColorSpace(.sRGB) ?? color
        func linear(_ value: CGFloat) -> CGFloat { value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4) }
        return 0.2126*linear(c.redComponent)+0.7152*linear(c.greenComponent)+0.0722*linear(c.blueComponent)
    }
}
