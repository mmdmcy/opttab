import AppKit

final class SwitcherHUD {
    var onChoose: ((Int) -> Void)?
    private(set) var columns = 1

    private var panel: NSPanel?
    private var cards: [CardView] = []
    private var clickMonitor: Any?
    private var globalClickMonitor: Any?
    private var lastPick: TimeInterval = 0

    @discardableResult
    func show(entries: [WindowEntry], selected: Int) -> Int {
        if panel == nil {
            panel = makePanel()
        }
        guard let panel else { return 1 }

        let metrics = Metrics.make(count: entries.count, screen: currentScreen())
        columns = metrics.columns
        rebuild(entries: entries, metrics: metrics)
        layout(on: panel, metrics: metrics)
        select(selected)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        installClickMonitor()
        loadPreviews(entries)
        return columns
    }

    func hide() {
        removeClickMonitor()
        panel?.orderOut(nil)
    }

    func select(_ index: Int) {
        for (i, card) in cards.enumerated() {
            card.selected = i == index
        }
    }

    private func currentScreen() -> NSScreen? {
        NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 320),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = NSWindow.Level.statusBar + 2
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        panel.sharingType = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle, .stationary]
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.animationBehavior = .utilityWindow
        panel.ignoresMouseEvents = false
        panel.acceptsMouseMovedEvents = true

        let effect = BackdropView()
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 14
        effect.layer?.masksToBounds = true
        effect.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.38).cgColor
        panel.contentView = effect
        return panel
    }

    private func rebuild(entries: [WindowEntry], metrics: Metrics) {
        guard let content = panel?.contentView else { return }
        content.subviews.forEach { $0.removeFromSuperview() }
        cards.removeAll()

        let grid = NSView()
        grid.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(grid)

        for (index, entry) in entries.enumerated() {
            let card = CardView(entry: entry, previewSize: metrics.previewSize)
            card.translatesAutoresizingMaskIntoConstraints = false
            card.onClick = { [weak self] in
                self?.onChoose?(index)
            }
            let col = index % metrics.columns
            let row = index / metrics.columns
            grid.addSubview(card)
            cards.append(card)
            NSLayoutConstraint.activate([
                card.widthAnchor.constraint(equalToConstant: metrics.cardWidth),
                card.heightAnchor.constraint(equalToConstant: metrics.cardHeight),
                card.leadingAnchor.constraint(
                    equalTo: grid.leadingAnchor,
                    constant: CGFloat(col) * (metrics.cardWidth + metrics.gap)
                ),
                card.topAnchor.constraint(
                    equalTo: grid.topAnchor,
                    constant: CGFloat(row) * (metrics.cardHeight + metrics.gap)
                ),
            ])
        }

        let gridHeight = CGFloat(metrics.rows) * metrics.cardHeight + CGFloat(max(metrics.rows - 1, 0)) * metrics.gap
        let gridWidth = CGFloat(metrics.columns) * metrics.cardWidth + CGFloat(max(metrics.columns - 1, 0)) * metrics.gap

        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: content.topAnchor, constant: metrics.inset),
            grid.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            grid.widthAnchor.constraint(equalToConstant: max(gridWidth, 1)),
            grid.heightAnchor.constraint(equalToConstant: max(gridHeight, 1)),
            grid.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -metrics.inset),
        ])
    }

    private func layout(on panel: NSPanel, metrics: Metrics) {
        let gridWidth = CGFloat(metrics.columns) * metrics.cardWidth + CGFloat(max(metrics.columns - 1, 0)) * metrics.gap
        let gridHeight = CGFloat(metrics.rows) * metrics.cardHeight + CGFloat(max(metrics.rows - 1, 0)) * metrics.gap
        let width = metrics.inset * 2 + gridWidth
        let height = metrics.inset * 2 + gridHeight
        let frame = currentScreen()?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        panel.setFrame(
            NSRect(x: frame.midX - width / 2, y: frame.midY - height / 2 + 24, width: width, height: height),
            display: true
        )
    }

    private func installClickMonitor() {
        removeClickMonitor()
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self else { return event }
            return self.pickCard() ? nil : event
        }
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            _ = self?.pickCard()
        }
    }

    private func removeClickMonitor() {
        if let clickMonitor {
            NSEvent.removeMonitor(clickMonitor)
            self.clickMonitor = nil
        }
        if let globalClickMonitor {
            NSEvent.removeMonitor(globalClickMonitor)
            self.globalClickMonitor = nil
        }
    }

    @discardableResult
    private func pickCard() -> Bool {
        guard let index = cardIndex(atScreen: NSEvent.mouseLocation) else { return false }
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastPick < 0.18 { return true }
        lastPick = now
        onChoose?(index)
        return true
    }

    private func cardIndex(atScreen screenPoint: NSPoint) -> Int? {
        guard let panel, panel.isVisible, panel.frame.contains(screenPoint) else { return nil }
        let windowPoint = panel.convertPoint(fromScreen: screenPoint)
        for (index, card) in cards.enumerated() {
            let point = card.convert(windowPoint, from: nil)
            if card.bounds.contains(point) {
                return index
            }
        }
        return nil
    }

    private func loadPreviews(_ entries: [WindowEntry]) {
        let ids = entries.map(\.windowID)
        Previews.capture(ids, maxPixel: 420) { [weak self] images in
            guard let self, self.cards.count == ids.count else { return }
            for (index, id) in ids.enumerated() {
                if let image = images[id] {
                    self.cards[index].setPreview(image)
                }
            }
        }
    }
}

private final class BackdropView: NSVisualEffectView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        super.hitTest(point) ?? self
    }
}

private struct Metrics {
    let columns: Int
    let rows: Int
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    let previewSize: CGSize
    let gap: CGFloat
    let inset: CGFloat

    static func make(count: Int, screen: NSScreen?) -> Metrics {
        let count = max(count, 1)
        let columns = max(1, Int(ceil(sqrt(Double(count)))))
        let rows = max(1, Int(ceil(Double(count) / Double(columns))))
        let frame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let gap: CGFloat = 10
        let inset: CGFloat = 16
        let maxW = frame.width * 0.78
        let maxH = frame.height * 0.66
        let cardWidth = min(220, max(150, floor((maxW - inset * 2 - gap * CGFloat(columns - 1)) / CGFloat(columns))))
        let cardHeight = min(168, max(118, floor((maxH - inset * 2 - gap * CGFloat(rows - 1)) / CGFloat(rows))))
        let previewHeight = max(72, cardHeight - 44)
        return Metrics(
            columns: columns,
            rows: rows,
            cardWidth: cardWidth,
            cardHeight: cardHeight,
            previewSize: CGSize(width: cardWidth - 16, height: previewHeight),
            gap: gap,
            inset: inset
        )
    }
}

private final class CardView: NSView {
    var onClick: (() -> Void)?
    var selected = false {
        didSet { needsDisplay = true }
    }
    private var hovered = false {
        didSet { needsDisplay = true }
    }
    private let preview = NSImageView()
    private let badge = NSImageView()

    init(entry: WindowEntry, previewSize: CGSize) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 10

        preview.wantsLayer = true
        preview.layer?.cornerRadius = 7
        preview.layer?.masksToBounds = true
        preview.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.35).cgColor
        preview.image = entry.icon
        preview.imageScaling = .scaleProportionallyDown
        preview.translatesAutoresizingMaskIntoConstraints = false

        badge.image = entry.icon
        badge.imageScaling = .scaleProportionallyDown
        badge.translatesAutoresizingMaskIntoConstraints = false

        let titleField = NSTextField(labelWithString: entry.title)
        titleField.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        titleField.textColor = .white
        titleField.alignment = .center
        titleField.lineBreakMode = .byTruncatingTail
        titleField.drawsBackground = false
        titleField.isSelectable = false
        titleField.refusesFirstResponder = true
        titleField.translatesAutoresizingMaskIntoConstraints = false

        addSubview(preview)
        addSubview(badge)
        addSubview(titleField)

        NSLayoutConstraint.activate([
            preview.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            preview.centerXAnchor.constraint(equalTo: centerXAnchor),
            preview.widthAnchor.constraint(equalToConstant: previewSize.width),
            preview.heightAnchor.constraint(equalToConstant: previewSize.height),
            badge.leadingAnchor.constraint(equalTo: preview.leadingAnchor, constant: 6),
            badge.bottomAnchor.constraint(equalTo: preview.bottomAnchor, constant: -6),
            badge.widthAnchor.constraint(equalToConstant: 22),
            badge.heightAnchor.constraint(equalToConstant: 22),
            titleField.topAnchor.constraint(equalTo: preview.bottomAnchor, constant: 6),
            titleField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            titleField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            titleField.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -6),
        ])

        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
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

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    override func mouseEntered(with event: NSEvent) {
        hovered = true
    }

    override func mouseExited(with event: NSEvent) {
        hovered = false
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if selected {
            NSColor.white.withAlphaComponent(0.16).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 10, yRadius: 10).fill()
            NSColor.white.withAlphaComponent(0.9).setStroke()
            let ring = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 9, yRadius: 9)
            ring.lineWidth = 2
            ring.stroke()
        } else if hovered {
            NSColor.white.withAlphaComponent(0.08).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 10, yRadius: 10).fill()
        }
    }
}
