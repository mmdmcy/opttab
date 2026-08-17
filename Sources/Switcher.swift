import AppKit
import CoreGraphics

final class Switcher {
    static let shared = Switcher()

    private let hud = SwitcherHUD()
    private var entries: [WindowEntry] = []
    private var index = 0
    private var showing = false

    func prepare() {
        hud.onChoose = { [weak self] index in
            guard let self else { return }
            self.index = index
            self.commit()
        }
    }

    var isShowing: Bool { showing }

    func handleEvent(type: CGEventType, event: CGEvent) -> Bool {
        let flags = event.flags
        let option = flags.contains(.maskAlternate)
        let shift = flags.contains(.maskShift)
        let command = flags.contains(.maskCommand)
        let control = flags.contains(.maskControl)

        if type == .flagsChanged {
            if showing, !option {
                commit()
            }
            return false
        }

        guard type == .keyDown || type == .keyUp else { return false }

        let key = event.getIntegerValueField(.keyboardEventKeycode)

        if showing, command || control {
            cancel()
            return false
        }

        let swallowable = showing || (option && !command && !control)
        guard swallowable else { return false }

        switch key {
        case 48 where option && !command && !control: // Tab
            if type == .keyDown {
                tab(reverse: shift)
            }
            return true
        case 53 where showing: // Escape
            if type == .keyDown {
                cancel()
            }
            return true
        case 123 where showing, 126 where showing: // left / up
            if type == .keyDown {
                tab(reverse: true)
            }
            return true
        case 124 where showing, 125 where showing: // right / down
            if type == .keyDown {
                tab(reverse: false)
            }
            return true
        default:
            return false
        }
    }

    private func tab(reverse: Bool) {
        if !showing {
            entries = WindowCatalog.list()
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

    private func commit() {
        guard showing else { return }
        let target = entries.indices.contains(index) ? entries[index] : nil
        hide()
        if let target {
            WindowCatalog.focus(target)
        }
    }

    private func cancel() {
        guard showing else { return }
        hide()
    }

    private func hide() {
        showing = false
        entries = []
        index = 0
        hud.hide()
    }
}
