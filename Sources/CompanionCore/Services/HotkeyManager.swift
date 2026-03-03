// Sources/CompanionCore/Services/HotkeyManager.swift
import Foundation
import Carbon

/// Registers a global hotkey (⌘⇧Space) to toggle the Friday overlay.
/// Uses Carbon RegisterEventHotKey — no accessibility permissions needed.
@MainActor
public final class HotkeyManager {
    public var onHotkey: (() -> Void)?

    private var hotkeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    // Store the singleton reference for the C callback
    private static var shared: HotkeyManager?

    public init() {}

    /// Register ⌘⇧Space as the global hotkey.
    public func register() {
        HotkeyManager.shared = self

        // ⌘⇧Space: modifiers = cmdKey + shiftKey, keyCode = 49 (space)
        var hotkeyID = EventHotKeyID()
        hotkeyID.signature = OSType(0x46524459) // "FRDY"
        hotkeyID.id = 1

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        // Install event handler
        let handler: EventHandlerUPP = { _, event, _ -> OSStatus in
            MainActor.assumeIsolated {
                HotkeyManager.shared?.onHotkey?()
            }
            return noErr
        }

        InstallEventHandler(
            GetApplicationEventTarget(),
            handler,
            1,
            &eventType,
            nil,
            &eventHandlerRef
        )

        // Register the hotkey: ⌘⇧Space
        let modifiers = UInt32(cmdKey | shiftKey)
        RegisterEventHotKey(
            UInt32(kVK_Space),
            modifiers,
            hotkeyID,
            GetApplicationEventTarget(),
            0,
            &hotkeyRef
        )
    }

    /// Unregister the hotkey.
    public func unregister() {
        if let ref = hotkeyRef {
            UnregisterEventHotKey(ref)
            hotkeyRef = nil
        }
        if let handler = eventHandlerRef {
            RemoveEventHandler(handler)
            eventHandlerRef = nil
        }
        HotkeyManager.shared = nil
    }

    deinit {
        // Note: deinit can't be @MainActor, but cleanup should happen via unregister()
    }
}
