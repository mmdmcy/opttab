import AppKit
import ApplicationServices
import Carbon
import CoreGraphics

final class Hotkeys {
    static let shared = Hotkeys()

    private var carbonHandler: EventHandlerRef?
    private var carbonKeys: [EventHotKeyRef] = []
    private var monitors: [Any] = []
    private var tapPort: CFMachPort?
    private var tapSource: CFRunLoopSource?

    func start() {
        stop()
        installCarbon()
        installMonitors()
        requestInputMonitoring()
        installTapIfAllowed()
        NSLog(
            "OptTab: hotkeys started ax=%d listen=%d carbon=%d tap=%d",
            AXIsProcessTrusted() ? 1 : 0,
            CGPreflightListenEventAccess() ? 1 : 0,
            carbonKeys.isEmpty ? 0 : 1,
            tapPort == nil ? 0 : 1
        )
    }

    func stop() {
        carbonKeys.forEach { UnregisterEventHotKey($0) }
        carbonKeys.removeAll()
        if let carbonHandler {
            RemoveEventHandler(carbonHandler)
            self.carbonHandler = nil
        }
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
        if let tapPort {
            CGEvent.tapEnable(tap: tapPort, enable: false)
        }
        if let tapSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), tapSource, .commonModes)
        }
        tapPort = nil
        tapSource = nil
    }

    func requestInputMonitoring() {
        if !CGPreflightListenEventAccess() {
            _ = CGRequestListenEventAccess()
        }
    }

    func reenableTap() {
        if let tapPort {
            CGEvent.tapEnable(tap: tapPort, enable: true)
        }
    }

    private func installCarbon() {
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let err = InstallEventHandler(
            GetApplicationEventTarget(),
            optTabCarbonHandler,
            1,
            &spec,
            nil,
            &carbonHandler
        )
        if err != noErr {
            NSLog("OptTab: carbon handler failed %d", err)
        }

        registerCarbon(id: 1, key: UInt32(kVK_Tab), modifiers: UInt32(optionKey))
        registerCarbon(id: 2, key: UInt32(kVK_Tab), modifiers: UInt32(optionKey | shiftKey))
    }

    private func registerCarbon(id: UInt32, key: UInt32, modifiers: UInt32) {
        let hotKeyID = EventHotKeyID(signature: optTabHotKeySignature, id: id)
        var ref: EventHotKeyRef?
        let err = RegisterEventHotKey(key, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        if err == noErr, let ref {
            carbonKeys.append(ref)
        } else {
            NSLog("OptTab: carbon hotkey %u failed %d", id, err)
        }
    }

    private func installMonitors() {
        let keys: NSEvent.EventTypeMask = [.keyDown, .flagsChanged]
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: keys, handler: { event in
            _ = Switcher.shared.handleNSEvent(event)
        }) {
            monitors.append(monitor)
        }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: keys, handler: { event in
            Switcher.shared.handleNSEvent(event) ? nil : event
        }) {
            monitors.append(monitor)
        }
    }

    private func installTapIfAllowed() {
        guard CGPreflightListenEventAccess() || AXIsProcessTrusted() else { return }

        let mask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: optTabCGEventCallback,
            userInfo: nil
        ) else {
            NSLog("OptTab: event tap create failed")
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        tapPort = tap
        tapSource = source
        NSLog("OptTab: event tap enabled")
    }
}

let optTabHotKeySignature: OSType = 0x4F545442

private func optTabCarbonHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    let err = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard err == noErr, hotKeyID.signature == optTabHotKeySignature else {
        return OSStatus(eventNotHandledErr)
    }

    DispatchQueue.main.async {
        switch hotKeyID.id {
        case 1:
            Switcher.shared.handleTab(reverse: false, fromHotkey: true)
        case 2:
            Switcher.shared.handleTab(reverse: true, fromHotkey: true)
        default:
            break
        }
    }
    return noErr
}

private func optTabCGEventCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        Hotkeys.shared.reenableTap()
        return Unmanaged.passUnretained(event)
    }

    if Switcher.shared.handleCGEvent(type: type, event: event) {
        return nil
    }
    return Unmanaged.passUnretained(event)
}
