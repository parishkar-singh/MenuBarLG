import AppKit

@MainActor
final class MenuBarOverlayWindow: NSWindow {
    private let glassViewController = GlassViewController()

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
        false
    }

    override var canBecomeMain: Bool {
        false
    }

    func updateFrame(for screen: NSScreen) {
        setFrame(Self.frame(for: screen), display: false)
    }

    func updateAppearance(
        isDark: Bool,
        reduceTransparency: Bool,
        materialPreset: BlurStyleManager.MaterialPreset,
        presetTuning: GlassTuningManager.PresetTuning
    ) {
        glassViewController.updateAppearance(
            isDark: isDark,
            reduceTransparency: reduceTransparency,
            materialPreset: materialPreset,
            presetTuning: presetTuning
        )
    }

    func show() {
        orderFrontRegardless()
    }

    func hide() {
        orderOut(nil)
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
