import Foundation
import AppKit

guard CommandLine.arguments.count == 3 else {
    fputs("Usage: InstallGuYi source.app destination.app\n", stderr)
    exit(2)
}
guard (CGSessionCopyCurrentDictionary() as NSDictionary?)?["CGSSessionScreenIsLocked"] as? Bool != true else {
    fputs("Unlock macOS before installing GuYi.\n", stderr)
    exit(2)
}
do {
    try BundleInstaller.install(source: URL(fileURLWithPath: CommandLine.arguments[1]),
                                destination: URL(fileURLWithPath: CommandLine.arguments[2]))
} catch {
    fputs("GuYi update failed: \(error.localizedDescription)\n", stderr)
    exit(1)
}
