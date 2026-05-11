import SwiftUI
import AppKit
import Carbon

struct HotkeyRecorder: NSViewRepresentable {
    @Binding var spec: HotkeySpec
    @Binding var isRecording: Bool
    var onCancelled: () -> Void = {}

    func makeNSView(context: Context) -> HotkeyRecorderView {
        let view = HotkeyRecorderView()
        view.onSpecRecorded = { newSpec in
            spec = newSpec
            isRecording = false
        }
        view.onCancelled = {
            isRecording = false
            onCancelled()
        }
        return view
    }

    func updateNSView(_ nsView: HotkeyRecorderView, context: Context) {
        nsView.isRecording = isRecording
        nsView.currentSpec = spec
        nsView.needsDisplay = true
    }
}

final class HotkeyRecorderView: NSView {
    private var localKeyMonitor: Any?
    private var hasRecordedCurrentSession = false
    private var pendingModifierChordWorkItem: DispatchWorkItem?
    private var lastModifierDown: (modifier: CGEventFlags, held: CGEventFlags, time: TimeInterval)?

    private let modifierChordDelay: TimeInterval = 0.28
    private let modifierDoubleTapInterval: TimeInterval = 0.45

    var isRecording = false {
        didSet {
            needsDisplay = true
            guard oldValue != isRecording else { return }
            if isRecording {
                resetRecordingState()
                installLocalKeyMonitor()
                DispatchQueue.main.async { [weak self] in
                    self?.window?.makeFirstResponder(self)
                }
            } else {
                cancelPendingModifierChord()
                removeLocalKeyMonitor()
            }
        }
    }
    var currentSpec = HotkeySpec(keyCode: -1, modifiers: [])
    var onSpecRecorded: ((HotkeySpec) -> Void)?
    var onCancelled: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    deinit {
        removeLocalKeyMonitor()
    }

    override func draw(_ dirtyRect: NSRect) {
        let text = isRecording ? "按下快捷键..." : currentSpec.displayString
        let attr: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: isRecording ? NSColor.systemBlue : NSColor.labelColor
        ]

        let bg = isRecording ? NSColor.systemBlue.withAlphaComponent(0.1) : NSColor.controlBackgroundColor
        bg.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()

        let border = isRecording ? NSColor.systemBlue : NSColor.separatorColor
        border.setStroke()
        let borderPath = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
        borderPath.lineWidth = 1
        borderPath.stroke()

        let textSize = (text as NSString).size(withAttributes: attr)
        let textRect = CGRect(
            x: (bounds.width - textSize.width) / 2,
            y: (bounds.height - textSize.height) / 2,
            width: textSize.width,
            height: textSize.height
        )
        (text as NSString).draw(in: textRect, withAttributes: attr)
    }

    override func keyDown(with event: NSEvent) {
        recordKeyEvent(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording, event.type == .keyDown else { return false }
        recordKeyEvent(event)
        return true
    }

    private func recordKeyEvent(_ event: NSEvent) {
        guard isRecording, !hasRecordedCurrentSession else { return }
        cancelPendingModifierChord()

        let keyCode = Int(event.keyCode)
        let modifierKeyCodes = [kVK_Command, kVK_Shift, kVK_Option, kVK_Control,
                                kVK_RightCommand, kVK_RightShift, kVK_RightOption, kVK_RightControl]
        if modifierKeyCodes.contains(keyCode) { return }

        // Esc 无修饰键 = 取消录制
        if keyCode == kVK_Escape && !event.modifierFlags.contains(.command) &&
            !event.modifierFlags.contains(.shift) && !event.modifierFlags.contains(.option) &&
            !event.modifierFlags.contains(.control) {
            onCancelled?()
            return
        }

        let flags = event.modifierFlags.cgEventFlags.intersection(
            [.maskCommand, .maskShift, .maskAlternate, .maskControl]
        )
        finishRecording(HotkeySpec(keyCode: keyCode, modifiers: flags))
    }

    private func recordFlagsChanged(_ event: NSEvent) {
        guard isRecording, !hasRecordedCurrentSession else { return }
        let currentFlags = event.modifierFlags.cgEventFlags.normalizedHotkeyModifiers
        let keyCode = Int(event.keyCode)
        guard let changedModifier = HotkeySpec.modifierFlag(forKeyCode: keyCode) else {
            return
        }

        if currentFlags.contains(changedModifier) {
            let held = currentFlags.subtracting(changedModifier)
            let now = ProcessInfo.processInfo.systemUptime

            if let lastModifierDown,
               lastModifierDown.modifier == changedModifier,
               lastModifierDown.held == held,
               now - lastModifierDown.time <= modifierDoubleTapInterval,
               let spec = HotkeySpec.modifierDoubleTap(tappedModifier: changedModifier, heldModifiers: held) {
                finishRecording(spec)
                return
            }

            lastModifierDown = (changedModifier, held, now)
        }

        scheduleModifierChordRecording(for: currentFlags)
    }

    private func scheduleModifierChordRecording(for flags: CGEventFlags) {
        cancelPendingModifierChord()

        let normalized = flags.normalizedHotkeyModifiers
        guard normalized.count >= 2 else { return }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.isRecording, !self.hasRecordedCurrentSession else { return }
            self.finishRecording(HotkeySpec.modifierChord(normalized))
        }
        pendingModifierChordWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + modifierChordDelay, execute: workItem)
    }

    private func finishRecording(_ spec: HotkeySpec) {
        guard isRecording, !hasRecordedCurrentSession else { return }
        hasRecordedCurrentSession = true
        cancelPendingModifierChord()
        onSpecRecorded?(spec)
    }

    private func resetRecordingState() {
        hasRecordedCurrentSession = false
        lastModifierDown = nil
        cancelPendingModifierChord()
    }

    private func cancelPendingModifierChord() {
        pendingModifierChordWorkItem?.cancel()
        pendingModifierChordWorkItem = nil
    }

    private func installLocalKeyMonitor() {
        removeLocalKeyMonitor()
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self, self.isRecording else { return event }
            switch event.type {
            case .keyDown:
                self.recordKeyEvent(event)
                return nil
            case .flagsChanged:
                self.recordFlagsChanged(event)
                return event
            default:
                return event
            }
        }
    }

    private func removeLocalKeyMonitor() {
        cancelPendingModifierChord()
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
            self.localKeyMonitor = nil
        }
    }
}

extension NSEvent.ModifierFlags {
    var cgEventFlags: CGEventFlags {
        var flags = CGEventFlags()
        if contains(.command) { flags.insert(.maskCommand) }
        if contains(.shift) { flags.insert(.maskShift) }
        if contains(.option) { flags.insert(.maskAlternate) }
        if contains(.control) { flags.insert(.maskControl) }
        return flags
    }
}
