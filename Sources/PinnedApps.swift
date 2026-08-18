import AppKit

enum PinnedApps {
    static let finderID = "com.apple.finder"
    static let appsID = "__apps__"
    private static let key = "opttab.pinned"

    static var ids: [String] {
        get { UserDefaults.standard.stringArray(forKey: key) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    static func isPinned(_ bundleID: String) -> Bool {
        locked.contains(bundleID) || ids.contains(bundleID)
    }

    static func canChange(_ bundleID: String) -> Bool {
        !bundleID.isEmpty && !locked.contains(bundleID) && !bundleID.hasPrefix("pid:")
    }

    static func pin(_ bundleID: String) {
        guard canChange(bundleID), !ids.contains(bundleID) else { return }
        ids = ids + [bundleID]
    }

    static func unpin(_ bundleID: String) {
        guard canChange(bundleID) else { return }
        ids = ids.filter { $0 != bundleID }
    }

    static func stub(bundleID: String) -> AppGroup? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
        return AppGroup(
            key: bundleID,
            name: displayName(url: url, bundleID: bundleID),
            icon: NSWorkspace.shared.icon(forFile: url.path),
            pid: app?.processIdentifier ?? 0,
            bundleID: bundleID,
            bundleURL: url,
            windows: []
        )
    }

    static func finder(windows: [WindowEntry]) -> AppGroup {
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: finderID)
            ?? URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")
        let app = NSRunningApplication.runningApplications(withBundleIdentifier: finderID).first
        return AppGroup(
            key: finderID,
            name: "Finder",
            icon: NSWorkspace.shared.icon(forFile: url.path),
            pid: app?.processIdentifier ?? windows.first?.pid ?? 0,
            bundleID: finderID,
            bundleURL: url,
            windows: windows
        )
    }

    static func apps() -> AppGroup {
        AppGroup(
            key: appsID,
            name: "Apps",
            icon: NSWorkspace.shared.icon(forFile: "/System/Applications/Launchpad.app"),
            pid: 0,
            bundleID: appsID,
            bundleURL: nil,
            windows: []
        )
    }

    private static let locked: Set<String> = [finderID, appsID]

    private static func displayName(url: URL, bundleID: String) -> String {
        if let name = Bundle(url: url)?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String, !name.isEmpty {
            return name
        }
        if let name = Bundle(url: url)?.object(forInfoDictionaryKey: "CFBundleName") as? String, !name.isEmpty {
            return name
        }
        return url.deletingPathExtension().lastPathComponent
    }
}
