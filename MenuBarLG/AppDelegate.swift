//
//  AppDelegate.swift
//  MenuBarLG
//
//  Created by Parishkar Singh on 08/04/26.
//

import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    // These objects form the app's long-lived graph. Keeping strong references here guarantees
    // observers/timers stay alive for the whole process lifetime.
    private var themeManager: ThemeManager?
    private var blurStyleManager: BlurStyleManager?
    private var glassTuningManager: GlassTuningManager?
    private var toggleManager: ToggleManager?
    private var statusItemVisibilityManager: StatusItemVisibilityManager?
    private var launchAtLoginManager: LaunchAtLoginManager?
    private var displayManager: DisplayManager?
    private var statusMenuController: StatusMenuController?
    private var settingsWindowController: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Accessory policy keeps the app in the menu bar only (no Dock icon, no app windows by default).
        NSApplication.shared.setActivationPolicy(.accessory)

        let themeManager = ThemeManager()
        let blurStyleManager = BlurStyleManager()
        let glassTuningManager = GlassTuningManager()
        let toggleManager = ToggleManager()
        let statusItemVisibilityManager = StatusItemVisibilityManager()
        let launchAtLoginManager = LaunchAtLoginManager()
        let displayManager = DisplayManager(
            themeManager: themeManager,
            blurStyleManager: blurStyleManager,
            glassTuningManager: glassTuningManager,
            toggleManager: toggleManager
        )
        let statusMenuController = StatusMenuController(
            toggleManager: toggleManager,
            statusItemVisibilityManager: statusItemVisibilityManager
        )
        let settingsWindowController = SettingsWindowController(
            toggleManager: toggleManager,
            themeManager: themeManager,
            blurStyleManager: blurStyleManager,
            glassTuningManager: glassTuningManager,
            launchAtLoginManager: launchAtLoginManager,
            statusItemVisibilityManager: statusItemVisibilityManager
        )

        self.themeManager = themeManager
        self.blurStyleManager = blurStyleManager
        self.glassTuningManager = glassTuningManager
        self.toggleManager = toggleManager
        self.statusItemVisibilityManager = statusItemVisibilityManager
        self.launchAtLoginManager = launchAtLoginManager
        self.displayManager = displayManager
        self.statusMenuController = statusMenuController
        self.settingsWindowController = settingsWindowController

        // Break potential cycles between menu controller and settings controller.
        statusMenuController.openSettingsHandler = { [weak settingsWindowController] in
            settingsWindowController?.show()
        }

        settingsWindowController.settingsVisibilityChangedHandler = { [weak statusMenuController] isVisible in
            statusMenuController?.setSettingsWindowVisible(isVisible)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        glassTuningManager?.flushPendingPersistence()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // When the user re-activates the app from Dock/Finder, treat it as "open Configure".
        settingsWindowController?.show()
        return true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}
