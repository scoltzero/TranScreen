import Foundation
import Carbon
import CoreGraphics

enum HotkeyAction: String, Codable, CaseIterable, Identifiable {
    case triggerRegionSelect = "triggerRegionSelect"
    case toggleFullScreenMask = "toggleFullScreenMask"
    case fullScreenRegionSelect = "fullScreenRegionSelect"
    case exitToIdle = "exitToIdle"
    case increaseOpacity = "increaseOpacity"
    case decreaseOpacity = "decreaseOpacity"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .triggerRegionSelect: return "选区截图翻译"
        case .toggleFullScreenMask: return "实时翻译"
        case .fullScreenRegionSelect: return "实时模式选区"
        case .exitToIdle: return "退出/取消"
        case .increaseOpacity: return "增加工具条不透明度"
        case .decreaseOpacity: return "降低工具条不透明度"
        }
    }

    var defaultKeyCode: Int {
        switch self {
        case .triggerRegionSelect: return kVK_ANSI_E
        case .toggleFullScreenMask: return kVK_ANSI_M
        case .fullScreenRegionSelect: return kVK_ANSI_E
        case .exitToIdle: return kVK_Escape
        case .increaseOpacity: return kVK_ANSI_Equal
        case .decreaseOpacity: return kVK_ANSI_Minus
        }
    }

    var defaultModifiers: CGEventFlags {
        switch self {
        case .triggerRegionSelect: return .maskCommand
        case .toggleFullScreenMask: return .maskCommand
        case .fullScreenRegionSelect: return [.maskCommand, .maskShift]
        case .exitToIdle: return []
        case .increaseOpacity: return .maskCommand
        case .decreaseOpacity: return .maskCommand
        }
    }

    var defaultBinding: HotkeySpec {
        HotkeySpec(keyCode: defaultKeyCode, modifiers: defaultModifiers)
    }
}

struct HotkeySpec: Codable, Equatable, Hashable {
    var keyCode: Int
    var modifiers: CGEventFlags

    private static let modifierChordKeyCode = -1_001
    private static let doubleTapControlKeyCode = -1_101
    private static let doubleTapOptionKeyCode = -1_102
    private static let doubleTapShiftKeyCode = -1_103
    private static let doubleTapCommandKeyCode = -1_104

    var isValid: Bool {
        if keyCode >= 0 { return true }
        if isModifierChord { return modifiers.normalizedHotkeyModifiers.count >= 2 }
        if doubleTappedModifier != nil { return true }
        return false
    }

    var isModifierChord: Bool { keyCode == Self.modifierChordKeyCode }

    var doubleTappedModifier: CGEventFlags? {
        switch keyCode {
        case Self.doubleTapControlKeyCode: return .maskControl
        case Self.doubleTapOptionKeyCode: return .maskAlternate
        case Self.doubleTapShiftKeyCode: return .maskShift
        case Self.doubleTapCommandKeyCode: return .maskCommand
        default: return nil
        }
    }

    static func modifierChord(_ modifiers: CGEventFlags) -> HotkeySpec {
        HotkeySpec(keyCode: modifierChordKeyCode, modifiers: modifiers.normalizedHotkeyModifiers)
    }

    static func modifierDoubleTap(tappedModifier: CGEventFlags, heldModifiers: CGEventFlags) -> HotkeySpec? {
        guard let keyCode = doubleTapKeyCode(for: tappedModifier) else { return nil }
        return HotkeySpec(
            keyCode: keyCode,
            modifiers: heldModifiers.normalizedHotkeyModifiers.subtracting(tappedModifier)
        )
    }

    static func modifierFlag(forKeyCode keyCode: Int) -> CGEventFlags? {
        switch keyCode {
        case kVK_Control, kVK_RightControl: return .maskControl
        case kVK_Option, kVK_RightOption: return .maskAlternate
        case kVK_Shift, kVK_RightShift: return .maskShift
        case kVK_Command, kVK_RightCommand: return .maskCommand
        default: return nil
        }
    }

    private static func doubleTapKeyCode(for modifier: CGEventFlags) -> Int? {
        switch modifier {
        case .maskControl: return doubleTapControlKeyCode
        case .maskAlternate: return doubleTapOptionKeyCode
        case .maskShift: return doubleTapShiftKeyCode
        case .maskCommand: return doubleTapCommandKeyCode
        default: return nil
        }
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(keyCode)
        hasher.combine(modifiers.normalizedHotkeyModifiers.rawValue)
    }

    static func == (lhs: HotkeySpec, rhs: HotkeySpec) -> Bool {
        lhs.keyCode == rhs.keyCode &&
            lhs.modifiers.normalizedHotkeyModifiers == rhs.modifiers.normalizedHotkeyModifiers
    }

    var displayString: String {
        if isModifierChord {
            return modifierSymbols(modifiers.normalizedHotkeyModifiers).joined()
        }

        if let tapped = doubleTappedModifier {
            var parts = modifierSymbols(modifiers.normalizedHotkeyModifiers.subtracting(tapped))
            let symbol = modifierSymbols(tapped).first ?? ""
            parts.append(symbol)
            parts.append(symbol)
            return parts.joined()
        }

        var parts: [String] = []
        parts.append(contentsOf: modifierSymbols(modifiers.normalizedHotkeyModifiers))
        parts.append(keyCodeToString(keyCode))
        return parts.joined()
    }

    private func modifierSymbols(_ flags: CGEventFlags) -> [String] {
        var parts: [String] = []
        if flags.contains(.maskControl) { parts.append("⌃") }
        if flags.contains(.maskAlternate) { parts.append("⌥") }
        if flags.contains(.maskShift) { parts.append("⇧") }
        if flags.contains(.maskCommand) { parts.append("⌘") }
        return parts
    }

    private func keyCodeToString(_ code: Int) -> String {
        switch code {
        case kVK_Escape: return "Esc"
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Space: return "Space"
        case kVK_Delete: return "⌫"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_ANSI_Equal: return "="
        case kVK_ANSI_Minus: return "-"
        case kVK_ANSI_Comma: return ","
        case kVK_ANSI_Period: return "."
        case kVK_ANSI_Slash: return "/"
        case kVK_ANSI_Semicolon: return ";"
        case kVK_ANSI_Quote: return "'"
        case kVK_ANSI_LeftBracket: return "["
        case kVK_ANSI_RightBracket: return "]"
        case kVK_ANSI_Backslash: return "\\"
        case kVK_ANSI_Grave: return "`"
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_Z: return "Z"
        default: return "(\(code))"
        }
    }

}

extension CGEventFlags: @retroactive Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(UInt64.self)
        self.init(rawValue: raw)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

extension CGEventFlags {
    var normalizedHotkeyModifiers: CGEventFlags {
        intersection([.maskCommand, .maskShift, .maskAlternate, .maskControl])
    }

    var count: Int {
        var result = 0
        if contains(.maskCommand) { result += 1 }
        if contains(.maskShift) { result += 1 }
        if contains(.maskAlternate) { result += 1 }
        if contains(.maskControl) { result += 1 }
        return result
    }

    var individualModifiers: [CGEventFlags] {
        var result: [CGEventFlags] = []
        if contains(.maskControl) { result.append(.maskControl) }
        if contains(.maskAlternate) { result.append(.maskAlternate) }
        if contains(.maskShift) { result.append(.maskShift) }
        if contains(.maskCommand) { result.append(.maskCommand) }
        return result
    }

    func subtracting(_ flag: CGEventFlags) -> CGEventFlags {
        CGEventFlags(rawValue: rawValue & ~flag.rawValue)
    }
}
