import AppKit

final class SwitcherHUD {
    var onChoose: ((Int) -> Void)?
    var onRequestAccess: (() -> Void)?
    private(set) var columns = 1

    private var panel: NSPanel?
    private var cards: [CardView] = []

    @discardableResult
    func show(entries: [WindowEntry], selected: Int) -> Int {
        if panel == nil {
            panel = makePanel()
        }
        guard let panel else { return 1 }

        let metrics = Metrics.make(count: entries.count, screen: currentScreen(), needsBanner: !AXIsProcessTrusted())
        columns = metrics.columns
        rebuild(entries: entries, metrics: metrics)
        layout(on: panel, metrics: metrics)
        select(selected)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        return columns
    }

    func hide() {
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

        let effect = NSVisualEffectView()
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
            let card = CardView(entry: entry, iconSize: metrics.iconSize)
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

        var banner: NSView?
        if metrics.needsBanner {
            let button = NSButton(title: "Accessibility is off — click here to grant it", target: self, action: #selector(requestAccess))
            button.isBordered = false
            button.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
            button.contentTintColor = NSColor.systemYellow
            button.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(button)
            banner = button
        }

        let gridHeight = CGFloat(metrics.rows) * metrics.cardHeight + CGFloat(max(metrics.rows - 1, 0)) * metrics.gap
        let gridWidth = CGFloat(metrics.columns) * metrics.cardWidth + CGFloat(max(metrics.columns - 1, 0)) * metrics.gap

        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: content.topAnchor, constant: metrics.inset),
            grid.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            grid.widthAnchor.constraint(equalToConstant: max(gridWidth, 1)),
            grid.heightAnchor.constraint(equalToConstant: max(gridHeight, 1)),
        ])

        if let banner {
            NSLayoutConstraint.activate([
                banner.topAnchor.constraint(equalTo: grid.bottomAnchor, constant: 10),
                banner.centerXAnchor.constraint(equalTo: content.centerXAnchor),
                banner.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
            ])
        } else {
            grid.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -metrics.inset).isActive = true
        }
    }

    private func layout(on panel: NSPanel, metrics: Metrics) {
        let gridWidth = CGFloat(metrics.columns) * metrics.cardWidth + CGFloat(max(metrics.columns - 1, 0)) * metrics.gap
        let gridHeight = CGFloat(metrics.rows) * metrics.cardHeight + CGFloat(max(metrics.rows - 1, 0)) * metrics.gap
        let banner: CGFloat = metrics.needsBanner ? 32 : 0
        let width = metrics.inset * 2 + gridWidth
        let height = metrics.inset * 2 + gridHeight + banner
        let frame = currentScreen()?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        panel.setFrame(
            NSRect(x: frame.midX - width / 2, y: frame.midY - height / 2 + 24, width: width, height: height),
            display: true
        )
    }

    @objc private func requestAccess() {
        onRequestAccess?()
    }
}

private struct Metrics {
    let columns: Int
    let rows: Int
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    let iconSize: CGFloat
    let gap: CGFloat
    let inset: CGFloat
    let needsBanner: Bool

    static func make(count: Int, screen: NSScreen?, needsBanner: Bool) -> Metrics {
        let count = max(count, 1)
        let columns = max(1, Int(ceil(sqrt(Double(count)))))
        let rows = max(1, Int(ceil(Double(count) / Double(columns))))
        let frame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let gap: CGFloat = 8
        let inset: CGFloat = 16
        let banner: CGFloat = needsBanner ? 32 : 0
        let maxW = frame.width * 0.72
        let maxH = frame.height * 0.64
        let cardWidth = min(156, max(108, floor((maxW - inset * 2 - gap * CGFloat(columns - 1)) / CGFloat(columns))))
        let cardHeight = min(128, max(92, floor((maxH - inset * 2 - banner - gap * CGFloat(rows - 1)) / CGFloat(rows))))
        let iconSize: CGFloat = cardHeight >= 116 ? 52 : 40
        return Metrics(
            columns: columns,
            rows: rows,
            cardWidth: cardWidth,
            cardHeight: cardHeight,
            iconSize: iconSize,
            gap: gap,
            inset: inset,
            needsBanner: needsBanner
        )
    }
}

private final class CardView: NSView {
    var onClick: (() -> Void)?
    var selected = false {
        didSet { needsDisplay = true }
    }

    init(entry: WindowEntry, iconSize: CGFloat) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 10

        let iconView = NSImageView()
        iconView.image = entry.icon
        iconView.imageScaling = .scaleProportionallyDown
        iconView.translatesAutoresizingMaskIntoConstraints = false

        let titleField = NSTextField(labelWithString: entry.title)
        titleField.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        titleField.textColor = .white
        titleField.alignment = .center
        titleField.lineBreakMode = .byTruncatingTail
        titleField.drawsBackground = false
        titleField.translatesAutoresizingMaskIntoConstraints = false

        let subtitle = entry.appName == entry.title ? "" : entry.appName
        let subtitleField = NSTextField(labelWithString: subtitle)
        subtitleField.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        subtitleField.textColor = NSColor.white.withAlphaComponent(0.55)
        subtitleField.alignment = .center
        subtitleField.lineBreakMode = .byTruncatingTail
        subtitleField.drawsBackground = false
        subtitleField.translatesAutoresizingMaskIntoConstraints = false

        addSubview(iconView)
        addSubview(titleField)
        addSubview(subtitleField)

        NSLayoutConstraint.activate([
            iconView.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconView.widthAnchor.constraint(equalToConstant: iconSize),
            iconView.heightAnchor.constraint(equalToConstant: iconSize),
            titleField.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 8),
            titleField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            titleField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            subtitleField.topAnchor.constraint(equalTo: titleField.bottomAnchor, constant: 1),
            subtitleField.leadingAnchor.constraint(equalTo: titleField.leadingAnchor),
            subtitleField.trailingAnchor.constraint(equalTo: titleField.trailingAnchor),
        ])
    }

    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if selected {
            NSColor.white.withAlphaComponent(0.14).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 10, yRadius: 10).fill()
            NSColor.white.withAlphaComponent(0.9).setStroke()
            let ring = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 9, yRadius: 9)
            ring.lineWidth = 2
            ring.stroke()
        }
    }

    override func mouseUp(with event: NSEvent) {
        onClick?()
    }
}
