import AppKit

@MainActor
final class DisplayManager {
    private let themeManager: ThemeManager
    private let blurStyleManager: BlurStyleManager
    private let glassTuningManager: GlassTuningManager
    private let toggleManager: ToggleManager

    private var screenObserver: NSObjectProtocol?
    private var themeObserver: NSObjectProtocol?
    private var blurStyleObserver: NSObjectProtocol?
    private var glassTuningObserver: NSObjectProtocol?
    private var toggleObserver: NSObjectProtocol?

    // Window lifetime is owned here. Keys are current NSScreen instances for the latest topology.
    private(set) var overlayWindows: [NSScreen: MenuBarOverlayWindow] = [:]

    init(
        themeManager: ThemeManager,
        blurStyleManager: BlurStyleManager,
        glassTuningManager: GlassTuningManager,
        toggleManager: ToggleManager
    ) {
        self.themeManager = themeManager
        self.blurStyleManager = blurStyleManager
        self.glassTuningManager = glassTuningManager
        self.toggleManager = toggleManager

        // Bootstrap immediately so the effect appears on launch before any notifications fire.
        syncWindows(with: NSScreen.screens)

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.syncWindows(with: NSScreen.screens)
            }
        }

        themeObserver = NotificationCenter.default.addObserver(
            forName: .menuBarThemeChanged,
            object: themeManager,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateAppearance()
            }
        }

        blurStyleObserver = NotificationCenter.default.addObserver(
            forName: .menuBarBlurStyleChanged,
            object: blurStyleManager,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateAppearance()
            }
        }

        glassTuningObserver = NotificationCenter.default.addObserver(
            forName: .menuBarGlassTuningChanged,
            object: glassTuningManager,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateAppearance()
            }
        }

        toggleObserver = NotificationCenter.default.addObserver(
            forName: .menuBarToggleChanged,
            object: toggleManager,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateVisibility()
            }
        }
    }

    deinit {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }

        if let themeObserver {
            NotificationCenter.default.removeObserver(themeObserver)
        }

        if let blurStyleObserver {
            NotificationCenter.default.removeObserver(blurStyleObserver)
        }

        if let glassTuningObserver {
            NotificationCenter.default.removeObserver(glassTuningObserver)
        }

        if let toggleObserver {
            NotificationCenter.default.removeObserver(toggleObserver)
        }
    }

    func updateAppearance() {
        // Tuning is resolved once per refresh to avoid repeated dictionary/file reads per window.
        let selectedPreset = blurStyleManager.materialPreset
        let presetTuning = glassTuningManager.tuning(for: selectedPreset)

        for window in overlayWindows.values {
            window.updateAppearance(
                isDark: themeManager.isDark,
                reduceTransparency: themeManager.reduceTransparency,
                materialPreset: selectedPreset,
                presetTuning: presetTuning
            )
        }
    }

    func updateVisibility() {
        for window in overlayWindows.values {
            if toggleManager.isEnabled {
                window.show()
            } else {
                window.hide()
            }
        }
    }

    private func syncWindows(with screens: [NSScreen]) {
        // Diff by stable display ID instead of object identity so resolution changes update in place
        // and we only create/close windows when displays are actually added/removed.
        var existingByDisplayID: [CGDirectDisplayID: (screen: NSScreen, window: MenuBarOverlayWindow)] = [:]

        for (screen, window) in overlayWindows {
            if let displayID = Self.displayID(for: screen) {
                existingByDisplayID[displayID] = (screen, window)
            } else {
                // Defensive close for screens that no longer expose an ID.
                window.close()
            }
        }

        var nextOverlayWindows: [NSScreen: MenuBarOverlayWindow] = [:]

        for screen in screens {
            guard let displayID = Self.displayID(for: screen) else {
                continue
            }

            if let existing = existingByDisplayID.removeValue(forKey: displayID) {
                let window = existing.window
                window.updateFrame(for: screen)
                nextOverlayWindows[screen] = window
            } else {
                let window = MenuBarOverlayWindow(screen: screen)
                nextOverlayWindows[screen] = window
            }
        }

        for removed in existingByDisplayID.values {
            removed.window.close()
        }

        overlayWindows = nextOverlayWindows
        updateAppearance()
        updateVisibility()
    }

    private static func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        guard let number = screen.deviceDescription[key] as? NSNumber else {
            return nil
        }

        return CGDirectDisplayID(number.uint32Value)
    }
}
