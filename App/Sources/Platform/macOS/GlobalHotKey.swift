#if os(macOS)
import AppKit
import Carbon.HIToolbox

/// The key combination that brings Theo forward with the cursor in the bar at the bottom, from
/// any app (Settings → Quick Add from any app). Stored per Mac. Never ⌃⌥Space: that's the
/// system's "next input source" shortcut, used by anyone typing in two languages.
enum HotKeyChoice: String, CaseIterable, Identifiable {
    case ctrlOptCmdN, ctrlOptCmdT, optShiftSpace, off

    /// UserDefaults key (this Mac only).
    static let preferenceKey = "hotkey.quickEntry"
    static let standard: HotKeyChoice = .ctrlOptCmdN

    /// The stored choice, or the standard one.
    static var stored: HotKeyChoice {
        UserDefaults.standard.string(forKey: preferenceKey).flatMap(HotKeyChoice.init(rawValue:)) ?? standard
    }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ctrlOptCmdN: "⌃⌥⌘N"
        case .ctrlOptCmdT: "⌃⌥⌘T"
        case .optShiftSpace: "⌥⇧Space"
        case .off: "Off"
        }
    }

    /// Carbon virtual key code; nil = off.
    var keyCode: UInt32? {
        switch self {
        case .ctrlOptCmdN: return UInt32(kVK_ANSI_N)
        case .ctrlOptCmdT: return UInt32(kVK_ANSI_T)
        case .optShiftSpace: return UInt32(kVK_Space)
        case .off: return nil
        }
    }

    /// Carbon modifier mask.
    var modifiers: UInt32 {
        switch self {
        case .ctrlOptCmdN, .ctrlOptCmdT: return UInt32(controlKey | optionKey | cmdKey)
        case .optShiftSpace: return UInt32(optionKey | shiftKey)
        case .off: return 0
        }
    }
}

/// A system-wide shortcut through Carbon's `RegisterEventHotKey`: it works inside the sandbox
/// and needs no Accessibility permission. Pressing it activates Theo, opens the main window if
/// it's closed, and puts the cursor in the composer (the same as ⌘N inside Theo).
@MainActor
final class GlobalHotKey {
    static let shared = GlobalHotKey()

    /// "THEO", so the system can tell our hot key apart.
    private static let signature: OSType = 0x5448454F

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private(set) var current: HotKeyChoice = .off

    private init() {}

    /// Registers `choice` (replacing the previous one); `.off` just removes it.
    func apply(_ choice: HotKeyChoice) {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        current = .off
        guard let keyCode = choice.keyCode else { return }
        installHandlerIfNeeded()
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode,
            choice.modifiers,
            EventHotKeyID(signature: Self.signature, id: 1),
            GetApplicationEventTarget(),
            0,
            &ref
        )
        guard status == 0, let ref else {
            // Usually another app (or a second copy of Theo) already owns the combination.
            print("Theo: couldn't register the Quick Add shortcut \(choice.title) (\(status))")
            return
        }
        hotKeyRef = ref
        current = choice
    }

    /// The application-wide handler (`theoHotKeyPressed`), installed once.
    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var pressed = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        var ref: EventHandlerRef?
        let status = InstallEventHandler(GetApplicationEventTarget(), theoHotKeyPressed, 1, &pressed, nil, &ref)
        if status == 0 {
            handlerRef = ref
        } else {
            print("Theo: couldn't install the hot key handler (\(status))")
        }
    }

    /// Theo to the front with the cursor in the composer. Also the Dock menu's "New Task".
    static func fire() {
        let wasVisible = MainWindow.isVisible
        // Activates Theo, and opens the main window when none is showing.
        MainWindow.reopen()
        Task { @MainActor in
            // Let the window become key (or appear) first, so the field can take the focus.
            try? await Task.sleep(for: .milliseconds(wasVisible ? 50 : 500))
            AppModel.shared?.commandTarget.requestQuickEntry()
        }
    }
}

/// Carbon's callback for our hot key. A C function pointer can't capture anything, so it hops
/// to the main actor and calls `GlobalHotKey.fire()`.
private func theoHotKeyPressed(_ call: EventHandlerCallRef?, _ event: EventRef?, _ userData: UnsafeMutableRawPointer?) -> OSStatus {
    Task { @MainActor in GlobalHotKey.fire() }
    return 0
}
#endif
