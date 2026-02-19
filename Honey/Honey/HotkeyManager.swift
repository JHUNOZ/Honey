import Foundation
import Carbon
import AppKit

// ══════════════════════════════════════════════════════════════
//  HOTKEY MANAGER
//  Mirrors: RegisterHotKey / WndProc hotkey handling
//
//  F1  = Activate   (kVK_F1)
//  F2  = Deactivate (kVK_F2)
//  F3  = Set Point  (kVK_F3)   — on Mac keyboards, may need Fn+F3
//  F4  = Toggle Salto (kVK_F4)
//  =   = Toggle Click (kVK_ANSI_Equal)
// ══════════════════════════════════════════════════════════════

final class HotkeyManager {

    enum HotkeyAction {
        case activate
        case deactivate
        case setPoint
        case toggleSalto
        case toggleClick
    }

    var onHotkey: ((HotkeyAction) -> Void)?

    // Carbon EventHotKey references (mirrors hWnd + id pairs)
    private var hk_activate:   EventHotKeyRef?
    private var hk_deactivate: EventHotKeyRef?
    private var hk_setPoint:   EventHotKeyRef?
    private var hk_salto:      EventHotKeyRef?
    private var hk_equals:     EventHotKeyRef?

    private var handlerRef: EventHandlerRef?

    // IDs mirroring C# HK_* constants
    private let HK_ACT:    UInt32 = 1
    private let HK_DESACT: UInt32 = 2
    private let HK_SETPT:  UInt32 = 3
    private let HK_SALTOS: UInt32 = 4
    private let HK_EQUALS: UInt32 = 5

    init() {}

    func register() {
        // Install Carbon event handler (mirrors WndProc WM_HOTKEY)
        var eventSpec = EventTypeSpec(eventClass: UInt32(kEventClassKeyboard),
                                      eventKind:  UInt32(kEventHotKeyPressed))

        // We use a C-compatible callback via a global bridge
        let selfPtr = Unmanaged.passRetained(self).toOpaque()

        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, userData) -> OSStatus in
                guard let userData = userData else { return OSStatus(eventNotHandledErr) }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                return manager.handleCarbonEvent(event)
            },
            1,
            &eventSpec,
            selfPtr,
            &handlerRef
        )

        // Register hotkeys — mirrors RegisterHotKey calls
        // F1 → activate
        var hkID = EventHotKeyID(signature: fourCharCode("HONY"), id: HK_ACT)
        RegisterEventHotKey(UInt32(kVK_F1), 0, hkID, GetApplicationEventTarget(), 0, &hk_activate)

        // F2 → deactivate
        hkID = EventHotKeyID(signature: fourCharCode("HONY"), id: HK_DESACT)
        RegisterEventHotKey(UInt32(kVK_F2), 0, hkID, GetApplicationEventTarget(), 0, &hk_deactivate)

        // F3 → set point
        hkID = EventHotKeyID(signature: fourCharCode("HONY"), id: HK_SETPT)
        RegisterEventHotKey(UInt32(kVK_F3), 0, hkID, GetApplicationEventTarget(), 0, &hk_setPoint)

        // F4 → toggle salto
        hkID = EventHotKeyID(signature: fourCharCode("HONY"), id: HK_SALTOS)
        RegisterEventHotKey(UInt32(kVK_F4), 0, hkID, GetApplicationEventTarget(), 0, &hk_salto)

        // = → toggle click (kVK_ANSI_Equal = 0x18)
        hkID = EventHotKeyID(signature: fourCharCode("HONY"), id: HK_EQUALS)
        RegisterEventHotKey(0x18, 0, hkID, GetApplicationEventTarget(), 0, &hk_equals)
    }

    func unregister() {
        if let ref = hk_activate   { UnregisterEventHotKey(ref) }
        if let ref = hk_deactivate { UnregisterEventHotKey(ref) }
        if let ref = hk_setPoint   { UnregisterEventHotKey(ref) }
        if let ref = hk_salto      { UnregisterEventHotKey(ref) }
        if let ref = hk_equals     { UnregisterEventHotKey(ref) }
        if let ref = handlerRef    { RemoveEventHandler(ref) }
    }

    // Mirrors WndProc switch on m.WParam
    private func handleCarbonEvent(_ event: EventRef?) -> OSStatus {
        guard let event = event else { return OSStatus(eventNotHandledErr) }
        var hkID = EventHotKeyID()
        GetEventParameter(event,
                          EventParamName(kEventParamDirectObject),
                          EventParamType(typeEventHotKeyID),
                          nil,
                          MemoryLayout<EventHotKeyID>.size,
                          nil,
                          &hkID)

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            switch hkID.id {
            case self.HK_ACT:    self.onHotkey?(.activate)
            case self.HK_DESACT: self.onHotkey?(.deactivate)
            case self.HK_SETPT:  self.onHotkey?(.setPoint)
            case self.HK_SALTOS: self.onHotkey?(.toggleSalto)
            case self.HK_EQUALS: self.onHotkey?(.toggleClick)
            default: break
            }
        }
        return noErr
    }

    // Helper: 4-char OSType from string literal
    private func fourCharCode(_ s: String) -> FourCharCode {
        var code: FourCharCode = 0
        for c in s.unicodeScalars {
            code = (code << 8) + FourCharCode(c.value)
        }
        return code
    }
}
