import AppKit

@MainActor
final class Launcher: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        launchSettings()
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        launchSettings()
        return true
    }
    private func launchSettings() {
        let directories = [URL(fileURLWithPath: "/Library/Input Methods"),
                           FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Input Methods")]
        let names = ["GuYi输入法.app", "GuYi Input Method.app", "Guyi.app"]
        guard let inputMethod = directories.flatMap({ directory in names.map { directory.appendingPathComponent($0) } }).first(where: {
            Bundle(url: $0)?.bundleIdentifier == "app.guyi.inputmethod.Guyi"
        }) else {
            let alert = NSAlert()
            alert.messageText = NSLocalizedString("LauncherInstallTitle", comment: "")
            alert.informativeText = NSLocalizedString("LauncherInstallHelp", comment: "")
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        if NSRunningApplication.runningApplications(withBundleIdentifier: "app.guyi.inputmethod.Guyi").contains(where: {
            $0.bundleURL?.standardizedFileURL == inputMethod.standardizedFileURL
        }) {
            DistributedNotificationCenter.default().postNotificationName(Notification.Name("guyi.showSettings"), object: nil, deliverImmediately: true)
            NSApp.terminate(nil)
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [inputMethod.path, "--args", "--settings"]
        do {
            try process.run()
            NSApp.terminate(nil)
        } catch {
            NSAlert(error: error).runModal()
            NSApp.terminate(nil)
        }
    }
}

MainActor.assumeIsolated {
    let delegate = Launcher()
    let application = NSApplication.shared
    application.setActivationPolicy(.regular)
    application.delegate = delegate
    withExtendedLifetime(delegate) { application.run() }
}
