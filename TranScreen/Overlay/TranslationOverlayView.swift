import SwiftUI

struct TranslationOverlayView: View {
    let blocks: [TranslatedBlock]
    let opacity: Double
    let showingOriginal: Bool
    var debugCapturedSize: CGSize = .zero
    var debugOCRCount: Int = 0

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Color.black.opacity(opacity)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                // 调试角标
                if !blocks.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("blocks: \(blocks.count)  ocr: \(debugOCRCount)")
                        Text("captured: \(Int(debugCapturedSize.width))×\(Int(debugCapturedSize.height))px")
                        Text("geo: \(Int(geo.size.width))×\(Int(geo.size.height))")
                    }
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.yellow)
                    .padding(6)
                    .background(Color.black.opacity(0.85))
                    .cornerRadius(4)
                    .position(x: 140, y: 40)
                    .allowsHitTesting(false)
                }

                ForEach(blocks) { block in
                    // Width is hard-locked to the OCR box width so translations
                    // never extend past the original text region. Height is left
                    // unbounded — the text wraps within maxW and grows downward
                    // as needed, instead of overflowing horizontally off-screen.
                    let maxW = max(30, block.screenRect.width)
                    let xOffset = clamp(block.screenRect.minX,
                                        min: 0,
                                        max: max(0, geo.size.width - maxW))
                    let yOffset = max(0, block.screenRect.minY - 1)

                    ForEach(Array(textCoverRects(for: block).enumerated()), id: \.offset) { _, rect in
                        backgroundForBlock(block)
                            .frame(width: rect.width, height: rect.height)
                            .offset(x: rect.minX, y: rect.minY)
                            .allowsHitTesting(false)
                    }

                    translationLabel(for: block)
                        .frame(width: maxW, alignment: .topLeading)
                        .fixedSize(horizontal: false, vertical: true)
                        .background(backgroundForBlock(block))
                        .allowsHitTesting(false)
                        .offset(x: xOffset, y: yOffset)
                }
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - Label

    @ViewBuilder
    private func translationLabel(for block: TranslatedBlock) -> some View {
        let displayText: String = {
            if showingOriginal {
                block.originalText
            } else {
                block.translatedText.isEmpty ? block.originalText : block.translatedText
            }
        }()
        let size = block.fontSize

        Text(displayText.isEmpty ? "[空]" : displayText)
            .font(.system(size: size, weight: .regular, design: .default))
            .foregroundStyle(textColor(for: block))
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .rotationEffect(block.isVertical ? .degrees(90) : .degrees(0))
    }

    // MARK: - Text color

    private func textColor(for block: TranslatedBlock) -> Color {
        let hasTextSample = block.textR > 0.01 || block.textG > 0.01 || block.textB > 0.01
        if hasTextSample {
            return Color(red: block.textR, green: block.textG, blue: block.textB)
        }
        return block.isLightBackground ? .black : .white
    }

    // MARK: - Background

    private func backgroundForBlock(_ block: TranslatedBlock) -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Color(red: block.bgRed, green: block.bgGreen, blue: block.bgBlue))
    }

    private func textCoverRects(for block: TranslatedBlock) -> [CGRect] {
        let rects = block.screenLineRects.isEmpty ? [block.screenRect] : block.screenLineRects
        return rects.map {
            $0.insetBy(dx: -3, dy: -2)
        }
    }

    // MARK: - Helpers

    private func clamp(_ value: CGFloat, min lower: CGFloat, max upper: CGFloat) -> CGFloat {
        Swift.max(lower, Swift.min(upper, value))
    }
}

struct RegionMaskView: View {
    let selectedRegion: CGRect
    let dimOpacity: Double

    var body: some View {
        Canvas { context, size in
            let fullRect = CGRect(origin: .zero, size: size)
            context.fill(Path(fullRect), with: .color(.black.opacity(dimOpacity)))
            context.blendMode = .clear
            context.fill(Path(selectedRegion), with: .color(.black))
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .overlay(
            Rectangle()
                .stroke(Color.white.opacity(0.8), lineWidth: 1.5)
                .frame(width: selectedRegion.width, height: selectedRegion.height)
                .position(x: selectedRegion.midX, y: selectedRegion.midY)
                .allowsHitTesting(false)
        )
        .overlay(cornerIndicators)
    }

    private var cornerIndicators: some View {
        let cornerLen: CGFloat = 20
        let lineWidth: CGFloat = 2
        let color = Color.white.opacity(0.9)
        let r = selectedRegion

        return Canvas { context, _ in
            // Top-left corner
            var path = Path()
            path.move(to: CGPoint(x: r.minX, y: r.minY + cornerLen))
            path.addLine(to: CGPoint(x: r.minX, y: r.minY))
            path.addLine(to: CGPoint(x: r.minX + cornerLen, y: r.minY))
            context.stroke(path, with: .color(color), lineWidth: lineWidth)

            // Top-right corner
            path = Path()
            path.move(to: CGPoint(x: r.maxX - cornerLen, y: r.minY))
            path.addLine(to: CGPoint(x: r.maxX, y: r.minY))
            path.addLine(to: CGPoint(x: r.maxX, y: r.minY + cornerLen))
            context.stroke(path, with: .color(color), lineWidth: lineWidth)

            // Bottom-left corner
            path = Path()
            path.move(to: CGPoint(x: r.minX, y: r.maxY - cornerLen))
            path.addLine(to: CGPoint(x: r.minX, y: r.maxY))
            path.addLine(to: CGPoint(x: r.minX + cornerLen, y: r.maxY))
            context.stroke(path, with: .color(color), lineWidth: lineWidth)

            // Bottom-right corner
            path = Path()
            path.move(to: CGPoint(x: r.maxX - cornerLen, y: r.maxY))
            path.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
            path.addLine(to: CGPoint(x: r.maxX, y: r.maxY - cornerLen))
            context.stroke(path, with: .color(color), lineWidth: lineWidth)
        }
        .allowsHitTesting(false)
    }
}

struct SelectionCornerBorderView: View {
    let screenRegion: CGRect

    var body: some View {
        let screen = OverlayCoordinateSpace.screen(containing: screenRegion)
        let region = OverlayCoordinateSpace.localRect(for: screenRegion, in: screen)

        Canvas { context, _ in
            let cornerLen = min(max(min(region.width, region.height) * 0.16, 14), 28)
            let lineWidth: CGFloat = 1.4
            let color = Color.black.opacity(0.92)

            context.stroke(cornerPath(
                from: CGPoint(x: region.minX, y: region.minY + cornerLen),
                through: CGPoint(x: region.minX, y: region.minY),
                to: CGPoint(x: region.minX + cornerLen, y: region.minY)
            ), with: .color(color), lineWidth: lineWidth)
            context.stroke(cornerPath(
                from: CGPoint(x: region.maxX - cornerLen, y: region.minY),
                through: CGPoint(x: region.maxX, y: region.minY),
                to: CGPoint(x: region.maxX, y: region.minY + cornerLen)
            ), with: .color(color), lineWidth: lineWidth)
            context.stroke(cornerPath(
                from: CGPoint(x: region.minX, y: region.maxY - cornerLen),
                through: CGPoint(x: region.minX, y: region.maxY),
                to: CGPoint(x: region.minX + cornerLen, y: region.maxY)
            ), with: .color(color), lineWidth: lineWidth)
            context.stroke(cornerPath(
                from: CGPoint(x: region.maxX - cornerLen, y: region.maxY),
                through: CGPoint(x: region.maxX, y: region.maxY),
                to: CGPoint(x: region.maxX, y: region.maxY - cornerLen)
            ), with: .color(color), lineWidth: lineWidth)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private func cornerPath(
        from start: CGPoint,
        through corner: CGPoint,
        to end: CGPoint
    ) -> Path {
        var path = Path()
        path.move(to: start)
        path.addLine(to: corner)
        path.addLine(to: end)
        return path
    }
}
