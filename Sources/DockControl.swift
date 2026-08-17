import AppKit

enum DockControl {
    private static let autohideKey = "opttab.savedDockAutohide"
    private static let delayKey = "opttab.savedDockDelay"

    static func hideForTaskbar() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: autohideKey) == nil {
            defaults.set(dockDefault("autohide") ?? "0", forKey: autohideKey)
            defaults.set(dockDefault("autohide-delay") ?? "0.2", forKey: delayKey)
        }
        _ = run("/usr/bin/defaults", ["write", "com.apple.dock", "autohide", "-bool", "true"])
        _ = run("/usr/bin/defaults", ["write", "com.apple.dock", "autohide-delay", "-float", "2"])
        _ = run("/usr/bin/killall", ["Dock"])
    }

    static func restore() {
        let defaults = UserDefaults.standard
        guard let autohide = defaults.string(forKey: autohideKey) else { return }
        _ = run("/usr/bin/defaults", ["write", "com.apple.dock", "autohide", "-bool", autohide == "1" || autohide.lowercased() == "true" ? "true" : "false"])
        if let delay = defaults.string(forKey: delayKey) {
            _ = run("/usr/bin/defaults", ["write", "com.apple.dock", "autohide-delay", "-float", delay])
        }
        defaults.removeObject(forKey: autohideKey)
        defaults.removeObject(forKey: delayKey)
        _ = run("/usr/bin/killall", ["Dock"])
    }

    private static func dockDefault(_ key: String) -> String? {
        run("/usr/bin/defaults", ["read", "com.apple.dock", key])
    }

    @discardableResult
    private static func run(_ launchPath: String, _ arguments: [String]) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: launchPath)
        proc.arguments = arguments
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        try? proc.run()
        proc.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
