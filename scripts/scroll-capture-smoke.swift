import AppKit

@main
struct ScrollCaptureSmoke {
    static func main() throws {
        let width = 384, height = 3000
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        var seed: UInt64 = 73819
        for row in 0..<height {
            seed = seed &* 6364136223846793005 &+ 1
            let rowValue = Int((seed >> 32) % 241)
            for column in 0..<width {
                let offset = (row * width + column) * 4
                let value = UInt8((rowValue + column * 17) % 241)
                bytes[offset] = value
                bytes[offset + 1] = value
                bytes[offset + 2] = value
            }
        }
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        let source = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                             bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                             bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                             provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        let first = source.cropping(to: CGRect(x: 0, y: 0, width: width, height: 400))!
        let second = source.cropping(to: CGRect(x: 0, y: 150, width: width, height: 400))!
        let result = try ScrollCapture.append(previous: first, next: second, combined: first)
        func rgba(_ image: CGImage) -> Data {
            let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                    bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return Data(bytes: context.data!, count: image.width * image.height * 4)
        }
        let expected = source.cropping(to: CGRect(x: 0, y: 0, width: width, height: 550))!
        precondition(rgba(result) == rgba(expected), "Stitched pixel content must match original document")
        precondition(ScrollCapture.isStable(first, first))
        precondition(!ScrollCapture.isStable(first, second))
        precondition(result.height == 550, "Wrong stitched height: \(result.height)")
        let duplicate = try ScrollCapture.append(previous: second, next: second, combined: result)
        precondition(duplicate.height == result.height)
        let upward = try ScrollCapture.prepend(previous: second, next: first, combined: second)
        precondition(upward.height == 550)
        precondition(rgba(upward) == rgba(expected), "Upward stitching preserves exact document pixels")
        let inside = source.cropping(to: CGRect(x: 0, y: 75, width: width, height: 400))!
        precondition(ScrollCapture.contains(inside, in: result), "Returning to an already captured interior must not append duplicates")
        let tiny = source.cropping(to: CGRect(x: 0, y: 1, width: width, height: 400))!
        let tinyResult = try ScrollCapture.append(previous: first, next: tiny, combined: first)
        precondition(tinyResult.height == 401, "Slow scrolling one pixel must stitch")
        let tallFirst = source.cropping(to: CGRect(x: 0, y: 0, width: width, height: 1200))!
        let tallSecond = source.cropping(to: CGRect(x: 0, y: 151, width: width, height: 1200))!
        let tallResult = try ScrollCapture.append(previous: tallFirst, next: tallSecond, combined: tallFirst)
        precondition(tallResult.height == 1351, "Retina overlap must preserve exact pixel rows")
        func framed(_ image: CGImage) -> CGImage {
            let context = CGContext(data: nil, width: image.width, height: image.height + 40, bitsPerComponent: 8, bytesPerRow: 0,
                                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.setFillColor(CGColor(gray: 0.1, alpha: 1))
            context.fill(CGRect(x: 0, y: image.height + 16, width: image.width, height: 24))
            context.setFillColor(CGColor(gray: 0.8, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: image.width, height: 16))
            context.draw(image, in: CGRect(x: 0, y: 16, width: image.width, height: image.height))
            return context.makeImage()!
        }
        let framedFirst = framed(first), framedSecond = framed(second)
        let framedResult = try ScrollCapture.append(previous: framedFirst, next: framedSecond, combined: framedFirst)
        precondition(rgba(framedResult) == rgba(framed(expected)), "Fixed header/footer must occur only once without losing content")
        precondition(ScrollCapture.contains(framed(inside), in: framedResult), "Returning within fixed-header content must not duplicate it")
        let unrelated = source.cropping(to: CGRect(x: 0, y: 600, width: width, height: 400))!
        precondition(!ScrollCapture.contains(unrelated, in: result), "Uncaptured frame cannot be marked as a duplicate")
        do {
            _ = try ScrollCapture.append(previous: second, next: unrelated, combined: result)
            fatalError("Unrelated frames must be rejected")
        } catch ScrollCapture.Failure.mismatch {}
        print("PASS · Scrolling overlap, duplicate frame, and unreliable overlap rejection")
    }
}
