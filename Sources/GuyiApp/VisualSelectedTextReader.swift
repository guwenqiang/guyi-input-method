import AppKit
import Vision

/// Fallback for custom-rendered selections that are visible but absent from AX.
/// Captured pixels stay in memory; only highlighted text is recognized.
@MainActor
final class VisualSelectedTextReader {
    func read(pid: pid_t, start: NSPoint, end: NSPoint) async -> (String, NSRect)? {
        guard CGPreflightScreenCaptureAccess(),
              let screen = NSScreen.screens.first(where: { $0.frame.contains(start) && $0.frame.contains(end) }) else { return nil }
        let width = abs(end.x - start.x), height = abs(end.y - start.y)
        let pad: CGFloat = 32
        let multiline = height > 18
        let pointSelection = width < 4 && height < 4
        let region = NSRect(x: pointSelection ? end.x - 110 : min(start.x, end.x) - pad,
                            y: pointSelection ? end.y - 25 : min(start.y, end.y) - pad,
                            width: pointSelection ? 220 : max(width + pad + (multiline ? 320 : pad), 32),
                            height: pointSelection ? 50 : max(height + pad * 2, 32))
            .intersection(screen.frame)
        guard region.width >= 24, region.height >= 24, region.width <= 1_200, region.height <= 700,
              ownsVisibleWindow(pid: pid, at: end) else { return nil }
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        let captureRect = CGRect(x: region.minX, y: top - region.maxY, width: region.width, height: region.height)
        do {
            let capture = try await ScrollRegionCapture.prepare(rect: captureRect,
                pixelSize: CGSize(width: region.width * screen.backingScaleFactor,
                                  height: region.height * screen.backingScaleFactor))
            let image = try await capture.capture()
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
                  ownsVisibleWindow(pid: pid, at: end),
                  let result = try await Task.detached(priority: .userInitiated, operation: {
                      try Self.recognizeHighlightedText(image)
                  }).value else { return nil }
            let scaleX = region.width / CGFloat(image.width), scaleY = region.height / CGFloat(image.height)
            let box = NSRect(x: region.minX + result.1.minX * scaleX,
                             y: region.maxY - result.1.maxY * scaleY,
                             width: result.1.width * scaleX, height: result.1.height * scaleY)
            return (result.0, box)
        } catch { return nil }
    }

    private func ownsVisibleWindow(pid: pid_t, at point: NSPoint) -> Bool {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return false }
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        let location = CGPoint(x: point.x, y: top - point.y)
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        for window in windows {
            guard window[kCGWindowOwnerPID as String] as? pid_t == pid,
                  window[kCGWindowLayer as String] as? Int == 0,
                  let values = window[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: values as CFDictionary), bounds.contains(location) else { continue }
            return true
        }
        return false
    }

    nonisolated static func recognizeHighlightedText(_ image: CGImage) throws -> (String, CGRect)? {
        let bitmap = NSBitmapImageRep(cgImage: image)
        let width = bitmap.pixelsWide, height = bitmap.pixelsHigh
        guard width >= 24, height >= 16 else { return nil }
        var rows: [(Int, Int, Int)] = []
        for y in 0..<height {
            var minimum = width, maximum = -1, count = 0
            for x in 0..<width {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let r = color.redComponent, g = color.greenComponent, b = color.blueComponent
                let blueSelection = b > 0.58 && g > r + 0.08 && b > g + 0.07 && b > r + 0.18
                let greenSelection = g > 0.58 && g > r + 0.11 && g > b + 0.04 && b > r + 0.06
                if blueSelection || greenSelection {
                    minimum = min(minimum, x); maximum = max(maximum, x); count += 1
                }
            }
            if count >= 8, maximum - minimum >= 8 { rows.append((y, minimum, maximum)) }
        }
        guard !rows.isEmpty else { return nil }
        var bands: [CGRect] = []
        var first = rows[0].0, last = first, left = rows[0].1, right = rows[0].2
        for row in rows.dropFirst() {
            if row.0 - last > 3 {
                if last - first >= 9 { bands.append(CGRect(x: left, y: first, width: right - left + 1, height: last - first + 1)) }
                first = row.0; left = row.1; right = row.2
            } else { left = min(left, row.1); right = max(right, row.2) }
            last = row.0
        }
        if last - first >= 9 { bands.append(CGRect(x: left, y: first, width: right - left + 1, height: last - first + 1)) }
        guard !bands.isEmpty, bands.count <= 12,
              bands.allSatisfy({ $0.minX > 2 && $0.maxX < CGFloat(width - 3) }) else { return nil }
        var lines: [String] = []
        for band in bands {
            let padded = band.insetBy(dx: -3, dy: -3).intersection(CGRect(x: 0, y: 0, width: width, height: height)).integral
            guard let crop = image.cropping(to: padded) else { continue }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            request.recognitionLanguages = ["en-US", "zh-Hans"]
            try VNImageRequestHandler(cgImage: crop).perform([request])
            let line = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
            if !line.isEmpty { lines.append(line) }
        }
        let text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 4_000 else { return nil }
        return (text, bands.reduce(bands[0]) { $0.union($1) })
    }
}
