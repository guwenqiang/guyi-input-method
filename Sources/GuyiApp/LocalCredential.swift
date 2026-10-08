import Foundation
import Darwin

enum LocalCredential {
    enum ReadResult { case available(String), missing, locked, failed(Int32) }
    private struct Configuration: Codable { let apiKey: String }
    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("guyi/Configuration", isDirectory: true)
    }
    static func readResult(directory: URL = directory) -> ReadResult {
        do {
            let file = directory.appendingPathComponent("credentials.json")
            guard FileManager.default.fileExists(atPath: file.path) else { return .missing }
            try validate(directory)
            try validate(file)
            let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
            guard ((attributes[.size] as? NSNumber)?.intValue ?? Int.max) <= 65_536 else { return .failed(-50) }
            let value = try JSONDecoder().decode(Configuration.self, from: Data(contentsOf: file))
            return value.apiKey.isEmpty ? .missing : .available(value.apiKey)
        } catch { return .failed(-50) }
    }
    static func save(_ key: String, directory: URL = directory) throws {
        let manager = FileManager.default
        if manager.fileExists(atPath: directory.path) { try validate(directory) }
        else { try manager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]) }
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let file = directory.appendingPathComponent("credentials.json")
        if (try? manager.attributesOfItem(atPath: file.path)) != nil { try validate(file) }
        guard !key.isEmpty, key.utf8.count <= 16_384 else { throw CocoaError(.fileWriteInvalidFileName) }
        try JSONEncoder().encode(Configuration(apiKey: key)).write(to: file, options: .atomic)
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        var excluded = file
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? excluded.setResourceValues(values)
    }
    private static func validate(_ url: URL) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType != .typeSymbolicLink,
              (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid() else { throw CocoaError(.fileReadNoPermission) }
    }
}
