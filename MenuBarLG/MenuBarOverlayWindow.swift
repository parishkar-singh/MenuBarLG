import AppKit

@MainActor
final class MenuBarOverlayWindow: NSWindow {
    private let glassViewController = GlassViewController()
    private var activationRefreshWorkItem: DispatchWorkItem?
    var isActivationAnchor = false
    private var forcedActiveAppearanceEnabled = true

    init(screen: NSScreen) {
        super.init(contentRect: Self.frame(for: screen), styleMask: .borderless, backing: .buffered, defer: false)

        // Transparent non-interactive overlay window that never steals focus from front apps.
        isOpaque = false
        backgroundColor = .clear
        ignoresMouseEvents = true
        hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        // mainMenuWindow level places the effect directly under the rendered menu extras.
        level = Self.overlayLevel()

        contentViewController = glassViewController
        setFrame(Self.frame(for: screen), display: false)
    }

    override var canBecomeKey: Bool {
        forcedActiveAppearanceEnabled
    }

    override var canBecomeMain: Bool {
        forcedActiveAppearanceEnabled
    }

    func updateFrame(for screen: NSScreen) {
        setFrame(Self.frame(for: screen), display: false)
    }

    func updateActivationAnchor(isAnchor: Bool) {
        isActivationAnchor = isAnchor

        guard isVisible else {
            return
        }

        refreshForcedActiveAppearance()
    }

    func setForcedActiveAppearanceEnabled(_ enabled: Bool) {
        forcedActiveAppearanceEnabled = enabled

        if !enabled {
            activationRefreshWorkItem?.cancel()
            if let replacementWindow = NSApplication.shared.windows.first(where: { window in
                window !== self && window.isVisible && !(window is MenuBarOverlayWindow)
            }) {
                replacementWindow.makeKeyAndOrderFront(nil)
            }
        } else if isVisible {
            refreshForcedActiveAppearance()
        }
    }

    func updateAppearance(
        isDark: Bool,
        reduceTransparency: Bool,
        blurConfiguration: BlurStyleManager.Configuration,
        tintWhiteAlpha: Double,
        customCornersEnabled: Bool,
        cornerRadii: GlassTuningManager.CornerRadii
    ) {
        glassViewController.updateAppearance(
            isDark: isDark,
            reduceTransparency: reduceTransparency,
            blurConfiguration: blurConfiguration,
            tintWhiteAlpha: tintWhiteAlpha,
            customCornersEnabled: customCornersEnabled,
            cornerRadii: cornerRadii
        )
    }

    func show() {
        orderFrontRegardless()
        refreshForcedActiveAppearance()
    }

    func hide() {
        activationRefreshWorkItem?.cancel()
        orderOut(nil)
    }

    override func becomeKey() {
        super.becomeKey()
        activationRefreshWorkItem?.cancel()
    }

    @objc(_hasActiveAppearance)
    func codex_hasActiveAppearance() -> Bool {
        forcedActiveAppearanceEnabled
    }

    @objc(_hasActiveAppearanceIgnoringKeyFocus)
    func codex_hasActiveAppearanceIgnoringKeyFocus() -> Bool {
        forcedActiveAppearanceEnabled
    }

    @objc(_hasActiveControls)
    func codex_hasActiveControls() -> Bool {
        forcedActiveAppearanceEnabled
    }

    @objc(_hasKeyAppearance)
    func codex_hasKeyAppearance() -> Bool {
        forcedActiveAppearanceEnabled
    }

    @objc(_hasMainAppearance)
    func codex_hasMainAppearance() -> Bool {
        forcedActiveAppearanceEnabled
    }

    private func refreshForcedActiveAppearance() {
        guard forcedActiveAppearanceEnabled else {
            return
        }

        guard isActivationAnchor, isVisible else {
            return
        }

        guard shouldReclaimKeyAppearance else {
            return
        }

        activationRefreshWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.isActivationAnchor, self.isVisible else {
                return
            }

            NSApplication.shared.activate(ignoringOtherApps: true)
            self.makeKeyAndOrderFront(nil)
        }

        activationRefreshWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: workItem)
    }

    private var shouldReclaimKeyAppearance: Bool {
        if isKeyWindow {
            return false
        }

        if let keyWindow = NSApplication.shared.keyWindow, !(keyWindow is MenuBarOverlayWindow) {
            return false
        }

        // Do not steal focus from the app's actual interactive windows like Settings.
        let hasOtherVisibleAppWindow = NSApplication.shared.windows.contains { window in
            window !== self && window.isVisible && !(window is MenuBarOverlayWindow)
        }

        return !hasOtherVisibleAppWindow
    }

    private static func frame(for screen: NSScreen) -> NSRect {
        // Height follows safe-area/notch geometry when available and falls back to status-bar thickness.
        let height = overlayHeight(for: screen)
        return NSRect(
            x: screen.frame.origin.x,
            y: screen.frame.maxY - height,
            width: screen.frame.width,
            height: height
        )
    }

    private static func overlayHeight(for screen: NSScreen) -> CGFloat {
        // Most accurate across notched + non-notched displays:
        // the top delta between full frame and visible frame equals the menu bar inset for that screen.
        let visibleTopInset = max(0, screen.frame.maxY - screen.visibleFrame.maxY)

        // Additional geometry sources retained as fallbacks for edge cases.
        let safeAreaHeight = screen.safeAreaInsets.top
        let auxiliaryLeftHeight = screen.auxiliaryTopLeftArea?.height ?? 0
        let auxiliaryRightHeight = screen.auxiliaryTopRightArea?.height ?? 0
        return max(visibleTopInset, NSStatusBar.system.thickness, safeAreaHeight, auxiliaryLeftHeight, auxiliaryRightHeight)
    }

    private static func overlayLevel() -> NSWindow.Level {
        NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)))
    }
}
