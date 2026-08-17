import AppKit
import ApplicationServices
import CoreGraphics

@main
enum OptTab {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate.shared
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    static let shared = AppDelegate()

    private var statusItem: NSStatusItem?
    private var trustTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Switcher.shared.prepare()
        setupStatusItem()
        Hotkeys.shared.start()
        refreshTrust()
        promptIfNeeded()
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )

        trustTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.refreshTrust()
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "opttab" {
            if url.host == "show" {
                Switcher.shared.showFromMenu()
            }
        }
    }

    @objc private func handleGetURLEvent(_ event: NSAppleEventDescriptor, withReplyEvent replyEvent: NSAppleEventDescriptor) {
        let string = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue ?? ""
        if string.contains("show") {
            Switcher.shared.showFromMenu()
        }
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "rectangle.on.rectangle", accessibilityDescription: "OptTab")
        item.button?.image?.isTemplate = true
        statusItem = item
        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        let ax = AXIsProcessTrusted()
        let listen = CGPreflightListenEventAccess()

        let show = NSMenuItem(title: "Show Switcher", action: #selector(showSwitcher), keyEquivalent: "")
        show.target = self
        menu.addItem(show)

        menu.addItem(.separator())

        let screen = CGPreflightScreenCaptureAccess()

        menu.addItem(statusItem(title: ax ? "Accessibility: on" : "Accessibility: needed", ok: ax))
        menu.addItem(statusItem(title: listen ? "Input Monitoring: on" : "Input Monitoring: needed", ok: listen))
        menu.addItem(statusItem(title: screen ? "Screen Recording: on" : "Screen Recording: needed for previews", ok: screen))

        if !ax || !listen || !screen {
            let grant = NSMenuItem(title: "Grant Permissions…", action: #selector(openPermissions), keyEquivalent: "")
            grant.target = self
            menu.addItem(grant)
        }

        menu.addItem(.separator())

        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLoginItem), keyEquivalent: "")
        login.target = self
        login.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Option+Tab switches windows", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit OptTab", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        statusItem?.menu = menu
        statusItem?.button?.appearsDisabled = !ax && !listen
    }

    private func statusItem(title: String, ok: Bool) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: ok ? nil : #selector(openPermissions), keyEquivalent: "")
        item.target = ok ? nil : self
        return item
    }

    private func refreshTrust() {
        rebuildMenu()
    }

    private func promptIfNeeded() {
        if !AXIsProcessTrusted() {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }
        Hotkeys.shared.requestInputMonitoring()
        if !CGPreflightScreenCaptureAccess() {
            _ = CGRequestScreenCaptureAccess()
        }
    }

    @objc private func showSwitcher() {
        Switcher.shared.showFromMenu()
    }

    @objc private func openPermissions() {
        promptIfNeeded()
        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture",
        ]
        for string in urls {
            if let url = URL(string: string) {
                NSWorkspace.shared.open(url)
            }
        }
    }

    @objc private func toggleLoginItem() {
        LoginItem.toggle()
        rebuildMenu()
    }
}
