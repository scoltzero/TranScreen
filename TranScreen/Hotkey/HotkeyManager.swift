import AppKit
import Carbon

@MainActor
final class HotkeyManager {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var bindings: [HotkeySpec: HotkeyAction] = [:]
    private var currentModifierFlags = CGEventFlags()
    private var pendingModifierChordTask: Task<Void, Never>?
    private var lastModifierDown: (modifier: CGEventFlags, held: CGEventFlags, time: TimeInterval)?
    private var firedModifierChordSpec: HotkeySpec?

    private let modifierChordDelay: TimeInterval = 0.28
    private let modifierDoubleTapInterval: TimeInterval = 0.45

    weak var appState: AppState?

    init(appState: AppState) {
        self.appState = appState
    }

    func loadBindings(_ hotkeyBindings: [HotkeyBinding]) {
        var newMap: [HotkeySpec: HotkeyAction] = [:]
        for binding in hotkeyBindings where binding.isEnabled {
            if let action = binding.action {
                let spec = binding.spec.isValid ? binding.spec : action.defaultBinding
                newMap[spec] = action
            }
        }

        if newMap.isEmpty {
            for action in HotkeyAction.allCases {
                newMap[action.defaultBinding] = action
            }
        }

        self.bindings = newMap
        unregister()
        register()
    }

    func register() {
        guard AXIsProcessTrusted() else {
            print("⚠️ 缺少辅助功能权限，无法注册全局快捷键")
            return
        }

        let eventTypes: [CGEventType] = [
            .keyDown,
            .flagsChanged,
            .scrollWheel,
            .leftMouseDown,
            .leftMouseUp,
            .rightMouseDown,
            .rightMouseUp,
            .otherMouseDown,
            .otherMouseUp
        ]
        let mask = eventTypes.reduce(CGEventMask(0)) { partial, eventType in
            partial | (CGEventMask(1) << eventType.rawValue)
        }
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { proxy, type, event, userInfo -> Unmanaged<CGEvent>? in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userInfo).takeUnretainedValue()
                return manager.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: selfPtr
        )

        guard let tap = eventTap else {
            print("⚠️ CGEvent.tapCreate 失败")
            return
        }

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        print("✅ 全局快捷键注册成功，已绑定 \(bindings.count) 个动作")
    }

    func unregister() {
        cancelPendingModifierChord()
        currentModifierFlags = []
        lastModifierDown = nil
        firedModifierChordSpec = nil
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            }
        }
        eventTap = nil
        runLoopSource = nil
    }

    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .flagsChanged {
            handleModifierEvent(event)
            return Unmanaged.passUnretained(event)
        }

        if type == .scrollWheel ||
            type == .leftMouseDown || type == .leftMouseUp ||
            type == .rightMouseDown || type == .rightMouseUp ||
            type == .otherMouseDown || type == .otherMouseUp {
            let location = event.location
            DispatchQueue.main.async { [weak self] in
                guard let appState = self?.appState else { return }
                if !appState.realtimeToolbarContainsEventLocation(location) {
                    appState.noteRealtimeUserActivity()
                }
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown else { return Unmanaged.passUnretained(event) }
        cancelPendingModifierChord()

        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags.normalizedHotkeyModifiers
        let spec = HotkeySpec(keyCode: keyCode, modifiers: flags)

        guard let action = bindings[spec] else {
            DispatchQueue.main.async { [weak self] in
                self?.appState?.noteRealtimeUserActivity()
            }
            return Unmanaged.passUnretained(event)
        }

        DispatchQueue.main.async { [weak self] in
            self?.executeAction(action)
        }

        return nil
    }

    private func handleModifierEvent(_ event: CGEvent) {
        let flags = event.flags.normalizedHotkeyModifiers
        currentModifierFlags = flags
        if let firedModifierChordSpec, firedModifierChordSpec.modifiers != flags {
            self.firedModifierChordSpec = nil
        }

        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        guard let changedModifier = HotkeySpec.modifierFlag(forKeyCode: keyCode) else {
            if flags.count < 2 { cancelPendingModifierChord() }
            return
        }

        if flags.contains(changedModifier) {
            let held = flags.subtracting(changedModifier)
            let now = ProcessInfo.processInfo.systemUptime

            if let lastModifierDown,
               lastModifierDown.modifier == changedModifier,
               lastModifierDown.held == held,
               now - lastModifierDown.time <= modifierDoubleTapInterval,
               let doubleTapSpec = HotkeySpec.modifierDoubleTap(tappedModifier: changedModifier, heldModifiers: held),
               let action = bindings[doubleTapSpec] {
                cancelPendingModifierChord()
                self.lastModifierDown = nil
                DispatchQueue.main.async { [weak self] in
                    self?.executeAction(action)
                }
                return
            }

            lastModifierDown = (changedModifier, held, now)
        }

        scheduleModifierChordAction(for: flags)
    }

    private func scheduleModifierChordAction(for flags: CGEventFlags) {
        cancelPendingModifierChord()

        let normalized = flags.normalizedHotkeyModifiers
        guard normalized.count >= 2 else { return }

        let spec = HotkeySpec.modifierChord(normalized)
        guard let action = bindings[spec] else { return }
        guard firedModifierChordSpec != spec else { return }

        if !hasPotentialDoubleTapBinding(for: normalized) {
            firedModifierChordSpec = spec
            DispatchQueue.main.async { [weak self] in
                self?.executeAction(action)
            }
            return
        }

        let delay = modifierChordDelay
        pendingModifierChordTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self, self.currentModifierFlags == normalized else { return }
            self.firedModifierChordSpec = spec
            self.executeAction(action)
            self.pendingModifierChordTask = nil
        }
    }

    private func hasPotentialDoubleTapBinding(for flags: CGEventFlags) -> Bool {
        let normalized = flags.normalizedHotkeyModifiers
        for modifier in normalized.individualModifiers {
            let held = normalized.subtracting(modifier)
            if let spec = HotkeySpec.modifierDoubleTap(tappedModifier: modifier, heldModifiers: held),
               bindings[spec] != nil {
                return true
            }
        }
        return false
    }

    private func cancelPendingModifierChord() {
        pendingModifierChordTask?.cancel()
        pendingModifierChordTask = nil
    }

    @MainActor
    private func executeAction(_ action: HotkeyAction) {
        guard let appState else { return }
        switch action {
        case .triggerRegionSelect:
            appState.enterRegionSelect()
        case .toggleFullScreenMask:
            appState.enterRealtimeSelect()
        case .fullScreenRegionSelect:
            appState.enterRealtimeSelect()
        case .exitToIdle:
            appState.exitToIdle()
        case .increaseOpacity:
            appState.adjustOpacity(by: 0.1)
        case .decreaseOpacity:
            appState.adjustOpacity(by: -0.1)
        }
    }
}
