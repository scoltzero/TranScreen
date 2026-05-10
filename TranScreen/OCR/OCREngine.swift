import Vision
import CoreGraphics

struct OCREngine: Sendable {

    struct OCRResult: Sendable {
        let text: String
        let boundingBox: CGRect
        let confidence: Float
    }

    func recognize(
        image: CGImage,
        languages: [String] = ["en-US", "zh-Hans", "zh-Hant", "ja", "ko"]
    ) async throws -> [OCRResult] {
        guard image.width > 10, image.height > 10 else { return [] }

        let request = VNRecognizeTextRequest()
        request.recognitionLanguages = languages
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.minimumTextHeight = 0.0

        let handler = VNImageRequestHandler(cgImage: image, orientation: .up, options: [:])
        try handler.perform([request])

        let observations = request.results ?? []

        #if DEBUG
        print("[OCR] image=\(image.width)x\(image.height) observations=\(observations.count)")
        if observations.isEmpty {
            print("[OCR] No text detected. Languages tried: \(languages)")
        }
        #endif

        return observations.compactMap { obs -> OCRResult? in
            guard let candidate = obs.topCandidates(1).first else { return nil }
            guard candidate.confidence > 0.1 else { return nil }
            return OCRResult(
                text: candidate.string,
                boundingBox: obs.boundingBox,
                confidence: candidate.confidence
            )
        }
    }
}
