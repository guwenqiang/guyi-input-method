import Foundation

@main
struct InstallerSmoke {
    static func main() throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent("guyi-install-" + UUID().uuidString).resolvingSymlinksInPath()
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }
        func bundle(_ name: String, content: String, connection: String? = "app.guyi.inputmethod.Guyi.Connection") throws -> URL {
            let location = root.appendingPathComponent(name + ".app")
            try manager.createDirectory(at: location.appendingPathComponent("Contents"), withIntermediateDirectories: true)
            var info: [String: Any] = ["CFBundleIdentifier": "app.guyi.inputmethod.Guyi", "CFBundleExecutable": "guyi",
                                       "TISInputSourceID": "app.guyi.inputmethod.Guyi", "LSMinimumSystemVersion": "26.0",
                                       "ComponentInputModeDict": ["tsInputModeListKey": ["app.guyi.inputmethod.Guyi.pinyin": [:]]]]
            if let connection { info["InputMethodConnectionName"] = connection }
            try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: location.appendingPathComponent("Contents/Info.plist"))
            try Data(content.utf8).write(to: location.appendingPathComponent("Contents/payload"))
            return location
        }
        let source = try bundle("New", content: "new")
        let destination = try bundle("Installed", content: "old", connection: "app.guyi.inputmethod.Guyi_Connection")
        let oldInode = try manager.attributesOfItem(atPath: destination.appendingPathComponent("Contents/payload").path)[.systemFileNumber] as! NSNumber
        var verified: [String] = []
        try BundleInstaller.install(source: source, destination: destination, verify: { location in
            verified.append(location.lastPathComponent)
            precondition(manager.fileExists(atPath: location.appendingPathComponent("Contents/payload").path))
        }, isRunning: { _ in false })
        precondition(verified.count == 3)
        let migrated = try BundleInstaller.metadata(destination)
        precondition(migrated["InputMethodConnectionName"] as? String == "app.guyi.inputmethod.Guyi.Connection")
        let intermediate = try bundle("Intermediate", content: "old", connection: nil)
        try BundleInstaller.install(source: source, destination: intermediate, verify: { _ in }, isRunning: { _ in false })
        let installedPayload = try String(contentsOf: destination.appendingPathComponent("Contents/payload"), encoding: .utf8)
        precondition(installedPayload == "new")
        let newInode = try manager.attributesOfItem(atPath: destination.appendingPathComponent("Contents/payload").path)[.systemFileNumber] as! NSNumber
        precondition(oldInode != newInode)
        let rejected = try bundle("Rejected", content: "rejected")
        do {
            try BundleInstaller.install(source: rejected, destination: destination, verify: { location in
                if location == destination { throw BundleInstallFailure(message: "Fixture post-swap failure") }
            }, isRunning: { _ in false })
            fatalError("Verification failure accepted")
        } catch {}
        let restoredPayload = try String(contentsOf: destination.appendingPathComponent("Contents/payload"), encoding: .utf8)
        precondition(restoredPayload == "new")
        do {
            try BundleInstaller.install(source: source, destination: destination, verify: { _ in }, isRunning: { _ in true })
            fatalError("Running application overwritten")
        } catch {}
        let changed = try bundle("Changed", content: "changed", connection: "DifferentConnection")
        do {
            try BundleInstaller.install(source: changed, destination: destination, verify: { _ in }, isRunning: { _ in false })
            fatalError("Changed connection accepted")
        } catch {}
        let link = root.appendingPathComponent("Link.app")
        try manager.createSymbolicLink(at: link, withDestinationURL: destination)
        do {
            try BundleInstaller.install(source: source, destination: link, verify: { _ in }, isRunning: { _ in false })
            fatalError("Symlink destination accepted")
        } catch {}
        let remaining = try manager.contentsOfDirectory(atPath: root.path)
        precondition(remaining.allSatisfy { !$0.hasPrefix(".guyi-update-") })
        print("PASS · Whole-bundle swap, new inode, verification rollback, running-process guard, identity and symlink protection")
        if CommandLine.arguments.count == 2 {
            let signedSource = URL(fileURLWithPath: CommandLine.arguments[1])
            let signedTarget = root.appendingPathComponent("Signed.app")
            try BundleInstaller.install(source: signedSource, destination: signedTarget, isRunning: { _ in false })
            let previousExecutable = try manager.attributesOfItem(atPath: signedTarget.appendingPathComponent("Contents/MacOS/guyi").path)[.systemFileNumber] as! NSNumber
            try BundleInstaller.install(source: signedSource, destination: signedTarget, isRunning: { _ in false })
            let replacedExecutable = try manager.attributesOfItem(atPath: signedTarget.appendingPathComponent("Contents/MacOS/guyi").path)[.systemFileNumber] as! NSNumber
            precondition(previousExecutable != replacedExecutable)
            print("PASS · Real signed GuYi bundle verifies before staging, after replacement, and after an update")
        }
    }
}
