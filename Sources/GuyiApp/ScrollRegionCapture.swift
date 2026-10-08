import AppKit
import ScreenCaptureKit

struct ScrollRegionCapture {
    let filter: SCContentFilter
    let configuration: SCStreamConfiguration

    static func prepare(rect: CGRect, pixelSize: CGSize) async throws -> ScrollRegionCapture {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.frame.contains(rect) }) else { throw ScrollCapture.Failure.mismatch }
        let excluded = content.applications.filter { $0.processID == getpid() }
        let filter = SCContentFilter(display: display, excludingApplications: excluded, exceptingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = rect.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
        configuration.width = Int(pixelSize.width)
        configuration.height = Int(pixelSize.height)
        configuration.showsCursor = false
        configuration.capturesAudio = false
        return ScrollRegionCapture(filter: filter, configuration: configuration)
    }

    func capture() async throws -> CGImage {
        try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }
}
