import AppKit

struct AppGroup {
    let key: String
    let name: String
    let icon: NSImage?
    let pid: pid_t
    let bundleID: String
    let bundleURL: URL?
    var windows: [WindowEntry]
}

final class Taskbar: NSObject {
    static let shared = Taskbar()

    private var panel: NSPanel?
    private var stack: NSStackView?
    private var clock: NSTextField?
    private var timer: Timer?
    private var lastSignature = ""
    private var lastGroupSignature = ""
    private var peek: PeekPanel?
    private var peekAnchor: TaskbarButton?
    private var peekPinned = false
    private var hoverTimer: Timer?
    private var hidePeekTimer: Timer?
    private var dismissMonitors: [Any] = []
    private var lastScreenID: CGDirectDisplayID = 0
    private var lastPeekClick: TimeInterval = 0
    private var groupOrder: [String] = []
    private var windowOrder: [String: [CGWindowID]] = [:]
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
        timer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: true) { [weak self] _ in
            self?.refresh(force: false)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(reposition), name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    func stop() {
        isVisible = false
        timer?.invalidate()
        timer = nil
        hidePeek()
        panel?.orderOut(nil)
        DockControl.restore()
        NotificationCenter.default.removeObserver(self)
    }

    @objc func reposition() {
        guard let panel else { return }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.screens.first { $0.frame.origin == .zero }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        let frame = screen?.frame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let next = NSRect(x: frame.minX, y: frame.minY, width: frame.width, height: 44)
        let screenID = (screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
        if screenID != lastScreenID {
            lastScreenID = screenID
            hidePeek()
        }
        panel.setFrame(next, display: true)
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
        panel.ignoresMouseEvents = false

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
        reposition()
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        clock?.stringValue = formatter.string(from: Date())

        if peek?.isShowing == true, !peekPinned, !mouseOverPeekUI() {
            hidePeek()
        }

        let windows = WindowCatalog.list()
        let groups = grouped(windows)
        let activeID = WindowCatalog.frontWindowID()
        let groupSignature = groups.map { group in
            group.key + ":" + group.windows.map { "\($0.windowID)" }.joined(separator: ",")
        }.joined(separator: "|")
        let signature = groupSignature + ":\(activeID ?? 0)"
        if !force, signature == lastSignature { return }
        lastSignature = signature

        if !force, groupSignature == lastGroupSignature {
            for case let button as TaskbarButton in stack?.arrangedSubviews ?? [] {
                button.active = groups.first(where: { $0.key == button.groupKey })?.windows.contains { $0.windowID == activeID } ?? false
            }
            return
        }
        lastGroupSignature = groupSignature
        rebuild(groups: groups, activeID: activeID)
    }

    private func grouped(_ windows: [WindowEntry]) -> [AppGroup] {
        var map: [String: AppGroup] = [:]
        for window in windows {
            let key = window.bundleID.isEmpty ? "pid:\(window.pid)" : window.bundleID
            if var existing = map[key] {
                existing.windows.append(window)
                map[key] = existing
            } else {
                let app = NSRunningApplication(processIdentifier: window.pid)
                map[key] = AppGroup(
                    key: key,
                    name: window.appName,
                    icon: window.icon,
                    pid: window.pid,
                    bundleID: window.bundleID,
                    bundleURL: app?.bundleURL,
                    windows: [window]
                )
            }
        }

        let live = Set(map.keys)
        groupOrder.removeAll { !live.contains($0) }
        for key in map.keys where !groupOrder.contains(key) {
            groupOrder.append(key)
        }

        for key in live {
            let ids = map[key]?.windows.map(\.windowID) ?? []
            let present = Set(ids)
            var order = windowOrder[key] ?? []
            order.removeAll { !present.contains($0) }
            for id in ids where !order.contains(id) {
                order.append(id)
            }
            windowOrder[key] = order
            if var group = map[key] {
                let lookup = Dictionary(uniqueKeysWithValues: group.windows.map { ($0.windowID, $0) })
                group.windows = order.compactMap { lookup[$0] }
                map[key] = group
            }
        }
        windowOrder = windowOrder.filter { live.contains($0.key) }
        return groupOrder.compactMap { map[$0] }
    }

    private func rebuild(groups: [AppGroup], activeID: CGWindowID?) {
        guard let stack else { return }
        let peekKey = peek?.groupKey
        let keepPeek = peekPinned || mouseOverPeekUI()
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let maxWidth = max((panel?.frame.width ?? 800) - 90, 200)
        let count = max(groups.count, 1)
        let buttonWidth = min(180, max(48, floor((maxWidth - CGFloat(count - 1) * 4 - 16) / CGFloat(count))))

        for group in groups {
            let button = TaskbarButton(group: group, width: buttonWidth)
            button.active = group.windows.contains { $0.windowID == activeID }
            button.onClick = { [weak self] in
                self?.clicked(group)
            }
            button.onHover = { [weak self] hovering in
                self?.hovered(group, hovering: hovering, from: button)
            }
            stack.addArrangedSubview(button)
            if keepPeek, peekKey == group.key {
                showPeek(group, from: button)
            }
        }
        if keepPeek, let peekKey, !groups.contains(where: { $0.key == peekKey }) {
            hidePeek()
        }
    }

    private func clicked(_ group: AppGroup) {
        hidePeekTimer?.invalidate()
        if group.windows.count == 1, let window = group.windows.first {
            hidePeek()
            WindowCatalog.toggle(window)
            return
        }
        peekPinned = true
        if let button = stack?.arrangedSubviews.compactMap({ $0 as? TaskbarButton }).first(where: { $0.groupKey == group.key }) {
            showPeek(group, from: button)
        }
    }

    private func hovered(_ group: AppGroup, hovering: Bool, from button: TaskbarButton) {
        hoverTimer?.invalidate()
        hidePeekTimer?.invalidate()
        if hovering {
            guard group.windows.count > 1 else { return }
            hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.18, repeats: false) { [weak self] _ in
                self?.showPeek(group, from: button)
            }
        } else if !peekPinned {
            hidePeekTimer = Timer.scheduledTimer(withTimeInterval: 0.22, repeats: false) { [weak self] _ in
                guard let self else { return }
                if self.peekPinned || self.mouseOverPeekUI() { return }
                self.hidePeek()
            }
        }
    }

    private func showPeek(_ group: AppGroup, from button: NSView) {
        if peek == nil {
            peek = PeekPanel()
            peek?.onChoose = { [weak self] window in
                self?.hidePeek()
                WindowCatalog.focus(window)
            }
            peek?.onClose = { [weak self] window in
                WindowCatalog.close(window)
                if (self?.peek?.cardCount ?? 1) <= 1 {
                    self?.hidePeek()
                }
            }
            peek?.onHoverChange = { [weak self] hovering in
                guard let self else { return }
                if hovering {
                    self.hidePeekTimer?.invalidate()
                } else if !self.peekPinned {
                    self.hidePeekTimer?.invalidate()
                    self.hidePeekTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { [weak self] _ in
                        guard let self else { return }
                        if self.peekPinned || self.mouseOverPeekUI() { return }
                        self.hidePeek()
                    }
                }
            }
        }
        peekAnchor = button as? TaskbarButton
        guard let peek, let panel else { return }
        peek.show(group: group, from: button, taskbar: panel)
        installPeekDismiss()
    }

    private func hidePeek() {
        hoverTimer?.invalidate()
        hidePeekTimer?.invalidate()
        peekPinned = false
        peekAnchor = nil
        peek?.hide()
        removePeekDismiss()
    }

    private func installPeekDismiss() {
        removePeekDismiss()
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            guard let self else { return }
            if self.handlePeekClick() { return }
            self.dismissPeekIfOutside()
        }) {
            dismissMonitors.append(monitor)
        }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown], handler: { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown {
                if event.keyCode == 53 {
                    self.hidePeek()
                    return nil
                }
                return event
            }
            if self.handlePeekClick() { return nil }
            if event.window === self.peek?.window { return event }
            self.dismissPeekIfOutside()
            return event
        }) {
            dismissMonitors.append(monitor)
        }
    }

    @discardableResult
    private func handlePeekClick() -> Bool {
        guard let peek, peek.isShowing else { return false }
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastPeekClick < 0.2 { return true }
        switch peek.hit(atScreen: NSEvent.mouseLocation) {
        case .focus(let window):
            lastPeekClick = now
            hidePeek()
            WindowCatalog.focus(window)
            return true
        case .close(let window):
            lastPeekClick = now
            WindowCatalog.close(window)
            hidePeek()
            return true
        case nil:
            return false
        }
    }

    private func removePeekDismiss() {
        dismissMonitors.forEach { NSEvent.removeMonitor($0) }
        dismissMonitors.removeAll()
    }

    private func dismissPeekIfOutside() {
        guard peek?.isShowing == true else { return }
        if mouseOverPeekUI() { return }
        hidePeek()
    }

    private func mouseOverPeekUI() -> Bool {
        let loc = NSEvent.mouseLocation
        if let frame = peek?.screenFrame, peek?.isShowing == true, frame.insetBy(dx: -12, dy: -12).contains(loc) {
            return true
        }
        guard let button = peekAnchor, let panel, button.window != nil else { return false }
        let buttonScreen = panel.convertToScreen(button.convert(button.bounds, to: nil))
        if buttonScreen.insetBy(dx: -8, dy: -10).contains(loc) {
            return true
        }
        if let peekFrame = peek?.screenFrame, peek?.isShowing == true {
            let gap = NSRect(
                x: min(buttonScreen.minX, peekFrame.minX),
                y: buttonScreen.maxY,
                width: max(buttonScreen.maxX, peekFrame.maxX) - min(buttonScreen.minX, peekFrame.minX),
                height: max(peekFrame.minY - buttonScreen.maxY, 0)
            )
            if gap.insetBy(dx: -10, dy: 0).contains(loc) {
                return true
            }
        }
        return false
    }
}

private final class TaskbarButton: NSView {
    let groupKey: String
    var onClick: (() -> Void)?
    var onHover: ((Bool) -> Void)?
    var active = false {
        didSet { needsDisplay = true }
    }

    private var hovered = false {
        didSet { needsDisplay = true }
    }

    private let group: AppGroup

    init(group: AppGroup, width: CGFloat) {
        self.group = group
        self.groupKey = group.key
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 36))
        wantsLayer = true
        layer?.cornerRadius = 6
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: width).isActive = true
        heightAnchor.constraint(equalToConstant: 36).isActive = true

        let icon = NSImageView()
        icon.image = group.icon
        icon.imageScaling = .scaleProportionallyDown
        icon.translatesAutoresizingMaskIntoConstraints = false

        let label = group.windows.count == 1 ? (group.windows.first?.title ?? group.name) : group.name
        let title = NSTextField(labelWithString: label)
        title.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        title.textColor = .white
        title.lineBreakMode = .byTruncatingTail
        title.drawsBackground = false
        title.isSelectable = false
        title.translatesAutoresizingMaskIntoConstraints = false
        title.isHidden = width < 72

        addSubview(icon)
        addSubview(title)

        var trailing: NSView = title
        if group.windows.count > 1 {
            let badge = NSTextField(labelWithString: "\(group.windows.count)")
            badge.font = NSFont.systemFont(ofSize: 10, weight: .bold)
            badge.textColor = NSColor.white.withAlphaComponent(0.75)
            badge.drawsBackground = false
            badge.isSelectable = false
            badge.translatesAutoresizingMaskIntoConstraints = false
            addSubview(badge)
            NSLayoutConstraint.activate([
                badge.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
                badge.centerYAnchor.constraint(equalTo: centerYAnchor),
            ])
            trailing = badge
        }

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 18),
            icon.heightAnchor.constraint(equalToConstant: 18),
            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
            title.trailingAnchor.constraint(equalTo: trailing == title ? trailingAnchor : trailing.leadingAnchor, constant: trailing == title ? -8 : -4),
            title.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
        menu = makeMenu()
    }

    required init?(coder: NSCoder) { nil }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        for window in group.windows {
            let item = NSMenuItem(title: window.title, action: #selector(focusWindow(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = NSNumber(value: window.windowID)
            menu.addItem(item)
        }
        menu.addItem(.separator())

        let minimize = NSMenuItem(
            title: group.windows.count > 1 ? "Minimize windows" : "Minimize",
            action: #selector(minimizeWindows),
            keyEquivalent: ""
        )
        minimize.target = self
        menu.addItem(minimize)

        let newWindow = NSMenuItem(title: "New Window", action: #selector(newWindow), keyEquivalent: "")
        newWindow.target = self
        menu.addItem(newWindow)

        let profiles = AppLaunch.profiles(bundleID: group.bundleID)
        if !profiles.isEmpty {
            let submenu = NSMenu()
            for profile in profiles {
                let item = NSMenuItem(title: profile.name, action: #selector(openProfile(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = profile.directory
                submenu.addItem(item)
            }
            let profilesItem = NSMenuItem(title: "Profiles", action: nil, keyEquivalent: "")
            profilesItem.submenu = submenu
            menu.addItem(profilesItem)
        }

        menu.addItem(.separator())
        let closeAll = NSMenuItem(
            title: group.windows.count > 1 ? "Close windows" : "Close window",
            action: #selector(closeWindows),
            keyEquivalent: ""
        )
        closeAll.target = self
        menu.addItem(closeAll)
        let quit = NSMenuItem(title: "Quit \(group.name)", action: #selector(quitApp), keyEquivalent: "")
        quit.target = self
        menu.addItem(quit)
        return menu
    }

    @objc private func focusWindow(_ sender: NSMenuItem) {
        guard let id = (sender.representedObject as? NSNumber)?.uint32Value,
              let window = group.windows.first(where: { $0.windowID == id })
        else { return }
        WindowCatalog.focus(window)
    }

    @objc private func minimizeWindows() {
        group.windows.forEach { WindowCatalog.minimize($0) }
    }

    @objc private func newWindow() {
        AppLaunch.newWindow(bundleURL: group.bundleURL, bundleID: group.bundleID)
    }

    @objc private func openProfile(_ sender: NSMenuItem) {
        guard let directory = sender.representedObject as? String else { return }
        AppLaunch.openProfile(bundleURL: group.bundleURL, directory: directory)
    }

    @objc private func closeWindows() {
        group.windows.forEach { WindowCatalog.close($0) }
    }

    @objc private func quitApp() {
        AppLaunch.quit(pid: group.pid)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
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

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    override func rightMouseDown(with event: NSEvent) {
        if let menu {
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        }
    }

    override func mouseEntered(with event: NSEvent) {
        hovered = true
        onHover?(true)
    }

    override func mouseExited(with event: NSEvent) {
        hovered = false
        onHover?(false)
    }
}

private enum PeekHit {
    case focus(WindowEntry)
    case close(WindowEntry)
}

private final class PeekPanel: NSObject {
    var onChoose: ((WindowEntry) -> Void)?
    var onClose: ((WindowEntry) -> Void)?
    var onHoverChange: ((Bool) -> Void)?
    private(set) var groupKey = ""
    var isShowing: Bool { panel?.isVisible == true && !groupKey.isEmpty }
    var screenFrame: NSRect { panel?.frame ?? .zero }
    var window: NSWindow? { panel }
    var cardCount: Int { cardList.count }

    private var panel: NSPanel?
    private var backdrop: PeekBackdrop?
    private var cards: [CGWindowID: PeekCard] = [:]
    private var cardList: [PeekCard] = []
    private var token = 0

    func show(group: AppGroup, from button: NSView, taskbar: NSPanel) {
        groupKey = group.key
        token += 1
        let current = token
        if panel == nil {
            panel = makePanel()
        }
        guard let panel, let content = panel.contentView else { return }
        content.subviews.forEach { $0.removeFromSuperview() }
        cards.removeAll()
        cardList.removeAll()

        let host = taskbar.screen?.frame
            ?? NSScreen.screens.first { $0.frame.intersects(taskbar.frame) }?.frame
            ?? taskbar.frame
        let count = max(group.windows.count, 1)
        var thumbW: CGFloat = count > 4 ? 148 : 184
        let padding: CGFloat = 16
        let gap: CGFloat = 8
        var width = padding + CGFloat(count) * thumbW + CGFloat(count - 1) * gap
        if width > host.width - 16 {
            thumbW = max(110, floor((host.width - 16 - padding - CGFloat(count - 1) * gap) / CGFloat(count)))
            width = padding + CGFloat(count) * thumbW + CGFloat(count - 1) * gap
        }
        let thumbH = (thumbW * 0.62).rounded()
        let height = 12 + thumbH + 30

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = gap
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        for window in group.windows {
            let card = PeekCard(window: window, thumbSize: NSSize(width: thumbW, height: thumbH))
            card.onClick = { [weak self] in
                self?.onChoose?(window)
            }
            card.onClose = { [weak self] in
                self?.onClose?(window)
            }
            stack.addArrangedSubview(card)
            cards[window.windowID] = card
            cardList.append(card)
        }

        place(panel, from: button, taskbar: taskbar, in: host, size: NSSize(width: width, height: height))
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 8),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -8),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -8),
        ])
        panel.orderFrontRegardless()

        Previews.capture(group.windows.map(\.windowID), maxPixel: thumbW * 2) { [weak self] images in
            guard let self, self.token == current, self.groupKey == group.key else { return }
            for (id, image) in images {
                self.cards[id]?.setPreview(image)
            }
        }
    }

    func hide() {
        token += 1
        groupKey = ""
        cards.removeAll()
        cardList.removeAll()
        panel?.orderOut(nil)
    }

    func hit(atScreen point: NSPoint) -> PeekHit? {
        for card in cardList {
            if let hit = card.hit(atScreen: point) {
                return hit
            }
        }
        return nil
    }

    private func place(_ panel: NSPanel, from button: NSView, taskbar: NSPanel, in host: NSRect, size: NSSize) {
        let buttonScreen = taskbar.convertToScreen(button.convert(button.bounds, to: nil))
        var x = buttonScreen.midX - size.width / 2
        x = min(max(x, host.minX + 8), max(host.minX + 8, host.maxX - size.width - 8))
        var y = taskbar.frame.maxY + 8
        if y + size.height > host.maxY - 8 {
            y = max(host.minY + 8, host.maxY - size.height - 8)
        }
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 80),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) + 1)
        panel.isOpaque = true
        panel.backgroundColor = NSColor(calibratedWhite: 0.08, alpha: 1)
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.sharingType = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .stationary]
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.ignoresMouseEvents = false

        let effect = PeekBackdrop()
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 12
        effect.layer?.masksToBounds = true
        effect.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.42).cgColor
        effect.onHover = { [weak self] hovering in
            self?.onHoverChange?(hovering)
        }
        panel.contentView = effect
        backdrop = effect
        return panel
    }
}

private final class PeekBackdrop: NSVisualEffectView {
    var onHover: ((Bool) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    required init?(coder: NSCoder) { nil }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        super.hitTest(point) ?? self
    }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
}

private final class PeekCard: NSView {
    var onClick: (() -> Void)?
    var onClose: (() -> Void)?
    let entry: WindowEntry
    private let preview = NSImageView()
    private let closeButton = CloseChip()
    private var hovered = false {
        didSet {
            needsDisplay = true
            closeButton.isHidden = !hovered
        }
    }

    init(window: WindowEntry, thumbSize: NSSize) {
        self.entry = window
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: thumbSize.width).isActive = true

        preview.wantsLayer = true
        preview.layer?.cornerRadius = 6
        preview.layer?.masksToBounds = true
        preview.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.35).cgColor
        preview.image = window.icon
        preview.imageScaling = .scaleProportionallyDown
        preview.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: window.title)
        title.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        title.textColor = .white
        title.alignment = .center
        title.lineBreakMode = .byTruncatingTail
        title.drawsBackground = false
        title.isSelectable = false
        title.translatesAutoresizingMaskIntoConstraints = false

        closeButton.isHidden = true
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.onClick = { [weak self] in self?.onClose?() }

        addSubview(preview)
        addSubview(title)
        addSubview(closeButton)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
        NSLayoutConstraint.activate([
            preview.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            preview.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            preview.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            preview.heightAnchor.constraint(equalToConstant: thumbSize.height),
            title.topAnchor.constraint(equalTo: preview.bottomAnchor, constant: 4),
            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            title.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            title.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            closeButton.topAnchor.constraint(equalTo: preview.topAnchor, constant: 4),
            closeButton.trailingAnchor.constraint(equalTo: preview.trailingAnchor, constant: -4),
            closeButton.widthAnchor.constraint(equalToConstant: 16),
            closeButton.heightAnchor.constraint(equalToConstant: 16),
        ])
    }

    required init?(coder: NSCoder) { nil }

    func setPreview(_ image: NSImage) {
        preview.image = image
        preview.imageScaling = .scaleProportionallyUpOrDown
        if let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            preview.image = nil
            preview.layer?.contents = cg
            preview.layer?.contentsGravity = .resizeAspectFill
        }
    }

    func hit(atScreen point: NSPoint) -> PeekHit? {
        guard let window else { return nil }
        let frame = window.convertToScreen(convert(bounds, to: nil))
        guard frame.contains(point) else { return nil }
        let close = window.convertToScreen(closeButton.convert(closeButton.bounds, to: nil))
        if close.insetBy(dx: -4, dy: -4).contains(point) {
            return .close(entry)
        }
        return .focus(entry)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? {
        if !closeButton.isHidden, closeButton.frame.contains(point) { return closeButton }
        return bounds.contains(point) ? self : nil
    }
    override func mouseDown(with event: NSEvent) { onClick?() }
    override func mouseEntered(with event: NSEvent) { hovered = true }
    override func mouseExited(with event: NSEvent) { hovered = false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if hovered {
            NSColor.white.withAlphaComponent(0.14).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()
        }
    }
}

private final class CloseChip: NSView {
    var onClick: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
    }

    required init?(coder: NSCoder) { nil }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onClick?() }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.white.setStroke()
        let inset = bounds.insetBy(dx: 4.5, dy: 4.5)
        let x = NSBezierPath()
        x.move(to: NSPoint(x: inset.minX, y: inset.minY))
        x.line(to: NSPoint(x: inset.maxX, y: inset.maxY))
        x.move(to: NSPoint(x: inset.maxX, y: inset.minY))
        x.line(to: NSPoint(x: inset.minX, y: inset.maxY))
        x.lineWidth = 1.4
        x.stroke()
    }
}

