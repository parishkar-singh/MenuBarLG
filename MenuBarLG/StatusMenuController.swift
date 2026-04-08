import AppKit
import Carbon.HIToolbox

@MainActor
final class StatusMenuController: NSObject, NSMenuDelegate {
    private let toggleManager: ToggleManager
    private let statusItemVisibilityManager: StatusItemVisibilityManager
    private var recoveryHotKeyMonitor: StatusIconRecoveryHotKeyMonitor?
    // AppDelegate injects this closure to avoid hard-coupling the menu controller to settings UI.
    var openSettingsHandler: (() -> Void)?

    private let statusItem: NSStatusItem
    private let menu: NSMenu
    private let settingsItem: NSMenuItem
    private let revealTemporarilyItem: NSMenuItem
    private let actionsSpacerItem: NSMenuItem
    private let toggleItem: NSMenuItem
    private let quitItem: NSMenuItem

    private var toggleObserver: NSObjectProtocol?
    private var statusItemVisibilityObserver: NSObjectProtocol?
    private var startupHideWorkItem: DispatchWorkItem?
    private var temporaryRevealHideWorkItem: DispatchWorkItem?
    private var isSettingsWindowVisible = false

    private static let startupRevealDuration: TimeInterval = 5
    private static let recoveryRevealDuration: TimeInterval = 25

    init(toggleManager: ToggleManager, statusItemVisibilityManager: StatusItemVisibilityManager) {
        self.toggleManager = toggleManager
        self.statusItemVisibilityManager = statusItemVisibilityManager
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        menu = NSMenu()
        settingsItem = NSMenuItem(title: "Open Settings…", action: #selector(openSettings), keyEquivalent: "")
        revealTemporarilyItem = NSMenuItem(title: "Show Menu Icon for 25 Seconds", action: #selector(revealTemporarily), keyEquivalent: "m")
        actionsSpacerItem = Self.makeSpacerItem(height: 5)
        toggleItem = NSMenuItem(title: "Enable Menu Bar Glass", action: #selector(toggleBlur), keyEquivalent: "")
        quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")

        super.init()

        // Keep tight horizontal spacing; we render the blur toggle checkmark inline in the title.
        menu.showsStateColumn = false
        menu.delegate = self
        settingsItem.target = self
        settingsItem.keyEquivalentModifierMask = []
        settingsItem.image = nil
        revealTemporarilyItem.target = self
        revealTemporarilyItem.keyEquivalentModifierMask = [.control, .option, .command]
        toggleItem.target = self
        toggleItem.keyEquivalentModifierMask = []
        quitItem.target = self

        menu.addItem(settingsItem)
        menu.addItem(revealTemporarilyItem)
        menu.addItem(actionsSpacerItem)
        menu.addItem(toggleItem)
        menu.addItem(.separator())
        menu.addItem(quitItem)

        if let button = statusItem.button {
            // Keep template rendering so the icon automatically adapts to light/dark menu bar text.
            let image = NSImage(systemSymbolName: "menubar.rectangle", accessibilityDescription: "Menu Bar Glass")
            image?.isTemplate = true
            button.image = image
        }

        statusItem.menu = menu
        toggleObserver = NotificationCenter.default.addObserver(
            forName: .menuBarToggleChanged,
            object: toggleManager,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshToggleItem()
            }
        }

        statusItemVisibilityObserver = NotificationCenter.default.addObserver(
            forName: .menuBarStatusItemVisibilityChanged,
            object: statusItemVisibilityManager,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.applyStatusItemVisibility(isInitialLaunch: false)
                self?.refreshRevealMenuItem()
            }
        }

        recoveryHotKeyMonitor = StatusIconRecoveryHotKeyMonitor { [weak self] in
            Task { @MainActor [weak self] in
                self?.handleRecoveryShortcut()
            }
        }

        refreshToggleItem()
        refreshRevealMenuItem()
        applyStatusItemVisibility(isInitialLaunch: true)
    }

    deinit {
        if let toggleObserver {
            NotificationCenter.default.removeObserver(toggleObserver)
        }

        if let statusItemVisibilityObserver {
            NotificationCenter.default.removeObserver(statusItemVisibilityObserver)
        }

        startupHideWorkItem?.cancel()
        temporaryRevealHideWorkItem?.cancel()
    }

    func menuWillOpen(_ menu: NSMenu) {
        // Defensive refresh in case state changed while the menu was closed.
        enforceTextOnlyMenu()
        refreshToggleItem()
        refreshRevealMenuItem()
    }

    func setSettingsWindowVisible(_ isVisible: Bool) {
        guard isSettingsWindowVisible != isVisible else {
            return
        }

        isSettingsWindowVisible = isVisible
        applyStatusItemVisibility(isInitialLaunch: false)
    }

    @objc private func toggleBlur() {
        toggleManager.toggle()
    }

    @objc private func openSettings() {
        openSettingsHandler?()
    }

    @objc private func revealTemporarily() {
        temporarilyRevealStatusItem(duration: Self.recoveryRevealDuration)
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func refreshToggleItem() {
        toggleItem.title = toggleManager.isEnabled ? "✓ Enable Menu Bar Glass" : "Enable Menu Bar Glass"
    }

    private func refreshRevealMenuItem() {
        // Recovery action is only meaningful when startup-only mode can hide the icon.
        let shouldHideRevealItem = statusItemVisibilityManager.visibilityMode == .alwaysVisible
        revealTemporarilyItem.isHidden = shouldHideRevealItem
        actionsSpacerItem.isHidden = shouldHideRevealItem
        revealTemporarilyItem.toolTip = "Recovery shortcut: \(StatusIconRecoveryHotKeyMonitor.shortcutDisplayString)"
    }

    private func applyStatusItemVisibility(isInitialLaunch: Bool) {
        switch statusItemVisibilityManager.visibilityMode {
        case .alwaysVisible:
            startupHideWorkItem?.cancel()
            startupHideWorkItem = nil
            statusItem.isVisible = true
        case .startupOnly:
            if isInitialLaunch {
                statusItem.isVisible = true
                scheduleStartupHide()
                return
            }

            statusItem.isVisible = shouldForceVisibilityInStartupOnlyMode
        }
    }

    private var shouldForceVisibilityInStartupOnlyMode: Bool {
        isSettingsWindowVisible || temporaryRevealHideWorkItem != nil || startupHideWorkItem != nil
    }

    private func scheduleStartupHide() {
        startupHideWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else {
                return
            }

            self.startupHideWorkItem = nil
            self.applyStatusItemVisibility(isInitialLaunch: false)
        }

        startupHideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.startupRevealDuration, execute: workItem)
    }

    private func temporarilyRevealStatusItem(duration: TimeInterval) {
        temporaryRevealHideWorkItem?.cancel()
        statusItem.isVisible = true

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else {
                return
            }

            self.temporaryRevealHideWorkItem = nil
            self.applyStatusItemVisibility(isInitialLaunch: false)
        }

        temporaryRevealHideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: workItem)
    }

    private func handleRecoveryShortcut() {
        guard statusItemVisibilityManager.visibilityMode == .startupOnly else {
            return
        }

        temporarilyRevealStatusItem(duration: Self.recoveryRevealDuration)
        statusItem.button?.performClick(nil)
    }

    private func enforceTextOnlyMenu() {
        settingsItem.image = nil
        revealTemporarilyItem.image = nil
        toggleItem.image = nil
        quitItem.image = nil
    }
}

private extension StatusMenuController {
    static func makeSpacerItem(height: CGFloat) -> NSMenuItem {
        let item = NSMenuItem()
        item.isEnabled = false
        item.view = NSView(frame: NSRect(x: 0, y: 0, width: 1, height: height))
        return item
    }
}

private final class StatusIconRecoveryHotKeyMonitor {
    private var eventHandlerRef: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?
    private let hotKeyID = EventHotKeyID(signature: 0x4D424C47, id: 1) // "MBLG"
    private let handler: () -> Void

    static let shortcutDisplayString = "⌃⌥⌘M"

    init(handler: @escaping () -> Void) {
        self.handler = handler
        register()
    }

    deinit {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }

    private func register() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let monitorPointer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, eventRef, userData in
                guard let userData, let eventRef else {
                    return noErr
                }

                let monitor = Unmanaged<StatusIconRecoveryHotKeyMonitor>.fromOpaque(userData).takeUnretainedValue()
                var pressedHotKeyID = EventHotKeyID()
                let parameterStatus = GetEventParameter(
                    eventRef,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &pressedHotKeyID
                )

                guard parameterStatus == noErr else {
                    return noErr
                }

                if pressedHotKeyID.signature == monitor.hotKeyID.signature && pressedHotKeyID.id == monitor.hotKeyID.id {
                    monitor.handler()
                }

                return noErr
            },
            1,
            &eventType,
            monitorPointer,
            &eventHandlerRef
        )

        guard installStatus == noErr else {
            NSLog("MenuBarLG: Failed to install recovery hotkey handler (%d)", installStatus)
            eventHandlerRef = nil
            return
        }

        let modifiers = UInt32(controlKey | optionKey | cmdKey)
        var registeredHotKeyRef: EventHotKeyRef?
        let registrationStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_M),
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &registeredHotKeyRef
        )

        if registrationStatus == noErr, let registeredHotKeyRef {
            hotKeyRef = registeredHotKeyRef
        } else {
            NSLog("MenuBarLG: Failed to register recovery hotkey (%d)", registrationStatus)
            hotKeyRef = nil
        }
    }
}
