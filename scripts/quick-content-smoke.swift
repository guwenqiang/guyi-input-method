import AppKit
import GuyiCore

@main
struct QuickContentSmoke {
    @MainActor static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("guyi-quick-content-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let directory = root.appendingPathComponent("store")
        let store = QuickContentStore(directory: directory)
        for number in 0..<10 { try store.saveText(number: number, title: "Slot \(number)", text: "Line one\nLine two \(number)") }
        precondition(store.entries.count == 10)
        let restored = QuickContentStore(directory: directory)
        precondition(restored.entry(9)?.text == "Line one\nLine two 9")
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        try restored.copy(9, to: pasteboard)
        precondition(pasteboard.string(forType: .string) == "Line one\nLine two 9")
        do { try restored.saveText(number: 10, title: "Invalid", text: "x"); fatalError("Invalid slot accepted") } catch {}
        do { try restored.saveText(number: 0, title: "Oversize", text: String(repeating: "a", count: 65_537)); fatalError("Large text accepted") } catch {}
        let source = root.appendingPathComponent("fixture.txt")
        try Data("synthetic file only".utf8).write(to: source)
        try await restored.saveFile(number: 0, title: "File", source: source)
        precondition(restored.entry(0)?.kind == .file)
        let asset = restored.entry(0)!.asset!
        try FileManager.default.removeItem(at: source)
        try restored.copy(0, to: pasteboard)
        precondition(pasteboard.types?.contains(.fileURL) == true)
        try restored.saveText(number: 0, title: "Replacement", text: "replacement")
        precondition(!FileManager.default.fileExists(atPath: directory.appendingPathComponent(asset).path))
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: directory.appendingPathComponent("index.json"))
        do { try await restored.saveFile(number: 1, title: "Link", source: link); fatalError("Symlink accepted") } catch {}
        let attributes = try FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent("index.json").path)
        precondition((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        try restored.remove(9)
        precondition(restored.entry(9) == nil)
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 8,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                      colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let imageURL = root.appendingPathComponent("fixture.png")
        try bitmap.representation(using: .png, properties: [:])!.write(to: imageURL)
        try await restored.saveFile(number: 2, title: "Image", source: imageURL)
        precondition(restored.entry(2)?.kind == .image)
        try restored.copy(2, to: pasteboard)
        precondition(NSImage(pasteboard: pasteboard) != nil)
        let oversized = root.appendingPathComponent("large.bin")
        FileManager.default.createFile(atPath: oversized.path, contents: Data())
        let handle = try FileHandle(forWritingTo: oversized)
        try handle.truncate(atOffset: UInt64(QuickContentStore.fileLimit + 1))
        try handle.close()
        do { try await restored.saveFile(number: 3, title: "Too big", source: oversized); fatalError("Oversized file accepted") } catch {}
        precondition(restored.entry(3)?.kind == .text)
        print("PASS · Image clipboard and oversized-file rejection preserve the existing slot")
        print("PASS · Ten slots, text clipboard, file snapshot, replacement cleanup, persistence, size and symlink guards")
    }
}
