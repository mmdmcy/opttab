import AppKit
import ApplicationServices

enum AppLaunch {
    struct Profile {
        let directory: String
        let name: String
    }

    static func profiles(bundleID: String) -> [Profile] {
        guard let root = userData(bundleID) else { return [] }
        let url = root.appendingPathComponent("Local State")
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let profile = json["profile"] as? [String: Any],
              let cache = profile["info_cache"] as? [String: Any]
        else { return [] }

        return cache.keys.sorted().compactMap { directory -> Profile? in
            let info = cache[directory] as? [String: Any] ?? [:]
            if (info["is_omitted_from_profile_list"] as? Bool) == true { return nil }
            let name = (info["shortcut_name"] as? String)
                ?? (info["gaia_name"] as? String)
                ?? (info["user_name"] as? String)
                ?? (info["name"] as? String)
                ?? directory
            return Profile(directory: directory, name: name)
        }
    }

    private static var launched: [Process] = []

    static func openApp(bundleURL: URL?, bundleID: String, reopenWindow: Bool = false) {
        if bundleID == "com.apple.finder" || bundleID == "com.apple.Finder" {
            newWindow(bundleURL: bundleURL, bundleID: bundleID)
            return
        }
        let url = bundleURL ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        if !bundleID.isEmpty,
           let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
            running.unhide()
            let sel = NSSelectorFromString("activateWithOptions:")
            if running.responds(to: sel) {
                _ = running.perform(sel, with: NSNumber(value: 1 << 1))
            }
            PrivateCalls.makeFront(pid: running.processIdentifier)
            let app = AXUIElementCreateApplication(running.processIdentifier)
            AXUIElementSetAttributeValue(app, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
            if reopenWindow {
                newWindow(bundleURL: url, bundleID: bundleID)
            }
            return
        }
        guard let url else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config)
    }

    static func newWindow(bundleURL: URL?, bundleID: String) {
        guard let bundleURL else { return }
        if userData(bundleID) != nil {
            open(bundleURL, args: ["--new-window"])
            return
        }
        if bundleID == "com.apple.Finder" || bundleID == "com.apple.finder" {
            NSAppleScript(source: "tell application \"Finder\" to make new Finder window")?.executeAndReturnError(nil)
            return
        }
        if bundleID == "com.apple.Safari" {
            NSAppleScript(source: "tell application id \"com.apple.Safari\" to make new document")?.executeAndReturnError(nil)
            return
        }
        if bundleID == "org.mozilla.firefox" || bundleID.hasPrefix("org.mozilla.firefox") {
            open(bundleURL, args: ["-new-window"])
            return
        }
        NSWorkspace.shared.openApplication(at: bundleURL, configuration: {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            return config
        }())
    }

    static func openProfile(bundleURL: URL?, directory: String) {
        guard let bundleURL else { return }
        open(bundleURL, args: ["--profile-directory=\(directory)", "--new-window"])
    }

    static func quit(pid: pid_t) {
        NSRunningApplication(processIdentifier: pid)?.terminate()
    }

    private static func userData(_ bundleID: String) -> URL? {
        let support = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support")
        switch bundleID {
        case "com.brave.Browser":
            return support.appendingPathComponent("BraveSoftware/Brave-Browser")
        case "com.brave.Browser.beta":
            return support.appendingPathComponent("BraveSoftware/Brave-Browser-Beta")
        case "com.brave.Browser.nightly":
            return support.appendingPathComponent("BraveSoftware/Brave-Browser-Nightly")
        case "com.google.Chrome":
            return support.appendingPathComponent("Google/Chrome")
        case "com.google.Chrome.canary":
            return support.appendingPathComponent("Google/Chrome Canary")
        case "com.google.Chrome.dev":
            return support.appendingPathComponent("Google/Chrome Dev")
        case "com.microsoft.edgemac":
            return support.appendingPathComponent("Microsoft Edge")
        case "com.vivaldi.Vivaldi":
            return support.appendingPathComponent("Vivaldi")
        default:
            return nil
        }
    }

    private static func open(_ bundleURL: URL, args: [String]) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        proc.arguments = ["-na", bundleURL.path, "--args"] + args
        proc.terminationHandler = { finished in
            DispatchQueue.main.async {
                launched.removeAll { $0 === finished }
            }
        }
        launched.append(proc)
        try? proc.run()
    }
}
