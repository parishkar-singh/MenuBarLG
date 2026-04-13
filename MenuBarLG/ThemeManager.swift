import AppKit

extension Notification.Name {
    static let menuBarThemeChanged = Notification.Name("MenuBarThemeChanged")
    static let menuBarToggleChanged = Notification.Name("MenuBarToggleChanged")
}

@MainActor
final class ThemeManager: NSObject {
    enum ThemeMode: Int, CaseIterable {
        case automatic
        case light
        case dark

        var title: String {
            switch self {
            case .automatic:
                return "Automatic"
            case .light:
                return "Light"
            case .dark:
                return "Dark"
            }
        }
    }

    static let themeModeUserDefaultsKey = "menuBarThemeMode"

    private let userDefaults: UserDefaults
    // KVO + notification tokens are kept strongly so they can be explicitly torn down in deinit.
    private var appearanceObservation: NSKeyValueObservation?
    private var distributedObserver: NSObjectProtocol?
    private var accessibilityObserver: NSObjectProtocol?

    private(set) var themeMode: ThemeMode
    private(set) var systemIsDark: Bool
    private(set) var isDark: Bool
    private(set) var reduceTransparency: Bool

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults

        let application = NSApplication.shared
        let storedThemeMode = ThemeMode(rawValue: userDefaults.integer(forKey: Self.themeModeUserDefaultsKey)) ?? .automatic
        let currentSystemIsDark = Self.isDarkAppearance(application.effectiveAppearance)

        themeMode = storedThemeMode
        systemIsDark = currentSystemIsDark
        isDark = Self.resolveIsDark(systemIsDark: currentSystemIsDark, themeMode: storedThemeMode)
        reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency

        super.init()

        // Observe all three upstream signals requested by product requirements. Any one of them can
        // drive the effective overlay state.
        appearanceObservation = application.observe(\.effectiveAppearance, options: [.initial, .new]) { [weak self] observedApplication, _ in
            Task { @MainActor [weak self] in
                self?.handleAppearanceChange(for: observedApplication.effectiveAppearance)
            }
        }

        distributedObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshState()
            }
        }

        accessibilityObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshState()
            }
        }
    }

    deinit {
        if let distributedObserver {
            DistributedNotificationCenter.default().removeObserver(distributedObserver)
        }

        if let accessibilityObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(accessibilityObserver)
        }
    }

    var effectiveAppearanceName: NSAppearance.Name {
        isDark ? .darkAqua : .aqua
    }

    var usesSystemTheme: Bool {
        themeMode == .automatic
    }

    var settingsWindowAppearance: NSAppearance? {
        switch themeMode {
        case .automatic:
            return nil
        case .light:
            return NSAppearance(named: .aqua)
        case .dark:
            return NSAppearance(named: .darkAqua)
        }
    }

    func setThemeMode(_ themeMode: ThemeMode) {
        guard self.themeMode != themeMode else {
            return
        }

        self.themeMode = themeMode
        userDefaults.set(themeMode.rawValue, forKey: Self.themeModeUserDefaultsKey)
        updateState(
            systemIsDark: systemIsDark,
            reduceTransparency: NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency,
            forceNotify: true
        )
    }

    private func handleAppearanceChange(for appearance: NSAppearance) {
        let nextSystemIsDark = Self.isDarkAppearance(appearance)
        updateState(
            systemIsDark: nextSystemIsDark,
            reduceTransparency: NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        )
    }

    private func refreshState() {
        let application = NSApplication.shared
        let nextSystemIsDark = Self.isDarkAppearance(application.effectiveAppearance)
        let nextReduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        updateState(systemIsDark: nextSystemIsDark, reduceTransparency: nextReduceTransparency)
    }

    private func updateState(systemIsDark nextSystemIsDark: Bool, reduceTransparency nextReduceTransparency: Bool, forceNotify: Bool = false) {
        let nextIsDark = Self.resolveIsDark(systemIsDark: nextSystemIsDark, themeMode: themeMode)
        let didChange =
            forceNotify ||
            systemIsDark != nextSystemIsDark ||
            isDark != nextIsDark ||
            reduceTransparency != nextReduceTransparency

        systemIsDark = nextSystemIsDark
        isDark = nextIsDark
        reduceTransparency = nextReduceTransparency

        guard didChange else {
            return
        }

        // A single notification fan-outs to all consumers (overlay windows + settings UI).
        NotificationCenter.default.post(
            name: .menuBarThemeChanged,
            object: self,
            userInfo: [
                "isDark": nextIsDark,
                "themeMode": themeMode.rawValue,
                "reduceTransparency": nextReduceTransparency
            ]
        )
    }

    private static func resolveIsDark(systemIsDark: Bool, themeMode: ThemeMode) -> Bool {
        switch themeMode {
        case .automatic:
            return systemIsDark
        case .light:
            return false
        case .dark:
            return true
        }
    }

    private static func isDarkAppearance(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}
