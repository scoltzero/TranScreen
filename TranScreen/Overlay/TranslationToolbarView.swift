import SwiftUI
import AppKit
import UniformTypeIdentifiers

private struct ToolbarSizeKey: PreferenceKey {
    static let defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next.width > 0 && next.height > 0 { value = next }
    }
}

struct TranslationToolbar: View {
    @Binding var showingOriginal: Bool
    let region: CGRect
    let onCopy: () -> Void
    let onSaveImage: () -> Bool
    let onDismiss: () -> Void

    @State private var size: CGSize = .zero
    @State private var copied: Bool = false
    @State private var saved: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            Button {
                showingOriginal.toggle()
            } label: {
                Image(systemName: showingOriginal ? "character.book.closed.fill" : "character.book.closed")
                Text(showingOriginal ? "原文" : "译文")
            }
            .buttonStyle(.borderless)
            .help("点击切换原文/译文")

            Divider().frame(height: 16)

            Button {
                onCopy()
                withAnimation(.easeOut(duration: 0.15)) { copied = true }
                Task {
                    try? await Task.sleep(for: .seconds(1.2))
                    withAnimation(.easeOut(duration: 0.2)) { copied = false }
                }
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .foregroundStyle(copied ? .green : .primary)
                Text(copied ? "已复制" : "复制")
                    .foregroundStyle(copied ? .green : .primary)
            }
            .buttonStyle(.borderless)
            .help("复制当前显示的文本")

            Button {
                if onSaveImage() {
                    withAnimation(.easeOut(duration: 0.15)) { saved = true }
                    Task {
                        try? await Task.sleep(for: .seconds(1.2))
                        withAnimation(.easeOut(duration: 0.2)) { saved = false }
                    }
                }
            } label: {
                Image(systemName: saved ? "checkmark" : "photo")
                    .foregroundStyle(saved ? .green : .primary)
                Text(saved ? "已截图" : "截图")
                    .foregroundStyle(saved ? .green : .primary)
            }
            .buttonStyle(.borderless)
            .help("保存当前画面为 PNG")

            Divider().frame(height: 16)

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle")
            }
            .buttonStyle(.borderless)
            .help("关闭翻译叠加层")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.3), lineWidth: 0.5)
        )
        .font(.system(size: 12))
        .foregroundStyle(.primary)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: ToolbarSizeKey.self, value: proxy.size)
            }
        )
        .onPreferenceChange(ToolbarSizeKey.self) { newSize in
            // SwiftUI may re-emit the same size repeatedly; only commit changes.
            if abs(newSize.width - size.width) > 0.5 || abs(newSize.height - size.height) > 0.5 {
                size = newSize
            }
        }
        .position(toolbarCenter)
    }

    /// Anchor: toolbar's top-right corner = selection's bottom-right corner + 4pt gap.
    /// `.position` takes the view's center, so we offset by half-size.
    private var toolbarCenter: CGPoint {
        let screen = OverlayCoordinateSpace.screen(containing: region)
        let localRegion = OverlayCoordinateSpace.localRect(for: region, in: screen)
        let screenH = screen.frame.height
        let screenW = screen.frame.width
        let w = max(size.width, 1)
        let h = max(size.height, 1)
        let gap: CGFloat = 4

        var centerX = localRegion.maxX - w / 2
        var centerY = localRegion.maxY + gap + h / 2

        // Below selection out of screen → flip above selection (bottom edge of toolbar = top of region).
        if localRegion.maxY + gap + h > screenH {
            centerY = localRegion.minY - gap - h / 2
        }
        // Both above and below clipped → tuck inside selection's top-right.
        if centerY - h / 2 < 0 {
            centerY = localRegion.minY + gap + h / 2
        }
        // Right edge clamp (defensive — selection is created on-screen anyway).
        if centerX + w / 2 > screenW {
            centerX = screenW - w / 2 - gap
        }
        if centerX - w / 2 < 0 {
            centerX = w / 2 + gap
        }

        return CGPoint(x: centerX, y: centerY)
    }
}
