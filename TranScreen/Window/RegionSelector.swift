import AppKit

final class RegionSelectorView: NSView {
    var onRegionSelected: ((CGRect) -> Void)?
    var onCancelled: (() -> Void)?

    private var startPoint: NSPoint?
    private var currentRect: NSRect = .zero
    private var isDragging = false

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        currentRect = .zero
        isDragging = false
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = startPoint else { return }
        isDragging = true
        let current = convert(event.locationInWindow, from: nil)
        currentRect = NSRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard isDragging, currentRect.width > 10, currentRect.height > 10 else {
            onCancelled?()
            return
        }
        // 转换为屏幕坐标（AppKit: 左下角原点）
        let screenRect = window?.convertToScreen(currentRect) ?? currentRect
        onRegionSelected?(screenRect)
        startPoint = nil
        currentRect = .zero
        isDragging = false
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onCancelled?() }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard isDragging, !currentRect.isEmpty else { return }

        drawCornerBorder(in: currentRect)
    }

    private func drawCornerBorder(in rect: NSRect) {
        let cornerLen = min(max(min(rect.width, rect.height) * 0.16, 14), 28)
        let path = NSBezierPath()

        path.move(to: NSPoint(x: rect.minX, y: rect.maxY - cornerLen))
        path.line(to: NSPoint(x: rect.minX, y: rect.maxY))
        path.line(to: NSPoint(x: rect.minX + cornerLen, y: rect.maxY))

        path.move(to: NSPoint(x: rect.maxX - cornerLen, y: rect.maxY))
        path.line(to: NSPoint(x: rect.maxX, y: rect.maxY))
        path.line(to: NSPoint(x: rect.maxX, y: rect.maxY - cornerLen))

        path.move(to: NSPoint(x: rect.minX, y: rect.minY + cornerLen))
        path.line(to: NSPoint(x: rect.minX, y: rect.minY))
        path.line(to: NSPoint(x: rect.minX + cornerLen, y: rect.minY))

        path.move(to: NSPoint(x: rect.maxX - cornerLen, y: rect.minY))
        path.line(to: NSPoint(x: rect.maxX, y: rect.minY))
        path.line(to: NSPoint(x: rect.maxX, y: rect.minY + cornerLen))

        NSColor.black.withAlphaComponent(0.92).setStroke()
        path.lineWidth = 1.4
        path.lineCapStyle = .square
        path.stroke()
    }
}
