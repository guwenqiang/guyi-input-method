import Foundation
import Combine
import Darwin
import GuyiCore

@MainActor final class ServiceProfiles: ObservableObject {
    static let shared = ServiceProfiles()
    @Published private(set) var saved = ServiceProfileCollection()
    private var tail: Task<Void, Error>?
    private var pending = ServiceProfileCollection()
    private var revision = 0
    private var completedRevision = 0
    private let file: URL
    init(file: URL = LocalCredential.directory.appendingPathComponent("service-profiles.json")) {
        self.file = file
        if let data = try? Self.read(file), let profiles = try? JSONDecoder().decode(ServiceProfileCollection.self, from: data),
           profiles.profiles.count <= 128, profiles.profiles.allSatisfy(\.isComplete) { saved = profiles; pending = profiles }
    }
    func remember(settings: TranslationSettings, key: String, name: String? = nil, id selectedID: String? = nil) async throws {
        let id = selectedID ?? pending.profiles.first(where: {
            $0.endpoint == settings.endpoint && $0.apiProtocol == settings.effectiveAPIProtocol &&
                $0.model == settings.model && $0.apiKey == key
        })?.id ?? ServiceProfile.profileID(endpoint: settings.endpoint, protocol: settings.effectiveAPIProtocol)
        let existingName = pending.profiles.first(where: { $0.id == id })?.name
        let profile = ServiceProfile(settings: settings, key: key, name: name ?? existingName, id: id)
        guard profile.isComplete else { return }
        if saved.profiles.contains(profile), pending.profiles.contains(profile) { return }
        var next = pending
        next.remember(profile)
        guard next.profiles.count <= 128 else { throw CocoaError(.fileWriteOutOfSpace) }
        let data = try JSONEncoder().encode(next), file = file, previous = tail
        pending = next; revision += 1
        let version = revision
        let write = Task.detached {
            // A previous failed write must not prevent a later retry.
            _ = try? await previous?.value
            try Self.write(data, to: file)
        }
        tail = write
        try await write.value
        if version > completedRevision { saved = next; completedRevision = version }
    }
    private nonisolated static func validate(_ url: URL, directory: Bool) throws {
        let a = try FileManager.default.attributesOfItem(atPath: url.path)
        guard a[.type] as? FileAttributeType == (directory ? .typeDirectory : .typeRegular),
              (a[.ownerAccountID] as? NSNumber)?.uint32Value == getuid() else { throw CocoaError(.fileReadNoPermission) }
    }
    private nonisolated static func read(_ file: URL) throws -> Data {
        try validate(file.deletingLastPathComponent(), directory: true)
        try validate(file, directory: false)
        let a = try FileManager.default.attributesOfItem(atPath: file.path)
        guard (a[.size] as? Int ?? Int.max) <= 2_097_152 else { throw CocoaError(.fileReadTooLarge) }
        return try Data(contentsOf: file)
    }
    private nonisolated static func write(_ data: Data, to file: URL) throws {
        let directory = file.deletingLastPathComponent(), fm = FileManager.default
        if fm.fileExists(atPath: directory.path) { try validate(directory, directory: true) }
        else { try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]) }
        if fm.fileExists(atPath: file.path) { try validate(file, directory: false) }
        guard data.count <= 2_097_152 else { throw CocoaError(.fileWriteOutOfSpace) }
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        try data.write(to: file, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        var target = file, values = URLResourceValues(); values.isExcludedFromBackup = true
        try? target.setResourceValues(values)
    }
}
