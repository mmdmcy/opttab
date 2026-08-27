import Foundation

/// Runtime switches for the independent OptTab components.
///
/// The switcher is the only implemented component in the current binary.
/// Taskbar and window-manager settings are reserved separately so neither can
/// accidentally become part of the switcher's lifecycle.
enum FeatureSettings {
    private static let switcherKey = "opttab.feature.switcher"
    private static let taskbarKey = "opttab.feature.taskbar"
    private static let windowManagerKey = "opttab.feature.windowManager"

    static var switcherEnabled: Bool {
        get { value(forKey: switcherKey, default: true) }
        set { UserDefaults.standard.set(newValue, forKey: switcherKey) }
    }

    // These remain off until their independent implementations are shipped.
    static var taskbarEnabled: Bool {
        get { value(forKey: taskbarKey, default: false) }
        set { UserDefaults.standard.set(newValue, forKey: taskbarKey) }
    }

    static var windowManagerEnabled: Bool {
        get { value(forKey: windowManagerKey, default: false) }
        set { UserDefaults.standard.set(newValue, forKey: windowManagerKey) }
    }

    private static func value(forKey key: String, default fallback: Bool) -> Bool {
        guard UserDefaults.standard.object(forKey: key) != nil else { return fallback }
        return UserDefaults.standard.bool(forKey: key)
    }
}
