import CoreGraphics
import Foundation

struct TranslatedBlock: Identifiable, Sendable {
    let id: UUID
    let originalText: String
    let translatedText: String
    let visionBoundingBox: CGRect
    var captureRegion: CGRect = .zero
    let isVertical: Bool
    var screenRect: CGRect = .zero
    var screenLineRects: [CGRect] = []
    var fontSize: CGFloat = 14
    var bgRed: Double = 1.0
    var bgGreen: Double = 1.0
    var bgBlue: Double = 1.0
    var textR: Double = 0
    var textG: Double = 0
    var textB: Double = 0
    var lineEdges: (left: CGFloat, right: CGFloat)?

    var isLightBackground: Bool {
        BackgroundSampler.isLight(bgRed, bgGreen, bgBlue)
    }

    init(
        originalText: String,
        translatedText: String,
        visionBoundingBox: CGRect,
        isVertical: Bool = false,
        bgRed: Double = 1.0,
        bgGreen: Double = 1.0,
        bgBlue: Double = 1.0
    ) {
        self.id = UUID()
        self.originalText = originalText
        self.translatedText = translatedText
        self.visionBoundingBox = visionBoundingBox
        self.isVertical = isVertical
        self.bgRed = bgRed
        self.bgGreen = bgGreen
        self.bgBlue = bgBlue
    }
}
