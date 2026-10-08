import Foundation
import Vision

enum ScreenshotOCR {
    struct Region: Sendable { let text: String; let bounds: CGRect }
    static func recognize(_ data: Data) throws -> [Region] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let supported = try request.supportedRecognitionLanguages()
        request.recognitionLanguages = ["zh-Hans", "en-US", "id-ID"].filter { supported.contains($0) }
        try VNImageRequestHandler(data: data).perform([request])
        return (request.results ?? []).compactMap { observation in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            return Region(text: text, bounds: observation.boundingBox)
        }
    }
}
