import CoreGraphics
import AppKit

enum OverlayCoordinateSpace {
    static func screen(containing rect: CGRect) -> NSScreen {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        return NSScreen.screens.first { $0.frame.contains(center) }
            ?? NSScreen.screens.first { $0.frame.intersects(rect) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }

    /// AppKit screen rect (origin at bottom-left) -> overlay-local SwiftUI rect
    /// (origin at top-left). The overlay panel itself is sized to the screen.
    static func localRect(for screenRect: CGRect, in screen: NSScreen? = nil) -> CGRect {
        let resolvedScreen = screen ?? self.screen(containing: screenRect)
        let frame = resolvedScreen.frame
        return CGRect(
            x: screenRect.minX - frame.minX,
            y: frame.maxY - screenRect.maxY,
            width: screenRect.width,
            height: screenRect.height
        )
    }
}

struct CoordinateMapper {
    let screen: NSScreen
    let captureRegion: CGRect
    let imageSize: CGSize
    let scaleFactor: CGFloat

    init(
        screen: NSScreen? = nil,
        captureRegion: CGRect,
        imageSize: CGSize
    ) {
        self.screen = screen ?? OverlayCoordinateSpace.screen(containing: captureRegion)
        self.captureRegion = captureRegion
        self.imageSize = imageSize
        self.scaleFactor = self.screen.backingScaleFactor
    }

    // Vision 归一化 boundingBox (左下角原点) → overlay-local SwiftUI 坐标 (左上角原点)
    func mapToSwiftUI(visionBox: CGRect) -> CGRect {
        // 步骤1: 归一化 → 像素 (Vision Y 向上)
        let pixelX = visionBox.origin.x * imageSize.width
        let pixelY = visionBox.origin.y * imageSize.height
        let pixelW = visionBox.width * imageSize.width
        let pixelH = visionBox.height * imageSize.height

        // 步骤2: 像素 → 逻辑点
        let pointX = pixelX / scaleFactor
        let pointY = pixelY / scaleFactor
        let pointW = pixelW / scaleFactor
        let pointH = pixelH / scaleFactor

        // 步骤3: 图像坐标 → 屏幕坐标 (AppKit Y 向上)
        let screenX = captureRegion.origin.x + pointX
        let screenY = captureRegion.origin.y + pointY

        // 步骤4: AppKit → overlay-local SwiftUI (Y 轴翻转)
        let swiftuiX = screenX - screen.frame.minX
        let swiftuiY = screen.frame.maxY - screenY - pointH

        return CGRect(x: swiftuiX, y: swiftuiY, width: pointW, height: pointH)
    }

    /// Calculate adaptive font size from per-line OCR bounding boxes (Vision normalized).
    /// Each observation is one line of text. Uses median (P50) of line heights so two
    /// blocks with the same actual font size — even if they have different line counts —
    /// resolve to the same font size, while title vs body still come out distinct.
    func adaptiveFontSize(forLineBoxes boxes: [CGRect]) -> CGFloat {
        guard !boxes.isEmpty else { return 14 }
        let heights = boxes.map { mapToSwiftUI(visionBox: $0).height }.sorted()
        let median = heights[heights.count / 2]
        return max(9, min(48, median * 0.85))
    }
}
