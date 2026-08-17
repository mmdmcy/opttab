import AppKit
import ApplicationServices

struct WindowEntry {
    let windowID: CGWindowID
    let pid: pid_t
    let appName: String
    let title: String
    let icon: NSImage?
    let axWindow: AXUIElement?
}

enum WindowCatalog {
    private static let skippedOwners: Set<String> = [
        "OptTab",
        "Window Server",
        "WindowManager",
        "Dock",
        "Control Center",
        "ControlCenter",
        "Notification Center",
        "NotificationCentre",
        "SystemUIServer",
        "OSDUIHelper",
        "loginwindow",
        "Spotlight",
        "Wallpaper",
        "TextInputMenuAgent",
        "Text Input Menu",
        "universalAccessAuthWarn",
        "AXVisualSupportAgent",
        "UserNotificationCenter",
        "Wi-Fi",
        "Item-0",
    ]

    static func list() -> [WindowEntry] {
        let ourPID = ProcessInfo.processInfo.processIdentifier
        guard let raw = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        var axCache: [pid_t: [AXUIElement]] = [:]
        var seen = Set<CGWindowID>()
        var result: [WindowEntry] = []

        func append(pid: pid_t, windowID: CGWindowID, owner: String, quartz: CGRect, cgTitle: String, axHint: AXUIElement? = nil) {
            guard !seen.contains(windowID) else { return }
            let app = NSRunningApplication(processIdentifier: pid)
            if let bundle = app?.bundleIdentifier, bundle.hasPrefix("com.apple.controlcenter") {
                return
            }
            let axList = axCache[pid] ?? {
                let list = axWindows(pid: pid)
                axCache[pid] = list
                return list
            }()
            let ax = axHint ?? matchAX(axList, windowID: windowID, quartz: quartz)
            if owner == "Finder", isDesktop(title: pickTitle(axTitle: ax.flatMap(title(of:)) ?? "", cgTitle: cgTitle, appName: owner), bounds: quartz) {
                return
            }
            let axTitle = ax.flatMap(title(of:)) ?? ""
            seen.insert(windowID)
            result.append(
                WindowEntry(
                    windowID: windowID,
                    pid: pid,
                    appName: app?.localizedName ?? owner,
                    title: pickTitle(axTitle: axTitle, cgTitle: cgTitle, appName: owner),
                    icon: app?.icon,
                    axWindow: ax
                )
            )
        }

        for info in raw {
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  pid != ourPID,
                  let windowID = info[kCGWindowNumber as String] as? CGWindowID
            else { continue }

            let layer = (info[kCGWindowLayer as String] as? Int) ?? 0
            let alpha = (info[kCGWindowAlpha as String] as? Double) ?? 1
            guard layer == 0, alpha > 0.05 else { continue }

            let owner = (info[kCGWindowOwnerName as String] as? String) ?? ""
            if skippedOwners.contains(owner) { continue }

            let boundsDict = info[kCGWindowBounds as String] as? [String: Any] ?? [:]
            let quartz = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) ?? .zero
            if quartz.width < 48 || quartz.height < 48 { continue }

            let cgTitle = (info[kCGWindowName as String] as? String) ?? ""
            if owner == "Finder", isDesktop(title: cgTitle, bounds: quartz) { continue }

            append(pid: pid, windowID: windowID, owner: owner, quartz: quartz, cgTitle: cgTitle)
        }

        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular && app.processIdentifier != ourPID {
            let pid = app.processIdentifier
            let axList = axCache[pid] ?? {
                let list = axWindows(pid: pid)
                axCache[pid] = list
                return list
            }()
            for ax in axList where isMinimized(ax) {
                let windowID = PrivateCalls.cgWindowID(of: ax) ?? 0
                guard windowID != 0 else { continue }
                append(
                    pid: pid,
                    windowID: windowID,
                    owner: app.localizedName ?? "",
                    quartz: bounds(of: ax) ?? .zero,
                    cgTitle: title(of: ax) ?? "",
                    axHint: ax
                )
            }
        }

        return result
    }

    static func focus(_ entry: WindowEntry) {
        let ax = entry.axWindow ?? axWindows(pid: entry.pid).first { PrivateCalls.cgWindowID(of: $0) == entry.windowID }

        if let ax {
            AXUIElementSetAttributeValue(ax, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }

        if let app = NSRunningApplication(processIdentifier: entry.pid) {
            if app.isHidden {
                app.unhide()
            }
            AXUIElementSetAttributeValue(AXUIElementCreateApplication(entry.pid), kAXFrontmostAttribute as CFString, kCFBooleanTrue)
            NSApp.yieldActivation(to: app)
            app.activate()
        }

        PrivateCalls.setFront(pid: entry.pid, windowID: entry.windowID)
        raise(ax, pid: entry.pid)

        DispatchQueue.main.async {
            PrivateCalls.setFront(pid: entry.pid, windowID: entry.windowID)
            raise(ax, pid: entry.pid)
            NSRunningApplication(processIdentifier: entry.pid)?.activate()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            PrivateCalls.setFront(pid: entry.pid, windowID: entry.windowID)
            raise(ax, pid: entry.pid)
        }
    }

    static func toggle(_ entry: WindowEntry) {
        if isFrontmost(entry) {
            minimize(entry)
        } else {
            focus(entry)
        }
    }

    static func isFrontmost(_ entry: WindowEntry) -> Bool {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == entry.pid else { return false }
        return list().first?.windowID == entry.windowID
    }

    static func minimize(_ entry: WindowEntry) {
        guard let ax = entry.axWindow else { return }
        AXUIElementSetAttributeValue(ax, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
    }

    static func close(_ entry: WindowEntry) {
        guard let ax = entry.axWindow else { return }
        var buttonRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(ax, kAXCloseButtonAttribute as CFString, &buttonRef) == .success,
           let button = buttonRef {
            AXUIElementPerformAction(button as! AXUIElement, kAXPressAction as CFString)
        }
    }

    private static func raise(_ ax: AXUIElement?, pid: pid_t) {
        guard let ax else { return }
        AXUIElementPerformAction(ax, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(ax, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(ax, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetAttributeValue(app, kAXFocusedWindowAttribute as CFString, ax)
        AXUIElementSetAttributeValue(app, kAXMainWindowAttribute as CFString, ax)
        AXUIElementPerformAction(ax, kAXRaiseAction as CFString)
    }

    private static func axWindows(pid: pid_t) -> [AXUIElement] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.08)
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &ref) == .success,
              let windows = ref as? [AXUIElement]
        else { return [] }
        return windows.filter { role(of: $0) == (kAXWindowRole as String) }
    }

    private static func matchAX(_ windows: [AXUIElement], windowID: CGWindowID, quartz: CGRect) -> AXUIElement? {
        for window in windows {
            if PrivateCalls.cgWindowID(of: window) == windowID {
                return window
            }
        }
        let cocoa = cocoaRect(fromQuartz: quartz)
        var best: (AXUIElement, CGFloat)?
        for window in windows {
            guard let bounds = bounds(of: window) else { continue }
            let delta =
                abs(bounds.origin.x - cocoa.origin.x) +
                abs(bounds.origin.y - cocoa.origin.y) +
                abs(bounds.width - cocoa.width) +
                abs(bounds.height - cocoa.height)
            if delta < 48, best == nil || delta < best!.1 {
                best = (window, delta)
            }
        }
        return best?.0
    }

    private static func cocoaRect(fromQuartz rect: CGRect) -> CGRect {
        let height = NSScreen.screens.first(where: { $0.frame.origin == .zero })?.frame.height
            ?? NSScreen.main?.frame.height
            ?? rect.height
        return CGRect(
            x: rect.origin.x,
            y: height - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )
    }

    private static func bounds(of window: AXUIElement) -> CGRect? {
        guard let origin = axPoint(window, kAXPositionAttribute as CFString),
              let size = axSize(window, kAXSizeAttribute as CFString)
        else { return nil }
        return CGRect(origin: origin, size: size)
    }

    private static func axPoint(_ element: AXUIElement, _ attribute: CFString) -> CGPoint? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &ref) == .success,
              let value = ref
        else { return nil }
        var point = CGPoint.zero
        guard AXValueGetValue(value as! AXValue, .cgPoint, &point) else { return nil }
        return point
    }

    private static func axSize(_ element: AXUIElement, _ attribute: CFString) -> CGSize? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &ref) == .success,
              let value = ref
        else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue(value as! AXValue, .cgSize, &size) else { return nil }
        return size
    }

    private static func title(of window: AXUIElement) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &ref) == .success else {
            return nil
        }
        let title = ref as? String ?? ""
        return title.isEmpty ? nil : title
    }

    private static func role(of element: AXUIElement) -> String {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &ref) == .success else {
            return ""
        }
        return (ref as? String) ?? ""
    }

    private static func isMinimized(_ window: AXUIElement?) -> Bool {
        guard let window else { return false }
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &ref) == .success else {
            return false
        }
        return (ref as? Bool) ?? false
    }

    private static func pickTitle(axTitle: String, cgTitle: String, appName: String) -> String {
        if !axTitle.isEmpty { return axTitle }
        if !cgTitle.isEmpty { return cgTitle }
        return appName
    }

    private static func isDesktop(title: String, bounds: CGRect) -> Bool {
        if title == "Desktop" { return true }
        let screen = NSScreen.main?.frame ?? .zero
        return title.isEmpty && bounds.width >= screen.width - 16 && bounds.height >= screen.height - 16
    }
}
