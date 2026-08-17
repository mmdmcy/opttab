import AppKit
import CoreGraphics

final class Switcher {
    static let shared = Switcher()

    private let hud = SwitcherHUD()
    private var entries: [WindowEntry] = []
    private var index = 0
    private var showing = false
    private var waitForOptionRelease = false
    private var lastFire: TimeInterval = 0

    func prepare() {
        hud.onChoose = { [weak self] index in
            guard let self else { return }
            self.index = index
            self.commit()
        }
        hud.onRequestAccess = {
            AppDelegate.shared.openAccessSettings()
        }
    }

    var isShowing: Bool { showing }

    func showFromMenu() {
        waitForOptionRelease = false
        present(reverse: false, force: true)
    }

    func handleTab(reverse: Bool, fromHotkey: Bool) {
        waitForOptionRelease = fromHotkey || optionDown
        present(reverse: reverse, force: false)
    }

    func cancel() {
        guard showing else { return }
        hide()
    }

    func handleNSEvent(_ event: NSEvent) -> Bool {
        if event.type == .flagsChanged {
            handleFlags(event.modifierFlags)
            return false
        }
        guard event.type == .keyDown else { return false }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let option = flags.contains(.option)
        let shift = flags.contains(.shift)
        let command = flags.contains(.command)
        let control = flags.contains(.control)

        if showing, event.keyCode == 53 { // escape
            cancel()
            return true
        }
        if showing, event.keyCode == 123 { // left
            move(dx: -1, dy: 0)
            return true
        }
        if showing, event.keyCode == 124 { // right
            move(dx: 1, dy: 0)
            return true
        }
        if showing, event.keyCode == 126 { // up
            move(dx: 0, dy: -1)
            return true
        }
        if showing, event.keyCode == 125 { // down
            move(dx: 0, dy: 1)
            return true
        }
        if event.keyCode == 48, option, !command, !control {
            handleTab(reverse: shift, fromHotkey: true)
            return true
        }
        return false
    }

    func handleCGEvent(type: CGEventType, event: CGEvent) -> Bool {
        if type == .flagsChanged {
            var nsFlags: NSEvent.ModifierFlags = []
            let flags = event.flags
            if flags.contains(.maskAlternate) { nsFlags.insert(.option) }
            if flags.contains(.maskShift) { nsFlags.insert(.shift) }
            if flags.contains(.maskCommand) { nsFlags.insert(.command) }
            if flags.contains(.maskControl) { nsFlags.insert(.control) }
            handleFlags(nsFlags)
            return false
        }

        guard type == .keyDown || type == .keyUp else { return false }
        let key = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        let option = flags.contains(.maskAlternate)
        let shift = flags.contains(.maskShift)
        let command = flags.contains(.maskCommand)
        let control = flags.contains(.maskControl)

        if showing, command || control {
            cancel()
            return false
        }

        switch key {
        case 48 where option && !command && !control:
            if type == .keyDown {
                handleTab(reverse: shift, fromHotkey: true)
            }
            return true
        case 53 where showing:
            if type == .keyDown { cancel() }
            return true
        case 123 where showing:
            if type == .keyDown { move(dx: -1, dy: 0) }
            return true
        case 124 where showing:
            if type == .keyDown { move(dx: 1, dy: 0) }
            return true
        case 126 where showing:
            if type == .keyDown { move(dx: 0, dy: -1) }
            return true
        case 125 where showing:
            if type == .keyDown { move(dx: 0, dy: 1) }
            return true
        default:
            return false
        }
    }

    private var optionDown: Bool {
        NSEvent.modifierFlags.contains(.option)
    }

    private func handleFlags(_ flags: NSEvent.ModifierFlags) {
        let option = flags.contains(.option)
        if showing, waitForOptionRelease, !option {
            commit()
        }
    }

    private func present(reverse: Bool, force: Bool) {
        let now = ProcessInfo.processInfo.systemUptime
        if !force, now - lastFire < 0.04 { return }
        lastFire = now

        if !showing {
            entries = WindowCatalog.list()
            NSLog("OptTab: found %d windows", entries.count)
            guard !entries.isEmpty else {
                NSSound.beep()
                return
            }
            index = entries.count > 1 ? 1 : 0
            showing = true
            hud.show(entries: entries, selected: index)
            return
        }

        guard !entries.isEmpty else { return }
        if reverse {
            index = (index - 1 + entries.count) % entries.count
        } else {
            index = (index + 1) % entries.count
        }
        hud.select(index)
    }

    private func move(dx: Int, dy: Int) {
        guard showing, !entries.isEmpty else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastFire < 0.04 { return }
        lastFire = now

        let cols = max(hud.columns, 1)
        let count = entries.count
        let row = index / cols
        let col = index % cols
        let rows = (count + cols - 1) / cols

        if dx != 0 {
            var next = index + dx
            if next < 0 { next = count - 1 }
            if next >= count { next = 0 }
            index = next
        } else {
            var newRow = row + dy
            if newRow < 0 { newRow = rows - 1 }
            if newRow >= rows { newRow = 0 }
            var next = newRow * cols + col
            if next >= count {
                next = count - 1
            }
            index = next
        }
        hud.select(index)
    }

    private func commit() {
        guard showing else { return }
        let target = entries.indices.contains(index) ? entries[index] : nil
        hide()
        if let target {
            WindowCatalog.focus(target)
        }
    }

    private func hide() {
        showing = false
        waitForOptionRelease = false
        entries = []
        index = 0
        hud.hide()
    }
}
