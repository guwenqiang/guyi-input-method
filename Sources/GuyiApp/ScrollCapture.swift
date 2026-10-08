import AppKit

enum ScrollCapture {
    static func contains(_ frame: CGImage, in combined: CGImage) -> Bool {
        guard frame.width == combined.width, frame.height <= combined.height, combined.height <= 24_000 else { return false }
        let width = 64
        func pixels(_ image: CGImage) -> [UInt8] {
            var bytes = [UInt8](repeating: 0, count: width * image.height)
            bytes.withUnsafeMutableBytes { buffer in
                guard let context = CGContext(data: buffer.baseAddress, width: width, height: image.height, bitsPerComponent: 8,
                                              bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0) else { return }
                context.interpolationQuality = .low
                context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: image.height))
            }
            return bytes
        }
        let source = pixels(combined), fullCandidate = pixels(frame)
        func rowsMatch(_ sourceRow: Int, _ frameRow: Int) -> Bool {
            (0..<width).allSatisfy { column in abs(Int(source[sourceRow * width + column]) - Int(fullCandidate[frameRow * width + column])) <= 2 }
        }
        var top = 0, bottom = 0
        while top < frame.height / 3 && rowsMatch(top, top) { top += 1 }
        while bottom < frame.height / 3 && rowsMatch(combined.height - bottom - 1, frame.height - bottom - 1) { bottom += 1 }
        let candidate = Array(fullCandidate[(top * width)..<((frame.height - bottom) * width)])
        let height = frame.height - top - bottom
        let anchors = [0, height / 4, height / 2, height * 3 / 4, height - 1]
        for offset in top...(combined.height - bottom - height) {
            let possible = anchors.allSatisfy { row in
                stride(from: 4, to: width - 4, by: 4).allSatisfy { column in
                    abs(Int(source[(offset + row) * width + column]) - Int(candidate[row * width + column])) <= 2
                }
            }
            guard possible else { continue }
            var matches = true
            for index in candidate.indices where abs(Int(source[offset * width + index]) - Int(candidate[index])) > 2 {
                matches = false
                break
            }
            if matches { return true }
        }
        return false
    }
    static func isStable(_ first: CGImage, _ second: CGImage) -> Bool {
        guard first.width == second.width, first.height == second.height else { return false }
        func thumbnail(_ image: CGImage) -> [UInt8] {
            var bytes = [UInt8](repeating: 0, count: 64 * 64)
            bytes.withUnsafeMutableBytes { buffer in
                guard let context = CGContext(data: buffer.baseAddress, width: 64, height: 64, bitsPerComponent: 8,
                                              bytesPerRow: 64, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0) else { return }
                context.draw(image, in: CGRect(x: 0, y: 0, width: 64, height: 64))
            }
            return bytes
        }
        let before = thumbnail(first), after = thumbnail(second)
        return zip(before, after).reduce(0) { $0 + abs(Int($1.0) - Int($1.1)) } < 2048
    }
    static func flipped(_ image: CGImage) -> CGImage {
        let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.translateBy(x: 0, y: CGFloat(image.height))
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage()!
    }

    static func prepend(previous: CGImage, next: CGImage, combined: CGImage) throws -> CGImage {
        flipped(try append(previous: flipped(previous), next: flipped(next), combined: flipped(combined)))
    }
    enum Failure: LocalizedError {
        case mismatch, limit
        var errorDescription: String? {
            switch self {
            case .mismatch: return "无法可靠拼接，请保持窗口位置不变，每次向下滚动不到半屏，并避开固定标题栏。"
            case .limit: return "长截图已达到内存限制，请保存后开始新的截图。"
            }
        }
    }
    static func append(previous: CGImage, next: CGImage, combined: CGImage) throws -> CGImage {
        guard previous.width == next.width, previous.height == next.height else { throw Failure.mismatch }
        let width = 96
        guard previous.height <= 8_000 else { throw Failure.limit }
        let height = previous.height
        func pixels(_ image: CGImage, rows: Int) -> [UInt8] {
            var bytes = [UInt8](repeating: 0, count: width * rows)
            bytes.withUnsafeMutableBytes { buffer in
                let context = CGContext(data: buffer.baseAddress, width: width, height: rows, bitsPerComponent: 8,
                                        bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0)!
                context.interpolationQuality = .low
                context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: rows))
            }
            return bytes
        }
        let old = pixels(previous, rows: height), new = pixels(next, rows: height)
        if zip(old, new).allSatisfy({ abs(Int($0.0) - Int($0.1)) <= 2 }) { return combined }
        func sameRow(_ row: Int) -> Bool {
            (8..<(width - 8)).allSatisfy { column in abs(Int(old[row * width + column]) - Int(new[row * width + column])) <= 2 }
        }
        var fixedTop = 0, fixedBottom = 0
        while fixedTop < height / 3 && sameRow(fixedTop) { fixedTop += 1 }
        while fixedBottom < height / 3 && sameRow(height - fixedBottom - 1) { fixedBottom += 1 }
        func error(_ shift: Int) -> Double {
            let end = height - fixedBottom - shift
            guard end - fixedTop >= 24 else { return .infinity }
            var total = 0, count = 0
            for row in stride(from: fixedTop, to: end, by: max(3, height / 400)) {
                for column in stride(from: 8, to: width - 8, by: 2) {
                    total += abs(Int(old[(row + shift) * width + column]) - Int(new[row * width + column]))
                    count += 1
                }
            }
            return Double(total) / Double(max(1, count))
        }
        let scores = (1..<max(2, height * 3 / 4)).map { ($0, error($0)) }.sorted { $0.1 < $1.1 }
        guard let best = scores.first, best.1 < 4,
              !scores.contains(where: { abs($0.0 - best.0) > 4 && $0.1 < best.1 + 1 }) else { throw Failure.mismatch }
        let shift = best.0
        let outputHeight = combined.height + shift
        guard outputHeight <= 24_000, next.width * outputHeight <= 24_000_000 else { throw Failure.limit }
        let tailHeight = shift + fixedBottom
        guard let base = combined.cropping(to: CGRect(x: 0, y: 0, width: combined.width, height: combined.height - fixedBottom)),
              let tail = next.cropping(to: CGRect(x: 0, y: next.height - tailHeight, width: next.width, height: tailHeight)),
              let context = CGContext(data: nil, width: next.width, height: outputHeight, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw Failure.limit }
        context.draw(base, in: CGRect(x: 0, y: tailHeight, width: base.width, height: base.height))
        context.draw(tail, in: CGRect(x: 0, y: 0, width: tail.width, height: tail.height))
        guard let output = context.makeImage() else { throw Failure.limit }
        return output
    }
}
