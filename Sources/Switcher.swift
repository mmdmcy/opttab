import AppKit
import CoreGraphics

final class Switcher {
    static let shared = Switcher()

    private let hud = SwitcherHUD()
    private var entries: [WindowEntry] = []
    private var index = 0
    private var showing = false
    private var waitForOptionRelease = false
    private var optionReleaseTimer: Timer?
    private var lastFire: TimeInterval = 0

    func prepare() {
        hud.onChoose = { [weak self] index in
            guard let self else { return }
            self.index = index
            self.commit()
        }
    }

    var isShowing: Bool { showing }

    func showFromMenu() {
        optionReleaseTimer?.invalidate()
        optionReleaseTimer = nil
        waitForOptionRelease = false
        present(reverse: false, force: true)
    }

    func handleTab(reverse: Bool, fromHotkey: Bool) {
        waitForOptionRelease = fromHotkey || optionDown
        present(reverse: reverse, force: false)
        if showing && waitForOptionRelease {
            startOptionReleasePolling()
        }
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
            dispatchMain { [weak self] in
                self?.handleFlags(nsFlags)
            }
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
            dispatchMain { [weak self] in
                self?.cancel()
            }
            return false
        }

        switch key {
        case 48 where option && !command && !control:
            if type == .keyDown {
                dispatchMain { [weak self] in
                    self?.handleTab(reverse: shift, fromHotkey: true)
                }
            }
            return true
        case 53 where showing:
            if type == .keyDown {
                dispatchMain { [weak self] in self?.cancel() }
            }
            return true
        case 123 where showing:
            if type == .keyDown {
                dispatchMain { [weak self] in self?.move(dx: -1, dy: 0) }
            }
            return true
        case 124 where showing:
            if type == .keyDown {
                dispatchMain { [weak self] in self?.move(dx: 1, dy: 0) }
            }
            return true
        case 126 where showing:
            if type == .keyDown {
                dispatchMain { [weak self] in self?.move(dx: 0, dy: -1) }
            }
            return true
        case 125 where showing:
            if type == .keyDown {
                dispatchMain { [weak self] in self?.move(dx: 0, dy: 1) }
            }
            return true
        default:
            return false
        }
    }

    private func dispatchMain(_ work: @escaping () -> Void) {
        // CGEvent tap callbacks must return quickly or WindowServer disables
        // the tap. Never build the catalog or touch AppKit in that callback.
        DispatchQueue.main.async(execute: work)
    }

    private var optionDown: Bool {
        if NSEvent.modifierFlags.contains(.option) {
            return true
        }
        return CGEventSource.flagsState(.combinedSessionState).contains(.maskAlternate)
    }

    private func handleFlags(_ flags: NSEvent.ModifierFlags) {
        let option = flags.contains(.option)
        if showing, waitForOptionRelease, !option {
            commit()
        }
    }

    private func present(reverse: Bool, force: Bool) {
        let now = ProcessInfo.processInfo.systemUptime
        if !force, now - lastFire < 0.02 { return }
        lastFire = now

        if !showing {
            let frontID = WindowCatalog.frontWindowID()
            entries = WindowCatalog.list()
            NSLog("OptTab: found %d windows", entries.count)
            guard !entries.isEmpty else {
                NSSound.beep()
                return
            }

            // CGWindowList is front-to-back. Select the next window relative
            // to the actual front window rather than assuming it is entry 0;
            // this also makes Shift-Option-Tab work on the first press.
            if let frontIndex = entries.firstIndex(where: { $0.windowID == frontID }) {
                index = reverse
                    ? (frontIndex - 1 + entries.count) % entries.count
                    : (frontIndex + 1) % entries.count
            } else {
                index = reverse ? entries.count - 1 : 0
            }
            let target = entries[index]
            NSLog(
                "OptTab: selected index=%d/%d front=%u window=%u",
                index,
                entries.count,
                frontID ?? 0,
                target.windowID
            )
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
        if now - lastFire < 0.02 { return }
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

    private func startOptionReleasePolling() {
        optionReleaseTimer?.invalidate()
        let timer = Timer(timeInterval: 0.025, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.showing, self.waitForOptionRelease, !self.optionDown {
                self.commit()
            }
        }
        optionReleaseTimer = timer
        RunLoop.main.add(timer, forMode: .common)
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
        optionReleaseTimer?.invalidate()
        optionReleaseTimer = nil
        showing = false
        waitForOptionRelease = false
        entries = []
        index = 0
        hud.hide()
    }
}
