import AppKit

extension Notification.Name {
    static let menuBarStatusItemVisibilityChanged = Notification.Name("MenuBarStatusItemVisibilityChanged")
}

@MainActor
final class ToggleManager {
    static let userDefaultsKey = "isBlurEnabled"

    private let userDefaults: UserDefaults

    private(set) var isEnabled: Bool

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults

        // First launch default is enabled to match product expectations.
        if userDefaults.object(forKey: Self.userDefaultsKey) == nil {
            userDefaults.set(true, forKey: Self.userDefaultsKey)
        }

        isEnabled = userDefaults.bool(forKey: Self.userDefaultsKey)
    }

    func toggle() {
        setEnabled(!isEnabled)
    }

    func setEnabled(_ enabled: Bool) {
        guard isEnabled != enabled else {
            return
        }

        isEnabled = enabled
        userDefaults.set(enabled, forKey: Self.userDefaultsKey)
        // Broadcast once so display/menu/settings all stay in sync.
        NotificationCenter.default.post(name: .menuBarToggleChanged, object: self)
    }
}

@MainActor
final class StatusItemVisibilityManager {
    enum VisibilityMode: Int, CaseIterable {
        case alwaysVisible
        case startupOnly

        var title: String {
            switch self {
            case .alwaysVisible:
                return "Always Visible"
            case .startupOnly:
                return "Show 5s On Startup"
            }
        }
    }

    static let userDefaultsKey = "menuBarStatusItemVisibilityMode"

    private let userDefaults: UserDefaults

    private(set) var visibilityMode: VisibilityMode

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        if let storedMode = VisibilityMode(rawValue: userDefaults.integer(forKey: Self.userDefaultsKey)) {
            visibilityMode = storedMode
        } else {
            visibilityMode = .alwaysVisible
            userDefaults.set(VisibilityMode.alwaysVisible.rawValue, forKey: Self.userDefaultsKey)
        }
    }

    var statusMessage: String {
        switch visibilityMode {
        case .alwaysVisible:
            return "Menu bar icon stays visible."
        case .startupOnly:
            return "Menu bar icon is shown for 5 seconds on launch, then hidden. Recovery shortcut: Control + Option + Command + M."
        }
    }

    func setVisibilityMode(_ mode: VisibilityMode) {
        guard visibilityMode != mode else {
            return
        }

        visibilityMode = mode
        userDefaults.set(mode.rawValue, forKey: Self.userDefaultsKey)
        NotificationCenter.default.post(name: .menuBarStatusItemVisibilityChanged, object: self)
    }
}
