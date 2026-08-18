import AppKit

final class AppsLauncher {
    static let shared = AppsLauncher()

    private var panel: NSPanel?
    private var shownAt: TimeInterval = 0
    private var monitors: [Any] = []
    private var buttons: [AppButton] = []
    private weak var anchor: NSView?
    private weak var taskbar: NSPanel?
    private(set) var isShowing = false

    func toggle(from button: NSView, taskbar: NSPanel) {
        if isShowing {
            hide()
        } else {
            show(from: button, taskbar: taskbar)
        }
    }

    func hide() {
        isShowing = false
        removeMonitors()
        buttons.removeAll()
        if let panel {
            panel.parent?.removeChildWindow(panel)
            panel.orderOut(nil)
        }
    }

    private func show(from button: NSView, taskbar: NSPanel) {
        anchor = button
        self.taskbar = taskbar
        if panel == nil {
            panel = makePanel()
        }
        guard let panel, let content = panel.contentView else { return }
        content.subviews.forEach { $0.removeFromSuperview() }
        buttons.removeAll()

        let apps = Self.installed()
        let columns = 6
        let cell: CGFloat = 88
        let gap: CGFloat = 8
        let inset: CGFloat = 14
        let rows = max(1, Int(ceil(Double(max(apps.count, 1)) / Double(columns))))
        let width = inset * 2 + CGFloat(columns) * cell + CGFloat(columns - 1) * gap
        let gridHeight = CGFloat(rows) * cell + CGFloat(max(rows - 1, 0)) * gap
        let header: CGFloat = 36
        let height = min(header + inset + gridHeight + inset, 460)

        let title = NSTextField(labelWithString: "Applications")
        title.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        title.textColor = .white
        title.drawsBackground = false
        title.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(title)

        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.scrollerStyle = .overlay
        scroll.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(scroll)

        let document = FlippedView(frame: NSRect(x: 0, y: 0, width: width - 18, height: max(gridHeight + inset, height - header)))
        scroll.documentView = document

        for (index, app) in apps.enumerated() {
            let item = AppButton(app: app)
            item.frame = NSRect(
                x: inset + CGFloat(index % columns) * (cell + gap),
                y: CGFloat(index / columns) * (cell + gap),
                width: cell,
                height: cell
            )
            item.onClick = { [weak self] in
                self?.hide()
                AppLaunch.openApp(
                    bundleURL: app.url,
                    bundleID: Bundle(url: app.url)?.bundleIdentifier ?? ""
                )
            }
            document.addSubview(item)
            buttons.append(item)
        }

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            title.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            scroll.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -8),
        ])

        let host = NSScreen.screens.first { $0.frame.intersects(taskbar.frame) }?.frame
            ?? taskbar.screen?.frame
            ?? taskbar.frame
        let buttonScreen = taskbar.convertToScreen(button.convert(button.bounds, to: nil))
        var x = buttonScreen.minX
        x = min(max(x, host.minX + 8), max(host.minX + 8, host.maxX - width - 8))
        var y = taskbar.frame.maxY + 8
        if y + height > host.maxY - 8 {
            y = max(host.minY + 8, host.maxY - height - 8)
        }
        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
        if panel.parent !== taskbar {
            panel.parent?.removeChildWindow(panel)
            taskbar.addChildWindow(panel, ordered: .above)
        }
        panel.orderFrontRegardless()
        taskbar.orderFrontRegardless()
        isShowing = true
        shownAt = ProcessInfo.processInfo.systemUptime
        DispatchQueue.main.async { [weak self] in
            self?.installDismiss()
        }
    }

    private func installDismiss() {
        removeMonitors()
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            self?.dismissIfOutside()
        }) {
            monitors.append(monitor)
        }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown], handler: { [weak self] event in
            guard let self else { return event }
            if self.pickApp(at: NSEvent.mouseLocation) {
                return nil
            }
            self.dismissIfOutside()
            return event
        }) {
            monitors.append(monitor)
        }
    }

    private func removeMonitors() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
    }

    private func dismissIfOutside() {
        guard isShowing, ProcessInfo.processInfo.systemUptime - shownAt > 0.25 else { return }
        if keepOpen(at: NSEvent.mouseLocation) { return }
        hide()
    }

    private func keepOpen(at point: NSPoint) -> Bool {
        if panel?.frame.contains(point) == true { return true }
        guard let anchor, let taskbar else { return false }
        let rect = taskbar.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        return rect.contains(point)
    }

    @discardableResult
    private func pickApp(at point: NSPoint) -> Bool {
        guard isShowing, let panel, panel.frame.contains(point) else { return false }
        for button in buttons {
            guard let window = button.window else { continue }
            let frame = window.convertToScreen(button.convert(button.bounds, to: nil))
            if frame.contains(point) {
                button.onClick?()
                return true
            }
        }
        return false
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 320),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) + 2)
        panel.isOpaque = true
        panel.backgroundColor = NSColor(calibratedWhite: 0.1, alpha: 1)
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.sharingType = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle, .stationary]
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.ignoresMouseEvents = false
        panel.becomesKeyOnlyIfNeeded = true

        let effect = Backdrop()
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 14
        effect.layer?.masksToBounds = true
        effect.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.35).cgColor
        panel.contentView = effect
        return panel
    }

    struct App {
        let name: String
        let url: URL
        let icon: NSImage
    }

    private static func installed() -> [App] {
        let roots = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            URL(fileURLWithPath: "/System/Applications/Utilities"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications"),
        ]
        var seen = Set<String>()
        var result: [App] = []
        for root in roots {
            guard let items = try? FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }
            for url in items where url.pathExtension == "app" {
                let name = url.deletingPathExtension().lastPathComponent
                if name == "OptTab" || name == "Launchpad" || !seen.insert(name).inserted { continue }
                result.append(App(name: name, url: url, icon: NSWorkspace.shared.icon(forFile: url.path)))
            }
        }
        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

private final class Backdrop: NSVisualEffectView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { super.hitTest(point) ?? self }
}

private final class AppButton: NSView {
    var onClick: (() -> Void)?
    private var hovered = false {
        didSet { needsDisplay = true }
    }

    init(app: AppsLauncher.App) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 10

        let icon = NSImageView()
        icon.image = app.icon
        icon.imageScaling = .scaleProportionallyDown
        icon.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: app.name)
        title.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        title.textColor = .white
        title.alignment = .center
        title.lineBreakMode = .byTruncatingTail
        title.drawsBackground = false
        title.isSelectable = false
        title.translatesAutoresizingMaskIntoConstraints = false

        addSubview(icon)
        addSubview(title)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
        NSLayoutConstraint.activate([
            icon.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            icon.centerXAnchor.constraint(equalTo: centerXAnchor),
            icon.widthAnchor.constraint(equalToConstant: 42),
            icon.heightAnchor.constraint(equalToConstant: 42),
            title.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 4),
            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            title.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
        ])
    }

    required init?(coder: NSCoder) { nil }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { bounds.contains(point) ? self : nil }
    override func mouseDown(with event: NSEvent) { onClick?() }
    override func mouseEntered(with event: NSEvent) { hovered = true }
    override func mouseExited(with event: NSEvent) { hovered = false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if hovered {
            NSColor.white.withAlphaComponent(0.12).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 10, yRadius: 10).fill()
        }
    }
}
