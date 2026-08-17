import AppKit

final class SwitcherHUD {
    var onChoose: ((Int) -> Void)?

    private var panel: NSPanel?
    private var cards: [CardView] = []
    private var scroll: NSScrollView?
    private var captureGeneration = 0

    func show(entries: [WindowEntry], selected: Int) {
        if panel == nil {
            panel = makePanel()
        }
        guard let panel else { return }

        let metrics = Metrics.make(count: entries.count, screen: currentScreen())
        rebuild(entries: entries, metrics: metrics)
        layout(on: panel, metrics: metrics, count: entries.count)
        select(selected)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        loadPreviews(entries)
    }

    func hide() {
        captureGeneration += 1
        panel?.orderOut(nil)
    }

    func select(_ index: Int) {
        for (i, card) in cards.enumerated() {
            card.selected = i == index
            if i == index {
                card.scrollToVisible(card.bounds.insetBy(dx: -24, dy: -12))
            }
        }
    }

    private func currentScreen() -> NSScreen? {
        NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 280),
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
        effect.layer?.cornerRadius = 12
        effect.layer?.masksToBounds = true
        effect.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.42).cgColor
        panel.contentView = effect
        return panel
    }

    private func rebuild(entries: [WindowEntry], metrics: Metrics) {
        guard let content = panel?.contentView else { return }
        content.subviews.forEach { $0.removeFromSuperview() }
        cards.removeAll()

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .top
        stack.spacing = metrics.gap
        stack.translatesAutoresizingMaskIntoConstraints = false

        for (index, entry) in entries.enumerated() {
            let card = CardView(entry: entry, metrics: metrics)
            card.translatesAutoresizingMaskIntoConstraints = false
            card.onClick = { [weak self] in
                self?.onChoose?(index)
            }
            NSLayoutConstraint.activate([
                card.widthAnchor.constraint(equalToConstant: metrics.cardWidth),
                card.heightAnchor.constraint(equalToConstant: metrics.cardHeight),
            ])
            if let preview = WindowCatalog.preview(windowID: entry.windowID) {
                card.setPreview(preview)
            }
            cards.append(card)
            stack.addArrangedSubview(card)
        }

        let needsScroll = entries.count > metrics.visibleCount
        if needsScroll {
            let scroll = NSScrollView()
            scroll.drawsBackground = false
            scroll.hasHorizontalScroller = true
            scroll.hasVerticalScroller = false
            scroll.autohidesScrollers = true
            scroll.horizontalScrollElasticity = .allowed
            scroll.verticalScrollElasticity = .none
            scroll.translatesAutoresizingMaskIntoConstraints = false
            let document = NSView()
            let width = CGFloat(entries.count) * metrics.cardWidth + CGFloat(max(entries.count - 1, 0)) * metrics.gap
            document.frame = NSRect(x: 0, y: 0, width: width, height: metrics.cardHeight)
            document.addSubview(stack)
            stack.translatesAutoresizingMaskIntoConstraints = true
            stack.frame = document.bounds
            scroll.documentView = document
            self.scroll = scroll
            content.addSubview(scroll)
            NSLayoutConstraint.activate([
                scroll.topAnchor.constraint(equalTo: content.topAnchor, constant: metrics.inset),
                scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: metrics.inset),
                scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -metrics.inset),
                scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -metrics.inset),
            ])
        } else {
            self.scroll = nil
            content.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.topAnchor.constraint(equalTo: content.topAnchor, constant: metrics.inset),
                stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: metrics.inset),
                stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -metrics.inset),
                stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -metrics.inset),
            ])
        }
    }

    private func layout(on panel: NSPanel, metrics: Metrics, count: Int) {
        let visible = min(count, metrics.visibleCount)
        let width = metrics.inset * 2
            + CGFloat(visible) * metrics.cardWidth
            + CGFloat(max(visible - 1, 0)) * metrics.gap
        let height = metrics.inset * 2 + metrics.cardHeight
        let frame = currentScreen()?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        let x = frame.midX - width / 2
        let y = frame.midY - height / 2 + 28
        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
    }

    private func loadPreviews(_ entries: [WindowEntry]) {
        captureGeneration += 1
        let generation = captureGeneration
        let missing = entries.enumerated().compactMap { index, entry -> CGWindowID? in
            cards.indices.contains(index) && cards[index].hasPreview ? nil : entry.windowID
        }
        guard !missing.isEmpty else { return }

        WindowCatalog.fillPreviews(windowIDs: missing) { [weak self] windowID, image in
            guard let self, self.captureGeneration == generation else { return }
            if let index = entries.firstIndex(where: { $0.windowID == windowID }) {
                self.cards[index].setPreview(image)
            }
        }
    }
}

private struct Metrics {
    let thumbWidth: CGFloat
    let thumbHeight: CGFloat
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    let gap: CGFloat
    let inset: CGFloat
    let visibleCount: Int

    static func make(count: Int, screen: NSScreen?) -> Metrics {
        let screenWidth = screen?.visibleFrame.width ?? 1280
        let inset: CGFloat = 22
        let gap: CGFloat = 10
        let caption: CGFloat = 34
        let ring: CGFloat = 10
        let maxWidth = screenWidth * 0.84

        let targetThumb: CGFloat
        switch count {
        case ...3: targetThumb = 260
        case 4...6: targetThumb = 200
        default: targetThumb = 164
        }

        let maxVisible = 7
        let visible = min(max(count, 1), maxVisible)
        let usable = maxWidth - inset * 2 - gap * CGFloat(visible - 1)
        let cardWidth = min(targetThumb + ring * 2, floor(usable / CGFloat(visible)))
        let thumbWidth = max(cardWidth - ring * 2, 96)
        let thumbHeight = floor(thumbWidth * 0.62)
        return Metrics(
            thumbWidth: thumbWidth,
            thumbHeight: thumbHeight,
            cardWidth: cardWidth,
            cardHeight: thumbHeight + caption + ring * 2,
            gap: gap,
            inset: inset,
            visibleCount: maxVisible
        )
    }
}

private final class CardView: NSView {
    var onClick: (() -> Void)?
    private(set) var hasPreview = false
    var selected = false {
        didSet { needsDisplay = true }
    }

    private let previewView = NSImageView()
    private let iconView = NSImageView()
    private let titleField = NSTextField(labelWithString: "")
    private let placeholderIcon = NSImageView()

    init(entry: WindowEntry, metrics: Metrics) {
        super.init(frame: .zero)
        wantsLayer = true

        previewView.imageScaling = .scaleProportionallyUpOrDown
        previewView.imageAlignment = .alignCenter
        previewView.wantsLayer = true
        previewView.layer?.cornerRadius = 6
        previewView.layer?.masksToBounds = true
        previewView.layer?.backgroundColor = NSColor(white: 0.09, alpha: 1).cgColor
        previewView.translatesAutoresizingMaskIntoConstraints = false

        placeholderIcon.image = entry.icon
        placeholderIcon.imageScaling = .scaleProportionallyDown
        placeholderIcon.translatesAutoresizingMaskIntoConstraints = false

        iconView.image = entry.icon
        iconView.imageScaling = .scaleProportionallyDown
        iconView.wantsLayer = true
        iconView.shadow = {
            let shadow = NSShadow()
            shadow.shadowBlurRadius = 6
            shadow.shadowOffset = NSSize(width: 0, height: -1)
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.55)
            return shadow
        }()
        iconView.translatesAutoresizingMaskIntoConstraints = false

        titleField.stringValue = entry.title
        titleField.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        titleField.textColor = NSColor.white.withAlphaComponent(0.92)
        titleField.alignment = .center
        titleField.lineBreakMode = .byTruncatingTail
        titleField.drawsBackground = false
        titleField.translatesAutoresizingMaskIntoConstraints = false

        addSubview(previewView)
        addSubview(placeholderIcon)
        addSubview(iconView)
        addSubview(titleField)

        NSLayoutConstraint.activate([
            previewView.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            previewView.centerXAnchor.constraint(equalTo: centerXAnchor),
            previewView.widthAnchor.constraint(equalToConstant: metrics.thumbWidth),
            previewView.heightAnchor.constraint(equalToConstant: metrics.thumbHeight),
            placeholderIcon.centerXAnchor.constraint(equalTo: previewView.centerXAnchor),
            placeholderIcon.centerYAnchor.constraint(equalTo: previewView.centerYAnchor),
            placeholderIcon.widthAnchor.constraint(equalToConstant: 54),
            placeholderIcon.heightAnchor.constraint(equalToConstant: 54),
            iconView.leadingAnchor.constraint(equalTo: previewView.leadingAnchor, constant: 7),
            iconView.bottomAnchor.constraint(equalTo: previewView.bottomAnchor, constant: -7),
            iconView.widthAnchor.constraint(equalToConstant: 26),
            iconView.heightAnchor.constraint(equalToConstant: 26),
            titleField.topAnchor.constraint(equalTo: previewView.bottomAnchor, constant: 7),
            titleField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            titleField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
        ])
    }

    required init?(coder: NSCoder) { nil }

    func setPreview(_ image: NSImage) {
        previewView.image = image
        placeholderIcon.isHidden = true
        hasPreview = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if selected {
            NSColor.white.withAlphaComponent(0.10).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 10, yRadius: 10).fill()
            let ring = NSBezierPath(roundedRect: previewView.frame.insetBy(dx: -3, dy: -3), xRadius: 8, yRadius: 8)
            ring.lineWidth = 2
            NSColor.white.withAlphaComponent(0.92).setStroke()
            ring.stroke()
        }
    }

    override func mouseUp(with event: NSEvent) {
        onClick?()
    }
}
