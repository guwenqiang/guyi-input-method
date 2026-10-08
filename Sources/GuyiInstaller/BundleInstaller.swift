import AppKit
import Darwin

struct BundleInstallFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

enum BundleInstaller {
    static func runningApplication(_ identifier: String) -> Bool {
        if !NSRunningApplication.runningApplications(withBundleIdentifier: identifier).isEmpty { return true }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-x", identifier == "app.guyi.launcher" ? "GuYi" : "guyi"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do { try process.run(); process.waitUntilExit(); return process.terminationStatus == 0 }
        catch { return true }
    }
    static func metadata(_ bundle: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: bundle.appendingPathComponent("Contents/Info.plist"))
        guard let info = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw BundleInstallFailure(message: "Invalid application metadata.")
        }
        return info
    }

    static func verifySignature(_ bundle: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["--verify", "--deep", "--strict", bundle.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw BundleInstallFailure(message: "Bundle signature verification failed.") }
    }

    static func install(source: URL, destination: URL,
                        verify: (URL) throws -> Void = verifySignature,
                        isRunning: (String) -> Bool = runningApplication) throws {
        let manager = FileManager.default
        let sourceProperties = try source.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard sourceProperties.isDirectory == true, sourceProperties.isSymbolicLink != true else {
            throw BundleInstallFailure(message: "Source must be a real application directory.")
        }
        guard source.standardizedFileURL != destination.standardizedFileURL else {
            throw BundleInstallFailure(message: "Source and destination must differ.")
        }
        let info = try metadata(source)
        guard let identifier = info["CFBundleIdentifier"] as? String,
              ["app.guyi.inputmethod.Guyi", "app.guyi.launcher"].contains(identifier) else {
            throw BundleInstallFailure(message: "Only GuYi bundles can be installed.")
        }
        let parent = destination.deletingLastPathComponent()
        guard parent.standardizedFileURL == parent.resolvingSymlinksInPath().standardizedFileURL,
              !((try? destination.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) ?? false) else {
            throw BundleInstallFailure(message: "Refusing a symlink installation destination.")
        }
        if isRunning(identifier) { throw BundleInstallFailure(message: "Quit GuYi before updating. No files were replaced.") }
        try verify(source)
        let existing = manager.fileExists(atPath: destination.path)
        if existing {
            let installed = try metadata(destination)
            guard installed["CFBundleIdentifier"] as? String == identifier else {
                throw BundleInstallFailure(message: "Destination belongs to a different application.")
            }
            if identifier == "app.guyi.inputmethod.Guyi" {
                for key in ["CFBundleExecutable", "TISInputSourceID"] {
                    guard installed[key] as? String == info[key] as? String else {
                        throw BundleInstallFailure(message: "Input-method identity migration requires an explicit migration plan: \(key)")
                    }
                }
                let previousConnection = installed["InputMethodConnectionName"] as? String
                let nextConnection = info["InputMethodConnectionName"] as? String
                let modernConnectionMigration = (previousConnection == identifier + "_Connection" || installed["InputMethodConnectionName"] == nil)
                    && nextConnection == identifier + ".Connection"
                    && info["LSMinimumSystemVersion"] as? String == "26.0"
                guard previousConnection == nextConnection || modernConnectionMigration else {
                    throw BundleInstallFailure(message: "Unsupported input-method connection migration.")
                }
                func modes(_ info: [String: Any]) -> Set<String> {
                    let container = info["ComponentInputModeDict"] as? [String: Any]
                    return Set((container?["tsInputModeListKey"] as? [String: Any] ?? [:]).keys)
                }
                guard modes(installed) == modes(info) else {
                    throw BundleInstallFailure(message: "Input-mode IDs must remain stable during updates.")
                }
            }
        }
        let staging = parent.appendingPathComponent(".guyi-update-\(UUID().uuidString).noindex", isDirectory: true)
        try manager.createDirectory(at: staging, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        var cleanStaging = true
        defer { if cleanStaging { try? manager.removeItem(at: staging) } }
        let payload = staging.appendingPathComponent("Payload.app", isDirectory: true)
        try manager.copyItem(at: source, to: payload)
        if geteuid() == 0 {
            let ownership = Process()
            ownership.executableURL = URL(fileURLWithPath: "/usr/sbin/chown")
            ownership.arguments = ["-R", "-P", "root:wheel", payload.path]
            try ownership.run()
            ownership.waitUntilExit()
            guard ownership.terminationStatus == 0 else { throw BundleInstallFailure(message: "Unable to set system bundle ownership.") }
        }
        try verify(payload)
        guard !isRunning(identifier) else { throw BundleInstallFailure(message: "GuYi relaunched during preparation; update cancelled before replacement.") }
        if existing {
            guard renameatx_np(AT_FDCWD, payload.path, AT_FDCWD, destination.path, UInt32(RENAME_SWAP)) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        } else {
            guard rename(payload.path, destination.path) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        }
        do { try verify(destination) }
        catch {
            let restored = existing
                ? renameatx_np(AT_FDCWD, payload.path, AT_FDCWD, destination.path, UInt32(RENAME_SWAP))
                : rename(destination.path, payload.path)
            if restored != 0 {
                cleanStaging = false
                throw BundleInstallFailure(message: "Verification and rollback failed. Recovery bundle retained at \(staging.path)")
            }
            throw error
        }
        print("Installed complete, verified GuYi bundle:", destination.path)
    }
}
