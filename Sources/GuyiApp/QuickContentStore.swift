import AppKit
import GuyiCore
import ImageIO

struct QuickContentEntry: Codable, Identifiable {
    enum Kind: String, Codable { case text, image, file }
    let id: Int
    let title: String
    let kind: Kind
    let text: String?
    let asset: String?
}

enum QuickContentError: LocalizedError {
    case invalid, missing, tooLarge, unsafe
    var errorDescription: String? {
        switch self {
        case .invalid: return Localizer.text("编号应为 0–9，标题和内容不能为空。")
        case .missing: return Localizer.text("此内容槽为空或文件已不存在。")
        case .tooLarge: return Localizer.text("文字最多 64 KiB，单个文件最多 10 MiB。")
        case .unsafe: return Localizer.text("无法使用符号链接或不安全的内容存储路径。")
        }
    }
}

@MainActor
final class QuickContentStore: ObservableObject {
    static let shared = QuickContentStore()
    nonisolated static let fileLimit = 10 * 1024 * 1024
    @Published private(set) var entries: [QuickContentEntry] = []
    @Published private(set) var error = ""
    private let directory: URL

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/guyi/QuickContent")
        do {
            try prepareDirectory()
            let index = self.directory.appendingPathComponent("index.json")
            if FileManager.default.fileExists(atPath: index.path) {
                try validateFile(index, maximum: 1_048_576)
                let saved = try JSONDecoder().decode([QuickContentEntry].self, from: Data(contentsOf: index))
                guard saved.count <= 10, Set(saved.map(\.id)).count == saved.count,
                      saved.allSatisfy({ (0...9).contains($0.id) && !$0.title.isEmpty && $0.title.count <= 120
                          && ($0.text?.utf8.count ?? 0) <= 65_536 }) else { throw QuickContentError.invalid }
                entries = saved.sorted { $0.id < $1.id }
            }
        } catch { self.error = error.localizedDescription }
    }

    func entry(_ number: Int) -> QuickContentEntry? { entries.first { $0.id == number } }

    func saveText(number: Int, title: String, text: String) throws {
        try validate(number: number, title: title)
        guard !text.isEmpty else { throw QuickContentError.invalid }
        guard text.utf8.count <= 65_536 else { throw QuickContentError.tooLarge }
        try replace(.init(id: number, title: title, kind: .text, text: text, asset: nil), number: number)
    }

    func saveFile(number: Int, title: String, source: URL) async throws {
        try validate(number: number, title: title)
        let data = try await Task.detached(priority: .utility) {
            let values = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else { throw QuickContentError.unsafe }
            guard (values.fileSize ?? Int.max) <= Self.fileLimit else { throw QuickContentError.tooLarge }
            let handle = try FileHandle(forReadingFrom: source)
            defer { try? handle.close() }
            let data = try handle.read(upToCount: Self.fileLimit + 1) ?? Data()
            guard data.count <= Self.fileLimit else { throw QuickContentError.tooLarge }
            return data
        }.value
        try Task.checkCancellation()
        try prepareDirectory()
        let token = UUID().uuidString
        let folder = directory.appendingPathComponent(token, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let name = source.lastPathComponent
        guard !name.isEmpty, name != ".", name != ".." else { throw QuickContentError.invalid }
        let destination = folder.appendingPathComponent(name)
        do {
            try data.write(to: destination, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
            let kind = try contentKind(data)
            try replace(.init(id: number, title: title, kind: kind, text: nil, asset: token + "/" + name), number: number)
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
    }

    func remove(_ number: Int) throws { try replace(nil, number: number) }

    func copy(_ number: Int, to pasteboard: NSPasteboard = .general) throws {
        guard let value = entry(number) else { throw QuickContentError.missing }
        if value.kind == .text {
            guard let text = value.text, text.utf8.count <= 65_536 else { throw QuickContentError.invalid }
            pasteboard.clearContents()
            guard pasteboard.setString(text, forType: .string) else { throw QuickContentError.invalid }
        } else {
            let url = try assetURL(value)
            try validateFile(url, maximum: Self.fileLimit)
            var image: NSImage?
            if value.kind == .image {
                let data = try Data(contentsOf: url)
                guard try contentKind(data) == .image, let decoded = NSImage(data: data) else { throw QuickContentError.invalid }
                image = decoded
            }
            pasteboard.clearContents()
            let objects: [NSPasteboardWriting] = image.map { [$0] } ?? [url as NSURL]
            guard pasteboard.writeObjects(objects) else { throw QuickContentError.invalid }
        }
    }

    private func validate(number: Int, title: String) throws {
        guard (0...9).contains(number), !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              title.count <= 120 else { throw QuickContentError.invalid }
    }

    private func contentKind(_ data: Data) throws -> QuickContentEntry.Kind {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetType(source) != nil else { return .file }
        guard CGImageSourceGetCount(source) == 1,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 16_000_000 / height else { throw QuickContentError.tooLarge }
        return .image
    }

    private func assetURL(_ entry: QuickContentEntry) throws -> URL {
        guard let asset = entry.asset else { throw QuickContentError.missing }
        let components = asset.split(separator: "/", omittingEmptySubsequences: false)
        guard components.count == 2, UUID(uuidString: String(components[0])) != nil,
              !components[1].isEmpty, components[1] != ".", components[1] != ".." else { throw QuickContentError.unsafe }
        let folder = directory.appendingPathComponent(String(components[0]))
        try validateDirectory(folder)
        return folder.appendingPathComponent(String(components[1]))
    }

    private func prepareDirectory() throws {
        let manager = FileManager.default
        if manager.fileExists(atPath: directory.path) { try validateDirectory(directory) }
        else { try manager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]) }
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    }

    private func validateDirectory(_ url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else { throw QuickContentError.unsafe }
    }

    private func validateFile(_ url: URL, maximum: Int) throws {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else { throw QuickContentError.unsafe }
        guard (values.fileSize ?? Int.max) <= maximum else { throw QuickContentError.tooLarge }
    }

    private func replace(_ value: QuickContentEntry?, number: Int) throws {
        guard (0...9).contains(number) else { throw QuickContentError.invalid }
        try prepareDirectory()
        let previous = entry(number)
        var updated = entries.filter { $0.id != number }
        if let value { updated.append(value) }
        updated.sort { $0.id < $1.id }
        let index = directory.appendingPathComponent("index.json")
        if FileManager.default.fileExists(atPath: index.path) { try validateFile(index, maximum: 1_048_576) }
        try JSONEncoder().encode(updated).write(to: index, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: index.path)
        entries = updated
        error = ""
        if let previous, let old = try? assetURL(previous), previous.asset != value?.asset {
            try? FileManager.default.removeItem(at: old.deletingLastPathComponent())
        }
    }
}
