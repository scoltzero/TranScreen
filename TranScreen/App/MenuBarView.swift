import SwiftUI
import SwiftData
import AppKit
import Carbon

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.openSettings) private var openSettings
    @Query private var bindings: [HotkeyBinding]

    var body: some View {
        Text(statusText)
            .foregroundStyle(.secondary)

        Divider()

        Button("选区翻译") { appState.enterRegionSelect() }
            .keyboardShortcut(for: .triggerRegionSelect, bindings: bindings)
        Button(appState.mode == .fullScreenMask ? "退出全屏蒙版" : "全屏蒙版翻译") {
            appState.toggleFullScreenMask()
        }
        .keyboardShortcut(for: .toggleFullScreenMask, bindings: bindings)

        if !appState.hasScreenRecordingPermission || !appState.hasAccessibilityPermission {
            Divider()
            Button("授予必要权限") { appState.requestPermissions() }
        }

        if let error = appState.lastError {
            Divider()
            Text("⚠️ \(error)")
                .foregroundStyle(.red)
        }

        Divider()

        Button("偏好设置...") { showSettingsWindow() }
            .keyboardShortcut(",", modifiers: .command)
        Button("退出 TranScreen") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q", modifiers: .command)
    }

    private var statusText: String {
        switch appState.mode {
        case .idle: return "● 空闲"
        case .regionSelecting: return "● 选择区域中"
        case .regionTranslating: return appState.isProcessing ? "● 翻译中..." : "● 显示译文"
        case .fullScreenMask: return "● 全屏蒙版"
        case .fullScreenRegionSelecting: return "● 全屏选区中"
        }
    }

    private func showSettingsWindow() {
        openSettings()
        NSApp.activate(ignoringOtherApps: true)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            Task { @MainActor in bringVisibleSettingsWindowToFront() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            Task { @MainActor in bringVisibleSettingsWindowToFront() }
        }
    }
}

@MainActor
private func bringVisibleSettingsWindowToFront() {
    NSApp.activate(ignoringOtherApps: true)
    guard let window = NSApp.windows.first(where: {
        !($0 is OverlayPanel) && $0.isVisible && $0.canBecomeMain
    }) else { return }
    window.makeKeyAndOrderFront(nil)
    window.orderFrontRegardless()
}

private extension View {
    @ViewBuilder
    func keyboardShortcut(for action: HotkeyAction, bindings: [HotkeyBinding]) -> some View {
        let spec = bindings.first { $0.actionRaw == action.rawValue }?.spec ?? action.defaultBinding
        if let shortcut = spec.keyboardShortcut {
            keyboardShortcut(shortcut.key, modifiers: shortcut.modifiers)
        } else {
            self
        }
    }
}

private extension HotkeySpec {
    var keyboardShortcut: (key: KeyEquivalent, modifiers: SwiftUI.EventModifiers)? {
        guard isValid, let key = keyEquivalent else { return nil }
        return (key, eventModifiers)
    }

    private var eventModifiers: SwiftUI.EventModifiers {
        var result = SwiftUI.EventModifiers()
        if modifiers.contains(.maskCommand) { result.insert(SwiftUI.EventModifiers.command) }
        if modifiers.contains(.maskShift) { result.insert(SwiftUI.EventModifiers.shift) }
        if modifiers.contains(.maskAlternate) { result.insert(SwiftUI.EventModifiers.option) }
        if modifiers.contains(.maskControl) { result.insert(SwiftUI.EventModifiers.control) }
        return result
    }

    private var keyEquivalent: KeyEquivalent? {
        switch keyCode {
        case kVK_Escape: return .escape
        case kVK_Return: return .return
        case kVK_Tab: return .tab
        case kVK_Space: return .space
        case kVK_Delete: return .delete
        case kVK_UpArrow: return .upArrow
        case kVK_DownArrow: return .downArrow
        case kVK_LeftArrow: return .leftArrow
        case kVK_RightArrow: return .rightArrow
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
        case kVK_ANSI_A: return "a"
        case kVK_ANSI_B: return "b"
        case kVK_ANSI_C: return "c"
        case kVK_ANSI_D: return "d"
        case kVK_ANSI_E: return "e"
        case kVK_ANSI_F: return "f"
        case kVK_ANSI_G: return "g"
        case kVK_ANSI_H: return "h"
        case kVK_ANSI_I: return "i"
        case kVK_ANSI_J: return "j"
        case kVK_ANSI_K: return "k"
        case kVK_ANSI_L: return "l"
        case kVK_ANSI_M: return "m"
        case kVK_ANSI_N: return "n"
        case kVK_ANSI_O: return "o"
        case kVK_ANSI_P: return "p"
        case kVK_ANSI_Q: return "q"
        case kVK_ANSI_R: return "r"
        case kVK_ANSI_S: return "s"
        case kVK_ANSI_T: return "t"
        case kVK_ANSI_U: return "u"
        case kVK_ANSI_V: return "v"
        case kVK_ANSI_W: return "w"
        case kVK_ANSI_X: return "x"
        case kVK_ANSI_Y: return "y"
        case kVK_ANSI_Z: return "z"
        default: return nil
        }
    }
}
