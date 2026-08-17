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

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    static let shared = AppDelegate()

    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Switcher.shared.prepare()
        setupStatusItem()
        Hotkeys.shared.start()
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
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

    func applicationWillTerminate(_ notification: Notification) {
        Hotkeys.shared.stop()
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "rectangle.on.rectangle", accessibilityDescription: "OptTab")
        item.button?.image?.isTemplate = true
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
        rebuildMenu(menu)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildMenu(menu)
    }

    private func rebuildMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        let ax = AXIsProcessTrusted()

        let show = NSMenuItem(title: "Show Switcher", action: #selector(showSwitcher), keyEquivalent: "")
        show.target = self
        menu.addItem(show)

        menu.addItem(.separator())

        if ax {
            menu.addItem(NSMenuItem(title: "Accessibility: on", action: nil, keyEquivalent: ""))
        } else {
            let grant = NSMenuItem(title: "Open Accessibility Settings", action: #selector(openAccessSettings), keyEquivalent: "")
            grant.target = self
            menu.addItem(grant)
            let relaunch = NSMenuItem(title: "Relaunch OptTab", action: #selector(relaunch), keyEquivalent: "")
            relaunch.target = self
            menu.addItem(relaunch)
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

        statusItem?.button?.appearsDisabled = !ax
    }

    @objc private func showSwitcher() {
        Switcher.shared.showFromMenu()
    }

    @objc func openAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func relaunch() {
        let path = Bundle.main.bundlePath
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/sh")
        proc.arguments = ["-c", "sleep 0.4; /usr/bin/open -a '\(path)'"]
        try? proc.run()
        NSApp.terminate(nil)
    }

    @objc private func toggleLoginItem() {
        LoginItem.toggle()
        if let menu = statusItem?.menu {
            rebuildMenu(menu)
        }
    }
}
