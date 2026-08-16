import Foundation
import Carbon
import AppKit

public final class HotKeyManager {
    public static let shared = HotKeyManager()
    
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    public var onHotKeyPressed: (() -> Void)?
    
    private init() {}
    
    /// 注册快捷键 (从 SettingsManager 读取配置)
    public func registerDefaultHotKey() {
        let settings = SettingsManager.shared
        registerHotKey(keyCode: settings.hotKeyCode, modifiers: settings.hotKeyModifiers)
    }
    
    /// 注册指定的全局快捷键
    public func registerHotKey(keyCode: UInt32, modifiers: UInt32) {
        unregisterHotKey()
        
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        
        let handlerUPP: EventHandlerUPP = { _, inEvent, _ -> OSStatus in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                inEvent,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            
            if status == noErr && hotKeyID.id == 1 {
                DispatchQueue.main.async {
                    HotKeyManager.shared.onHotKeyPressed?()
                }
                return noErr
            }
            return OSStatus(eventNotHandledErr)
        }
        
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            handlerUPP,
            1,
            &eventType,
            nil,
            &eventHandler
        )
        
        guard installStatus == noErr else {
            print("MacSnip: Failed to install Carbon event handler: \(installStatus)")
            return
        }
        
        let signature = OSType(
            (UInt32(UInt8(ascii: "M")) << 24) |
            (UInt32(UInt8(ascii: "S")) << 16) |
            (UInt32(UInt8(ascii: "N")) << 8)  |
            UInt32(UInt8(ascii: "P"))
        )
        let hotKeyID = EventHotKeyID(signature: signature, id: 1)
        
        let registerStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        
        if registerStatus != noErr {
            print("MacSnip: Failed to register hotkey: \(registerStatus)")
        } else {
            print("MacSnip: Global hotkey registered successfully (code: \(keyCode), mods: \(modifiers)).")
        }
    }
    
    public func unregisterHotKey() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        if let handler = eventHandler {
            RemoveEventHandler(handler)
            eventHandler = nil
        }
    }
    
    /// 将 keyCode 和 NSEvent.ModifierFlags 转换为 Carbon 修饰符与可读字符串
    public static func formatHotKey(keyCode: UInt16, flags: NSEvent.ModifierFlags) -> (display: String, carbonModifiers: UInt32, keyCode: UInt32)? {
        var parts: [String] = []
        var carbonMods: UInt32 = 0
        
        if flags.contains(.control) {
            parts.append("⌃")
            carbonMods |= UInt32(controlKey)
        }
        if flags.contains(.option) {
            parts.append("⌥")
            carbonMods |= UInt32(optionKey)
        }
        if flags.contains(.shift) {
            parts.append("⇧")
            carbonMods |= UInt32(shiftKey)
        }
        if flags.contains(.command) {
            parts.append("⌘")
            carbonMods |= UInt32(cmdKey)
        }
        
        guard let keyString = stringForKeyCode(keyCode) else {
            return nil
        }
        
        parts.append(keyString)
        let display = parts.joined(separator: " + ")
        return (display, carbonMods, UInt32(keyCode))
    }
    
    public static func stringForKeyCode(_ keyCode: UInt16) -> String? {
        switch Int(keyCode) {
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
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"
        case kVK_Space: return "Space"
        case kVK_Return: return "Return"
        case kVK_Tab: return "Tab"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        default: return nil
        }
    }
    
    deinit {
        unregisterHotKey()
    }
}
