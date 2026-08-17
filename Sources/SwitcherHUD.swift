import AppKit

final class SwitcherHUD {
    var onChoose: ((Int) -> Void)?

    private var panel: NSPanel?
    private var rows: [RowView] = []
    private var scroll: NSScrollView?

    func show(entries: [WindowEntry], selected: Int) {
        if panel == nil {
            panel = makePanel()
        }
        guard let panel else { return }

        rebuild(entries: entries)
        select(selected)
        layout(on: panel, count: entries.count)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.08
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.06
            panel.animator().alphaValue = 0
        } completionHandler: {
            panel.orderOut(nil)
        }
    }

    func select(_ index: Int) {
        for (i, row) in rows.enumerated() {
            row.selected = i == index
            if i == index {
                row.scrollToVisible(row.bounds.insetBy(dx: 0, dy: -8))
            }
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 240),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.sharingType = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.animationBehavior = .none

        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 18
        effect.layer?.masksToBounds = true
        panel.contentView = effect
        return panel
    }

    private func rebuild(entries: [WindowEntry]) {
        guard let content = panel?.contentView else { return }
        content.subviews.forEach { $0.removeFromSuperview() }
        rows.removeAll()

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 2
        stack.alignment = .leading
        stack.distribution = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false

        for (index, entry) in entries.enumerated() {
            let row = RowView(entry: entry)
            row.translatesAutoresizingMaskIntoConstraints = false
            row.onClick = { [weak self] in
                self?.onChoose?(index)
            }
            NSLayoutConstraint.activate([
                row.heightAnchor.constraint(equalToConstant: 58),
                row.widthAnchor.constraint(equalTo: stack.widthAnchor),
            ])
            rows.append(row)
            stack.addArrangedSubview(row)
        }

        let hint = NSTextField(labelWithString: "Tab next  ·  ⇧Tab back  ·  release ⌥ to switch  ·  esc cancel")
        hint.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        hint.textColor = NSColor.white.withAlphaComponent(0.45)
        hint.alignment = .center
        hint.translatesAutoresizingMaskIntoConstraints = false

        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = entries.count > 8
        scroll.autohidesScrollers = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = stack
        self.scroll = scroll

        content.addSubview(scroll)
        content.addSubview(hint)

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: content.topAnchor, constant: 10),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 10),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -10),
            hint.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 6),
            hint.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            hint.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            hint.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -10),
            stack.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            stack.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
        ])
    }

    private func layout(on panel: NSPanel, count: Int) {
        let rowsShown = min(count, 8)
        let height = CGFloat(20 + rowsShown * 60 + 28)
        let width: CGFloat = 540
        let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        let frame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        let x = frame.midX - width / 2
        let y = frame.midY - height / 2 + 36
        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
    }
}

private final class RowView: NSView {
    var onClick: (() -> Void)?
    var selected = false {
        didSet { needsDisplay = true }
    }

    private let iconView = NSImageView()
    private let titleField = NSTextField(labelWithString: "")
    private let subtitleField = NSTextField(labelWithString: "")

    init(entry: WindowEntry) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 10

        iconView.image = entry.icon
        iconView.imageScaling = .scaleProportionallyDown
        iconView.translatesAutoresizingMaskIntoConstraints = false

        titleField.stringValue = entry.title
        titleField.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        titleField.textColor = .white
        titleField.lineBreakMode = .byTruncatingTail
        titleField.translatesAutoresizingMaskIntoConstraints = false

        subtitleField.stringValue = entry.appName
        subtitleField.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        subtitleField.textColor = NSColor.white.withAlphaComponent(0.55)
        subtitleField.lineBreakMode = .byTruncatingTail
        subtitleField.translatesAutoresizingMaskIntoConstraints = false

        addSubview(iconView)
        addSubview(titleField)
        addSubview(subtitleField)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 36),
            iconView.heightAnchor.constraint(equalToConstant: 36),
            titleField.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            titleField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            titleField.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            subtitleField.leadingAnchor.constraint(equalTo: titleField.leadingAnchor),
            subtitleField.trailingAnchor.constraint(equalTo: titleField.trailingAnchor),
            subtitleField.topAnchor.constraint(equalTo: titleField.bottomAnchor, constant: 1),
        ])
    }

    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if selected {
            NSColor.controlAccentColor.withAlphaComponent(0.22).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 10, yRadius: 10).fill()
            NSColor.controlAccentColor.setFill()
            NSBezierPath(roundedRect: NSRect(x: 4, y: 10, width: 3, height: bounds.height - 20), xRadius: 1.5, yRadius: 1.5).fill()
        }
    }

    override func mouseUp(with event: NSEvent) {
        onClick?()
    }
}
