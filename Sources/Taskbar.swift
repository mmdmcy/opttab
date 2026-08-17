import AppKit

final class Taskbar {
    static let shared = Taskbar()

    private var panel: NSPanel?
    private var stack: NSStackView?
    private var clock: NSTextField?
    private var timer: Timer?
    private var lastSignature = ""
    private var buttons: [CGWindowID: TaskbarButton] = [:]
    private(set) var isVisible = false

    func start() {
        guard !isVisible else { return }
        isVisible = true
        DockControl.hideForTaskbar()
        if panel == nil {
            panel = makePanel()
        }
        reposition()
        panel?.orderFrontRegardless()
        refresh(force: true)
        timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            self?.refresh(force: false)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(reposition), name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    func stop() {
        isVisible = false
        timer?.invalidate()
        timer = nil
        panel?.orderOut(nil)
        DockControl.restore()
        NotificationCenter.default.removeObserver(self)
    }

    @objc func reposition() {
        guard let panel else { return }
        let screen = NSScreen.main ?? NSScreen.screens.first
        let frame = screen?.frame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let height: CGFloat = 44
        panel.setFrame(NSRect(x: frame.minX, y: frame.minY, width: frame.width, height: height), display: true)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 44),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)))
        panel.isOpaque = true
        panel.backgroundColor = NSColor(calibratedWhite: 0.11, alpha: 1)
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.sharingType = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.animationBehavior = .none

        let root = NSView()
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor(calibratedWhite: 0.11, alpha: 1).cgColor
        panel.contentView = root

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 4
        stack.alignment = .centerY
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        self.stack = stack

        let clock = NSTextField(labelWithString: "")
        clock.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        clock.textColor = NSColor.white.withAlphaComponent(0.9)
        clock.alignment = .right
        clock.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(clock)
        self.clock = clock

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.topAnchor.constraint(equalTo: root.topAnchor),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            clock.leadingAnchor.constraint(greaterThanOrEqualTo: stack.trailingAnchor, constant: 12),
            clock.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14),
            clock.centerYAnchor.constraint(equalTo: root.centerYAnchor),
            clock.widthAnchor.constraint(equalToConstant: 58),
        ])
        return panel
    }

    private func refresh(force: Bool) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        clock?.stringValue = formatter.string(from: Date())

        let windows = WindowCatalog.list()
        let activeID = windows.first?.windowID
        let signature = windows.map { "\($0.windowID):\($0.title)" }.joined(separator: "|") + ":\(activeID ?? 0)"
        if !force, signature == lastSignature { return }
        lastSignature = signature
        rebuild(windows: windows, activeID: activeID)
    }

    private func rebuild(windows: [WindowEntry], activeID: CGWindowID?) {
        guard let stack else { return }
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        buttons.removeAll()

        let maxWidth = max((panel?.frame.width ?? 800) - 90, 200)
        let count = max(windows.count, 1)
        let buttonWidth = min(220, max(48, floor((maxWidth - CGFloat(count - 1) * 4 - 16) / CGFloat(count))))

        for entry in windows {
            let button = TaskbarButton(entry: entry, width: buttonWidth)
            button.active = entry.windowID == activeID
            button.onClick = { WindowCatalog.toggle(entry) }
            button.onClose = { WindowCatalog.close(entry) }
            stack.addArrangedSubview(button)
            buttons[entry.windowID] = button
        }
    }
}

private final class TaskbarButton: NSView {
    var onClick: (() -> Void)?
    var onClose: (() -> Void)?
    var active = false {
        didSet { needsDisplay = true }
    }

    private var hovered = false {
        didSet { needsDisplay = true }
    }

    init(entry: WindowEntry, width: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 36))
        wantsLayer = true
        layer?.cornerRadius = 6
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: width).isActive = true
        heightAnchor.constraint(equalToConstant: 36).isActive = true

        let icon = NSImageView()
        icon.image = entry.icon
        icon.imageScaling = .scaleProportionallyDown
        icon.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: entry.title)
        title.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        title.textColor = .white
        title.lineBreakMode = .byTruncatingTail
        title.drawsBackground = false
        title.translatesAutoresizingMaskIntoConstraints = false
        title.isHidden = width < 72

        addSubview(icon)
        addSubview(title)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 18),
            icon.heightAnchor.constraint(equalToConstant: 18),
            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
            title.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            title.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
        menu = makeMenu()
    }

    required init?(coder: NSCoder) { nil }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        let close = NSMenuItem(title: "Close window", action: #selector(closeWindow), keyEquivalent: "")
        close.target = self
        menu.addItem(close)
        return menu
    }

    @objc private func closeWindow() {
        onClose?()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if active {
            NSColor.white.withAlphaComponent(0.16).setFill()
        } else if hovered {
            NSColor.white.withAlphaComponent(0.08).setFill()
        } else {
            NSColor.clear.setFill()
        }
        NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
        if active {
            NSColor.controlAccentColor.setFill()
            NSBezierPath(rect: NSRect(x: 8, y: 1, width: bounds.width - 16, height: 2)).fill()
        }
    }

    override func mouseUp(with event: NSEvent) {
        if event.type == .rightMouseUp { return }
        onClick?()
    }

    override func mouseEntered(with event: NSEvent) { hovered = true }
    override func mouseExited(with event: NSEvent) { hovered = false }
}
