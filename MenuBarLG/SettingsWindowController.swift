import AppKit
import ServiceManagement

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private enum SettingsTab: Int, CaseIterable {
        case general
        case appearance
        case corners
        case credits

        var title: String {
            switch self {
            case .general:
                return "General"
            case .appearance:
                return "Appearance"
            case .corners:
                return "Corners"
            case .credits:
                return "Credits"
            }
        }
    }

    private let toggleManager: ToggleManager
    private let themeManager: ThemeManager
    private let blurStyleManager: BlurStyleManager
    private let glassTuningManager: GlassTuningManager
    private let launchAtLoginManager: LaunchAtLoginManager
    private let statusItemVisibilityManager: StatusItemVisibilityManager

    var settingsVisibilityChangedHandler: ((Bool) -> Void)?

    private let subtitleLabel = NSTextField(labelWithString: "Liquid Glass menu bar overlay (macOS 26+)")
    private let tabSelector = NSSegmentedControl(
        labels: SettingsTab.allCases.map(\.title),
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    private let pageHostView = NSView(frame: .zero)

    private let generalPage = GeneralSettingsPageView()
    private let appearancePage = AppearanceSettingsPageView()
    private let cornerRadiusPage = CornerRadiusSettingsPageView()
    private let creditsPage = CreditsSettingsPageView()
    private var tabViews: [SettingsTab: NSView] = [:]

    private var observers: [NSObjectProtocol] = []
    private var isRefreshingAppearancePage = false
    private var isRefreshingCornerPage = false

    private static let statusIconRecoveryShortcut = "⌃⌥⌘M"

    init(
        toggleManager: ToggleManager,
        themeManager: ThemeManager,
        blurStyleManager: BlurStyleManager,
        glassTuningManager: GlassTuningManager,
        launchAtLoginManager: LaunchAtLoginManager,
        statusItemVisibilityManager: StatusItemVisibilityManager
    ) {
        self.toggleManager = toggleManager
        self.themeManager = themeManager
        self.blurStyleManager = blurStyleManager
        self.glassTuningManager = glassTuningManager
        self.launchAtLoginManager = launchAtLoginManager
        self.statusItemVisibilityManager = statusItemVisibilityManager

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.center()
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 620, height: 560)

        super.init(window: window)

        window.delegate = self
        configureContentView(in: window)
        configureControlOptions()
        bindActions()
        installObservers()
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func show() {
        settingsVisibilityChangedHandler?(true)
        applyWindowTheme()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        settingsVisibilityChangedHandler?(false)
    }

    private func configureContentView(in window: NSWindow) {
        let contentView = NSView(frame: window.contentRect(forFrameRect: window.frame))
        contentView.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: "MenuBarLG")
        titleLabel.font = .systemFont(ofSize: 24, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        subtitleLabel.font = .systemFont(ofSize: 13, weight: .regular)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        tabSelector.translatesAutoresizingMaskIntoConstraints = false
        tabSelector.segmentStyle = .rounded
        tabSelector.selectedSegment = SettingsTab.general.rawValue

        pageHostView.translatesAutoresizingMaskIntoConstraints = false
        pageHostView.wantsLayer = false

        contentView.addSubview(titleLabel)
        contentView.addSubview(subtitleLabel)
        contentView.addSubview(tabSelector)
        contentView.addSubview(pageHostView)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 22),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -24),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            subtitleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            subtitleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),

            tabSelector.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 16),
            tabSelector.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),

            pageHostView.topAnchor.constraint(equalTo: tabSelector.bottomAnchor, constant: 14),
            pageHostView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            pageHostView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            pageHostView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -24)
        ])

        tabViews = [
            .general: generalPage,
            .appearance: appearancePage,
            .corners: cornerRadiusPage,
            .credits: creditsPage
        ]

        for tab in SettingsTab.allCases {
            if let page = tabViews[tab] {
                embed(page: page, in: pageHostView)
            }
        }

        applySelectedTab(.general)
        window.contentView = contentView
    }

    private func embed(page: NSView, in hostView: NSView) {
        page.translatesAutoresizingMaskIntoConstraints = false
        hostView.addSubview(page)
        NSLayoutConstraint.activate([
            page.topAnchor.constraint(equalTo: hostView.topAnchor),
            page.leadingAnchor.constraint(equalTo: hostView.leadingAnchor),
            page.trailingAnchor.constraint(equalTo: hostView.trailingAnchor),
            page.bottomAnchor.constraint(equalTo: hostView.bottomAnchor)
        ])
    }

    private func configureControlOptions() {
        appearancePage.appearancePopupButton.removeAllItems()
        appearancePage.appearancePopupButton.addItems(withTitles: ThemeManager.ThemeMode.allCases.map(\.title))

        appearancePage.blurModePopupButton.removeAllItems()
        appearancePage.blurModePopupButton.addItems(withTitles: BlurStyleManager.BlurMode.allCases.map(\.title))

        appearancePage.variantPopupButton.removeAllItems()
        appearancePage.variantPopupButton.addItems(withTitles: BlurStyleManager.PrivateGlassVariant.allCases.map(\.title))

        appearancePage.stylePopupButton.removeAllItems()
        appearancePage.stylePopupButton.addItems(withTitles: BlurStyleManager.GlassStyle.allCases.map(\.title))

        appearancePage.backdropMaterialPopupButton.removeAllItems()
        appearancePage.backdropMaterialPopupButton.addItems(withTitles: BlurStyleManager.BackdropMaterial.allCases.map(\.title))

        appearancePage.backdropBlendModePopupButton.removeAllItems()
        appearancePage.backdropBlendModePopupButton.addItems(withTitles: BlurStyleManager.BackdropBlendMode.allCases.map(\.title))

        generalPage.menuBarIconPopupButton.removeAllItems()
        generalPage.menuBarIconPopupButton.addItems(withTitles: StatusItemVisibilityManager.VisibilityMode.allCases.map(\.title))

        generalPage.recoveryHintLabel.stringValue =
            "Recovery: when icon mode is \"Show 5s On Startup\", press \(Self.statusIconRecoveryShortcut) to restore the icon for 25 seconds."
    }

    private func bindActions() {
        tabSelector.target = self
        tabSelector.action = #selector(changeSelectedTab)

        generalPage.toggleButton.target = self
        generalPage.toggleButton.action = #selector(toggleBlur)

        generalPage.launchAtLoginButton.target = self
        generalPage.launchAtLoginButton.action = #selector(toggleLaunchAtLogin)

        generalPage.menuBarIconPopupButton.target = self
        generalPage.menuBarIconPopupButton.action = #selector(changeMenuBarIconVisibilityMode)

        appearancePage.appearancePopupButton.target = self
        appearancePage.appearancePopupButton.action = #selector(changeThemeMode)

        appearancePage.blurModePopupButton.target = self
        appearancePage.blurModePopupButton.action = #selector(changeBlurMode)

        appearancePage.variantPopupButton.target = self
        appearancePage.variantPopupButton.action = #selector(changeVariant)

        appearancePage.stylePopupButton.target = self
        appearancePage.stylePopupButton.action = #selector(changeStyle)

        appearancePage.scrimButton.target = self
        appearancePage.scrimButton.action = #selector(toggleScrim)

        appearancePage.subduedButton.target = self
        appearancePage.subduedButton.action = #selector(toggleSubdued)

        appearancePage.backdropMaterialPopupButton.target = self
        appearancePage.backdropMaterialPopupButton.action = #selector(changeBackdropMaterial)

        appearancePage.backdropBlendModePopupButton.target = self
        appearancePage.backdropBlendModePopupButton.action = #selector(changeBackdropBlendMode)

        appearancePage.backdropEmphasizedButton.target = self
        appearancePage.backdropEmphasizedButton.action = #selector(toggleBackdropEmphasized)

        appearancePage.backdropAlphaRow.slider.target = self
        appearancePage.backdropAlphaRow.slider.action = #selector(changeBackdropAlpha)

        appearancePage.backdropIntensityRow.slider.target = self
        appearancePage.backdropIntensityRow.slider.action = #selector(changeBackdropIntensity)

        appearancePage.tintRow.slider.target = self
        appearancePage.tintRow.slider.action = #selector(changeTint)

        appearancePage.resetTintButton.target = self
        appearancePage.resetTintButton.action = #selector(resetTint)

        cornerRadiusPage.enableCustomCornersButton.target = self
        cornerRadiusPage.enableCustomCornersButton.action = #selector(toggleCustomCorners)

        cornerRadiusPage.topLeftRow.slider.target = self
        cornerRadiusPage.topLeftRow.slider.action = #selector(changeTopLeftCornerRadius)

        cornerRadiusPage.topRightRow.slider.target = self
        cornerRadiusPage.topRightRow.slider.action = #selector(changeTopRightCornerRadius)

        cornerRadiusPage.bottomLeftRow.slider.target = self
        cornerRadiusPage.bottomLeftRow.slider.action = #selector(changeBottomLeftCornerRadius)

        cornerRadiusPage.bottomRightRow.slider.target = self
        cornerRadiusPage.bottomRightRow.slider.action = #selector(changeBottomRightCornerRadius)

        cornerRadiusPage.resetCornersButton.target = self
        cornerRadiusPage.resetCornersButton.action = #selector(resetCornerRadii)
    }

    private func installObservers() {
        let center = NotificationCenter.default

        observers.append(
            center.addObserver(forName: .menuBarToggleChanged, object: toggleManager, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.refreshGeneralPage() }
            }
        )

        observers.append(
            center.addObserver(forName: .menuBarThemeChanged, object: themeManager, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refreshAppearancePage()
                    self?.applyWindowTheme()
                }
            }
        )

        observers.append(
            center.addObserver(forName: .menuBarBlurStyleChanged, object: blurStyleManager, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.refreshAppearancePage() }
            }
        )

        observers.append(
            center.addObserver(forName: .menuBarGlassTuningChanged, object: glassTuningManager, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refreshAppearancePage()
                    self?.refreshCornerPage()
                }
            }
        )

        observers.append(
            center.addObserver(forName: .menuBarLaunchAtLoginChanged, object: launchAtLoginManager, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.refreshGeneralPage() }
            }
        )

        observers.append(
            center.addObserver(forName: .menuBarStatusItemVisibilityChanged, object: statusItemVisibilityManager, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.refreshGeneralPage() }
            }
        )
    }

    @objc private func changeSelectedTab() {
        let selectedTab = SettingsTab(rawValue: tabSelector.selectedSegment) ?? .general
        applySelectedTab(selectedTab)
    }

    @objc private func toggleBlur() {
        toggleManager.setEnabled(generalPage.toggleButton.state == .on)
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            try launchAtLoginManager.setEnabled(generalPage.launchAtLoginButton.state == .on)
        } catch {
            refreshGeneralPage()
            presentErrorAlert(message: "Unable to update the login item setting.", error: error)
        }
    }

    @objc private func changeMenuBarIconVisibilityMode() {
        let selectedIndex = generalPage.menuBarIconPopupButton.indexOfSelectedItem
        guard StatusItemVisibilityManager.VisibilityMode.allCases.indices.contains(selectedIndex) else {
            return
        }

        statusItemVisibilityManager.setVisibilityMode(StatusItemVisibilityManager.VisibilityMode.allCases[selectedIndex])
    }

    @objc private func changeThemeMode() {
        guard !isRefreshingAppearancePage else {
            return
        }

        let selectedIndex = appearancePage.appearancePopupButton.indexOfSelectedItem
        guard ThemeManager.ThemeMode.allCases.indices.contains(selectedIndex) else {
            return
        }

        themeManager.setThemeMode(ThemeManager.ThemeMode.allCases[selectedIndex])
        applyWindowTheme()
    }

    @objc private func changeBlurMode() {
        guard !isRefreshingAppearancePage else {
            return
        }

        let selectedIndex = appearancePage.blurModePopupButton.indexOfSelectedItem
        guard BlurStyleManager.BlurMode.allCases.indices.contains(selectedIndex) else {
            return
        }

        blurStyleManager.setBlurMode(BlurStyleManager.BlurMode.allCases[selectedIndex])
    }

    @objc private func changeVariant() {
        guard !isRefreshingAppearancePage else {
            return
        }

        let selectedIndex = appearancePage.variantPopupButton.indexOfSelectedItem
        guard BlurStyleManager.PrivateGlassVariant.allCases.indices.contains(selectedIndex) else {
            return
        }

        blurStyleManager.setVariant(BlurStyleManager.PrivateGlassVariant.allCases[selectedIndex])
    }

    @objc private func changeStyle() {
        guard !isRefreshingAppearancePage else {
            return
        }

        let selectedIndex = appearancePage.stylePopupButton.indexOfSelectedItem
        guard BlurStyleManager.GlassStyle.allCases.indices.contains(selectedIndex) else {
            return
        }

        blurStyleManager.setStyle(BlurStyleManager.GlassStyle.allCases[selectedIndex])
    }

    @objc private func toggleScrim() {
        guard !isRefreshingAppearancePage else {
            return
        }

        blurStyleManager.setScrim(appearancePage.scrimButton.state == .on)
    }

    @objc private func toggleSubdued() {
        guard !isRefreshingAppearancePage else {
            return
        }

        blurStyleManager.setSubdued(appearancePage.subduedButton.state == .on)
    }

    @objc private func changeBackdropMaterial() {
        guard !isRefreshingAppearancePage else {
            return
        }

        let selectedIndex = appearancePage.backdropMaterialPopupButton.indexOfSelectedItem
        guard BlurStyleManager.BackdropMaterial.allCases.indices.contains(selectedIndex) else {
            return
        }

        blurStyleManager.setBackdropMaterial(BlurStyleManager.BackdropMaterial.allCases[selectedIndex])
    }

    @objc private func changeBackdropBlendMode() {
        guard !isRefreshingAppearancePage else {
            return
        }

        let selectedIndex = appearancePage.backdropBlendModePopupButton.indexOfSelectedItem
        guard BlurStyleManager.BackdropBlendMode.allCases.indices.contains(selectedIndex) else {
            return
        }

        blurStyleManager.setBackdropBlendMode(BlurStyleManager.BackdropBlendMode.allCases[selectedIndex])
    }

    @objc private func toggleBackdropEmphasized() {
        guard !isRefreshingAppearancePage else {
            return
        }

        blurStyleManager.setBackdropEmphasized(appearancePage.backdropEmphasizedButton.state == .on)
    }

    @objc private func changeBackdropAlpha() {
        guard !isRefreshingAppearancePage else {
            return
        }

        blurStyleManager.setBackdropAlpha(appearancePage.backdropAlphaRow.slider.doubleValue)
    }

    @objc private func changeBackdropIntensity() {
        guard !isRefreshingAppearancePage else {
            return
        }

        blurStyleManager.setBackdropIntensity(appearancePage.backdropIntensityRow.slider.doubleValue)
    }

    @objc private func changeTint() {
        guard !isRefreshingAppearancePage else {
            return
        }

        glassTuningManager.setTint(appearancePage.tintRow.slider.doubleValue)
    }

    @objc private func resetTint() {
        guard !isRefreshingAppearancePage else {
            return
        }

        glassTuningManager.resetToDefaults()
    }

    @objc private func toggleCustomCorners() {
        guard !isRefreshingCornerPage else {
            return
        }

        glassTuningManager.setCustomCornersEnabled(cornerRadiusPage.enableCustomCornersButton.state == .on)
    }

    @objc private func changeTopLeftCornerRadius() {
        updateCornerRadius(value: cornerRadiusPage.topLeftRow.slider.doubleValue, corner: .topLeft)
    }

    @objc private func changeTopRightCornerRadius() {
        updateCornerRadius(value: cornerRadiusPage.topRightRow.slider.doubleValue, corner: .topRight)
    }

    @objc private func changeBottomLeftCornerRadius() {
        updateCornerRadius(value: cornerRadiusPage.bottomLeftRow.slider.doubleValue, corner: .bottomLeft)
    }

    @objc private func changeBottomRightCornerRadius() {
        updateCornerRadius(value: cornerRadiusPage.bottomRightRow.slider.doubleValue, corner: .bottomRight)
    }

    @objc private func resetCornerRadii() {
        guard !isRefreshingCornerPage else {
            return
        }

        glassTuningManager.resetCornerRadiiToDefault()
    }

    private func updateCornerRadius(value: Double, corner: GlassTuningManager.Corner) {
        guard !isRefreshingCornerPage else {
            return
        }

        glassTuningManager.setCornerRadius(value, for: corner)
    }

    private func refresh() {
        refreshGeneralPage()
        refreshAppearancePage()
        refreshCornerPage()
    }

    private func refreshGeneralPage() {
        generalPage.toggleButton.state = toggleManager.isEnabled ? .on : .off
        generalPage.launchAtLoginButton.state = launchAtLoginManager.isEnabled ? .on : .off
        generalPage.menuBarIconPopupButton.selectItem(at: statusItemVisibilityManager.visibilityMode.rawValue)
        generalPage.launchAtLoginStatusLabel.stringValue = launchAtLoginManager.statusMessage
        generalPage.launchAtLoginStatusLabel.textColor = launchAtLoginManager.status == .requiresApproval ? .systemOrange : .secondaryLabelColor
        generalPage.menuBarIconStatusLabel.stringValue = statusItemVisibilityManager.statusMessage
    }

    private func refreshAppearancePage() {
        isRefreshingAppearancePage = true
        defer { isRefreshingAppearancePage = false }

        appearancePage.appearancePopupButton.selectItem(at: themeManager.themeMode.rawValue)

        let configuration = blurStyleManager.configuration

        if let blurModeIndex = BlurStyleManager.BlurMode.allCases.firstIndex(of: configuration.blurMode) {
            appearancePage.blurModePopupButton.selectItem(at: blurModeIndex)
        }

        if let variantIndex = BlurStyleManager.PrivateGlassVariant.allCases.firstIndex(of: configuration.variant) {
            appearancePage.variantPopupButton.selectItem(at: variantIndex)
        }

        if let styleIndex = BlurStyleManager.GlassStyle.allCases.firstIndex(of: configuration.style) {
            appearancePage.stylePopupButton.selectItem(at: styleIndex)
        }

        if let backdropMaterialIndex = BlurStyleManager.BackdropMaterial.allCases.firstIndex(of: configuration.backdropMaterial) {
            appearancePage.backdropMaterialPopupButton.selectItem(at: backdropMaterialIndex)
        }

        if let backdropBlendModeIndex = BlurStyleManager.BackdropBlendMode.allCases.firstIndex(of: configuration.backdropBlendMode) {
            appearancePage.backdropBlendModePopupButton.selectItem(at: backdropBlendModeIndex)
        }

        appearancePage.backdropEmphasizedButton.state = configuration.backdropEmphasized ? .on : .off
        appearancePage.backdropAlphaRow.slider.doubleValue = configuration.backdropAlpha
        appearancePage.backdropAlphaRow.valueLabel.stringValue = Self.backdropAlphaString(from: configuration.backdropAlpha)
        appearancePage.backdropIntensityRow.slider.doubleValue = configuration.backdropIntensity
        appearancePage.backdropIntensityRow.valueLabel.stringValue = Self.backdropIntensityString(from: configuration.backdropIntensity)
        appearancePage.setBlurMode(configuration.blurMode)

        let supportsStyle = configuration.variant.supportsStyleOverride
        appearancePage.stylePopupButton.isEnabled = supportsStyle
        appearancePage.styleHintLabel.isHidden = configuration.blurMode != .liquidGlass || supportsStyle

        appearancePage.scrimButton.state = configuration.scrim ? .on : .off
        appearancePage.subduedButton.state = configuration.subdued ? .on : .off
        appearancePage.tintRow.slider.doubleValue = glassTuningManager.tintWhiteAlpha
        appearancePage.tintRow.valueLabel.stringValue = Self.tintString(from: glassTuningManager.tintWhiteAlpha)
        appearancePage.materialStatusLabel.stringValue =
            configuration.blurMode == .liquidGlass ? blurStyleManager.configurationStatusMessage : ""
        appearancePage.backdropStatusLabel.stringValue =
            configuration.blurMode == .backdropBlur ? blurStyleManager.configurationStatusMessage : ""
    }

    private func refreshCornerPage() {
        isRefreshingCornerPage = true
        defer { isRefreshingCornerPage = false }

        let customCornersEnabled = glassTuningManager.customCornersEnabled
        let radii = glassTuningManager.cornerRadii
        cornerRadiusPage.enableCustomCornersButton.state = customCornersEnabled ? .on : .off
        cornerRadiusPage.setCornerControlsEnabled(customCornersEnabled)

        cornerRadiusPage.topLeftRow.slider.doubleValue = radii.topLeft
        cornerRadiusPage.topLeftRow.valueLabel.stringValue = Self.cornerRadiusString(from: radii.topLeft)

        cornerRadiusPage.topRightRow.slider.doubleValue = radii.topRight
        cornerRadiusPage.topRightRow.valueLabel.stringValue = Self.cornerRadiusString(from: radii.topRight)

        cornerRadiusPage.bottomLeftRow.slider.doubleValue = radii.bottomLeft
        cornerRadiusPage.bottomLeftRow.valueLabel.stringValue = Self.cornerRadiusString(from: radii.bottomLeft)

        cornerRadiusPage.bottomRightRow.slider.doubleValue = radii.bottomRight
        cornerRadiusPage.bottomRightRow.valueLabel.stringValue = Self.cornerRadiusString(from: radii.bottomRight)

        if customCornersEnabled {
            cornerRadiusPage.statusLabel.stringValue =
                "TL \(Self.cornerRadiusString(from: radii.topLeft)), TR \(Self.cornerRadiusString(from: radii.topRight)), BL \(Self.cornerRadiusString(from: radii.bottomLeft)), BR \(Self.cornerRadiusString(from: radii.bottomRight))"
        } else {
            cornerRadiusPage.statusLabel.stringValue = "Custom corners are disabled. Enable to apply corner radii."
        }
    }

    private func applyWindowTheme() {
        window?.appearance = themeManager.settingsWindowAppearance
    }

    private func applySelectedTab(_ tab: SettingsTab) {
        tabSelector.selectedSegment = tab.rawValue
        for (candidate, pageView) in tabViews {
            pageView.isHidden = candidate != tab
        }
    }

    private static func tintString(from value: Double) -> String {
        let clamped = min(max(value, GlassTuningManager.minTintWhiteAlpha), GlassTuningManager.maxTintWhiteAlpha)
        let magnitude = Int((abs(clamped) * 100).rounded())
        if magnitude == 0 {
            return "Off"
        }

        return clamped > 0 ? "W \(magnitude)%" : "B \(magnitude)%"
    }

    private static func cornerRadiusString(from value: Double) -> String {
        let clamped = min(max(value, GlassTuningManager.minCornerRadius), GlassTuningManager.maxCornerRadius)
        return String(format: "%.1f px", clamped)
    }

    private static func backdropAlphaString(from value: Double) -> String {
        let clamped = min(max(value, BlurStyleManager.minBackdropAlpha), BlurStyleManager.maxBackdropAlpha)
        return "\(Int((clamped * 100).rounded()))%"
    }

    private static func backdropIntensityString(from value: Double) -> String {
        let clamped = min(max(value, BlurStyleManager.minBackdropIntensity), BlurStyleManager.maxBackdropIntensity)
        return "\(Int((clamped * 100).rounded()))%"
    }

    private func presentErrorAlert(message: String, error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = message
        alert.informativeText = error.localizedDescription

        if let window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }
}

private final class GeneralSettingsPageView: NSView {
    let toggleButton = NSButton(checkboxWithTitle: "Enable Menu Bar Glass", target: nil, action: nil)
    let launchAtLoginButton = NSButton(checkboxWithTitle: "Start App at Login", target: nil, action: nil)
    let menuBarIconPopupButton = NSPopUpButton(frame: .zero, pullsDown: false)
    let launchAtLoginStatusLabel = NSTextField(labelWithString: "")
    let menuBarIconStatusLabel = NSTextField(labelWithString: "")
    let recoveryHintLabel = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    private func configure() {
        translatesAutoresizingMaskIntoConstraints = false

        let headingLabel = Self.makeHeading("General")
        let menuIconRow = Self.makeFormRow(title: "Menu Bar Icon", control: menuBarIconPopupButton)

        toggleButton.font = .systemFont(ofSize: 14, weight: .medium)
        launchAtLoginButton.font = .systemFont(ofSize: 14, weight: .medium)

        launchAtLoginStatusLabel.font = .systemFont(ofSize: 12, weight: .regular)
        launchAtLoginStatusLabel.textColor = .secondaryLabelColor
        launchAtLoginStatusLabel.maximumNumberOfLines = 0

        menuBarIconStatusLabel.font = .systemFont(ofSize: 12, weight: .regular)
        menuBarIconStatusLabel.textColor = .secondaryLabelColor
        menuBarIconStatusLabel.maximumNumberOfLines = 0

        recoveryHintLabel.font = .systemFont(ofSize: 12, weight: .regular)
        recoveryHintLabel.textColor = .secondaryLabelColor
        recoveryHintLabel.maximumNumberOfLines = 0

        let stack = NSStackView(views: [
            headingLabel,
            toggleButton,
            launchAtLoginButton,
            menuIconRow,
            launchAtLoginStatusLabel,
            menuBarIconStatusLabel,
            recoveryHintLabel
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 18),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -18)
        ])
    }

    private static func makeHeading(_ title: String) -> NSTextField {
        let heading = NSTextField(labelWithString: title)
        heading.font = .systemFont(ofSize: 17, weight: .semibold)
        heading.textColor = .labelColor
        return heading
    }

    private static func makeFormRow(title: String, control: NSView) -> NSStackView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.setContentHuggingPriority(.required, for: .horizontal)
        titleLabel.widthAnchor.constraint(equalToConstant: 130).isActive = true

        let row = NSStackView(views: [titleLabel, control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        return row
    }
}

private final class AppearanceSettingsPageView: NSView {
    let appearancePopupButton = NSPopUpButton(frame: .zero, pullsDown: false)
    let blurModePopupButton = NSPopUpButton(frame: .zero, pullsDown: false)

    let variantPopupButton = NSPopUpButton(frame: .zero, pullsDown: false)
    let stylePopupButton = NSPopUpButton(frame: .zero, pullsDown: false)
    let styleHintLabel = NSTextField(labelWithString: "Style only applies to Regular/Clear variants.")
    let scrimButton = NSButton(checkboxWithTitle: "Scrim (adds opaque wash)", target: nil, action: nil)
    let subduedButton = NSButton(checkboxWithTitle: "Subdued (flattens highlights)", target: nil, action: nil)

    let backdropMaterialPopupButton = NSPopUpButton(frame: .zero, pullsDown: false)
    let backdropBlendModePopupButton = NSPopUpButton(frame: .zero, pullsDown: false)
    let backdropEmphasizedButton = NSButton(checkboxWithTitle: "Emphasized", target: nil, action: nil)
    let backdropAlphaRow = TuningSliderRow(
        title: "Alpha",
        minValue: BlurStyleManager.minBackdropAlpha,
        maxValue: BlurStyleManager.maxBackdropAlpha
    )
    let backdropIntensityRow = TuningSliderRow(
        title: "Intensity",
        minValue: BlurStyleManager.minBackdropIntensity,
        maxValue: BlurStyleManager.maxBackdropIntensity
    )

    let tintRow = TuningSliderRow(
        title: "Tint",
        minValue: GlassTuningManager.minTintWhiteAlpha,
        maxValue: GlassTuningManager.maxTintWhiteAlpha
    )
    let resetTintButton = NSButton(title: "Reset Tint", target: nil, action: nil)
    let materialStatusLabel = NSTextField(labelWithString: "")
    let backdropStatusLabel = NSTextField(labelWithString: "")

    private let liquidSettingsContainer = NSStackView()
    private let backdropSettingsContainer = NSStackView()

    init() {
        super.init(frame: .zero)
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    private func configure() {
        translatesAutoresizingMaskIntoConstraints = false

        let headingLabel = Self.makeHeading("Appearance")
        let themeRow = Self.makeFormRow(title: "Theme", control: appearancePopupButton)
        let blurModeRow = Self.makeFormRow(title: "Blur Type", control: blurModePopupButton)

        let liquidHeadingLabel = Self.makeSectionHeading("Liquid Glass Settings")
        let variantRow = Self.makeFormRow(title: "Variant", control: variantPopupButton)
        let styleRow = Self.makeFormRow(title: "Style", control: stylePopupButton)

        styleHintLabel.font = .systemFont(ofSize: 11, weight: .regular)
        styleHintLabel.textColor = .secondaryLabelColor
        styleHintLabel.maximumNumberOfLines = 0

        materialStatusLabel.font = .systemFont(ofSize: 12, weight: .regular)
        materialStatusLabel.textColor = .secondaryLabelColor
        materialStatusLabel.maximumNumberOfLines = 0

        resetTintButton.bezelStyle = .rounded

        let backdropHeadingLabel = Self.makeSectionHeading("Backdrop Blur Settings")
        let backdropMaterialRow = Self.makeFormRow(title: "Material", control: backdropMaterialPopupButton)
        let backdropBlendModeRow = Self.makeFormRow(title: "Blend Mode", control: backdropBlendModePopupButton)

        backdropStatusLabel.font = .systemFont(ofSize: 12, weight: .regular)
        backdropStatusLabel.textColor = .secondaryLabelColor
        backdropStatusLabel.maximumNumberOfLines = 0

        liquidSettingsContainer.orientation = .vertical
        liquidSettingsContainer.alignment = .leading
        liquidSettingsContainer.spacing = 10
        liquidSettingsContainer.translatesAutoresizingMaskIntoConstraints = false
        liquidSettingsContainer.addArrangedSubview(liquidHeadingLabel)
        liquidSettingsContainer.addArrangedSubview(variantRow)
        liquidSettingsContainer.addArrangedSubview(styleRow)
        liquidSettingsContainer.addArrangedSubview(styleHintLabel)
        liquidSettingsContainer.addArrangedSubview(scrimButton)
        liquidSettingsContainer.addArrangedSubview(subduedButton)
        liquidSettingsContainer.addArrangedSubview(tintRow)
        liquidSettingsContainer.addArrangedSubview(resetTintButton)
        liquidSettingsContainer.addArrangedSubview(materialStatusLabel)

        backdropSettingsContainer.orientation = .vertical
        backdropSettingsContainer.alignment = .leading
        backdropSettingsContainer.spacing = 10
        backdropSettingsContainer.translatesAutoresizingMaskIntoConstraints = false
        backdropSettingsContainer.addArrangedSubview(backdropHeadingLabel)
        backdropSettingsContainer.addArrangedSubview(backdropMaterialRow)
        backdropSettingsContainer.addArrangedSubview(backdropBlendModeRow)
        backdropSettingsContainer.addArrangedSubview(backdropEmphasizedButton)
        backdropSettingsContainer.addArrangedSubview(backdropAlphaRow)
        backdropSettingsContainer.addArrangedSubview(backdropIntensityRow)
        backdropSettingsContainer.addArrangedSubview(backdropStatusLabel)

        let stack = NSStackView(views: [
            headingLabel,
            themeRow,
            blurModeRow,
            liquidSettingsContainer,
            backdropSettingsContainer
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 18),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -18),
            liquidSettingsContainer.widthAnchor.constraint(equalTo: stack.widthAnchor),
            backdropSettingsContainer.widthAnchor.constraint(equalTo: stack.widthAnchor),
            tintRow.widthAnchor.constraint(equalTo: liquidSettingsContainer.widthAnchor),
            backdropAlphaRow.widthAnchor.constraint(equalTo: backdropSettingsContainer.widthAnchor),
            backdropIntensityRow.widthAnchor.constraint(equalTo: backdropSettingsContainer.widthAnchor)
        ])

        setBlurMode(.liquidGlass)
    }

    private static func makeHeading(_ title: String) -> NSTextField {
        let heading = NSTextField(labelWithString: title)
        heading.font = .systemFont(ofSize: 17, weight: .semibold)
        heading.textColor = .labelColor
        return heading
    }

    private static func makeSectionHeading(_ title: String) -> NSTextField {
        let heading = NSTextField(labelWithString: title)
        heading.font = .systemFont(ofSize: 13, weight: .semibold)
        heading.textColor = .secondaryLabelColor
        return heading
    }

    func setBlurMode(_ blurMode: BlurStyleManager.BlurMode) {
        let isLiquidGlass = blurMode == .liquidGlass
        liquidSettingsContainer.isHidden = !isLiquidGlass
        backdropSettingsContainer.isHidden = isLiquidGlass
    }

    private static func makeFormRow(title: String, control: NSView) -> NSStackView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.setContentHuggingPriority(.required, for: .horizontal)
        titleLabel.widthAnchor.constraint(equalToConstant: 130).isActive = true

        let row = NSStackView(views: [titleLabel, control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        return row
    }
}

private final class CornerRadiusSettingsPageView: NSView {
    let enableCustomCornersButton = NSButton(checkboxWithTitle: "Enable Custom Corners", target: nil, action: nil)
    let topLeftRow = TuningSliderRow(
        title: "Top Left",
        minValue: GlassTuningManager.minCornerRadius,
        maxValue: GlassTuningManager.maxCornerRadius
    )
    let topRightRow = TuningSliderRow(
        title: "Top Right",
        minValue: GlassTuningManager.minCornerRadius,
        maxValue: GlassTuningManager.maxCornerRadius
    )
    let bottomLeftRow = TuningSliderRow(
        title: "Bottom Left",
        minValue: GlassTuningManager.minCornerRadius,
        maxValue: GlassTuningManager.maxCornerRadius
    )
    let bottomRightRow = TuningSliderRow(
        title: "Bottom Right",
        minValue: GlassTuningManager.minCornerRadius,
        maxValue: GlassTuningManager.maxCornerRadius
    )
    let resetCornersButton = NSButton(title: "Reset All Corners", target: nil, action: nil)
    let statusLabel = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    private func configure() {
        translatesAutoresizingMaskIntoConstraints = false

        let headingLabel = NSTextField(labelWithString: "Corners")
        headingLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        headingLabel.textColor = .labelColor

        let descriptionLabel = NSTextField(
            labelWithString: "Set each corner radius independently to match your display curve."
        )
        descriptionLabel.font = .systemFont(ofSize: 12, weight: .regular)
        descriptionLabel.textColor = .secondaryLabelColor
        descriptionLabel.maximumNumberOfLines = 0

        enableCustomCornersButton.font = .systemFont(ofSize: 13, weight: .medium)
        resetCornersButton.bezelStyle = .rounded

        statusLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.maximumNumberOfLines = 0

        let stack = NSStackView(views: [
            headingLabel,
            descriptionLabel,
            enableCustomCornersButton,
            topLeftRow,
            topRightRow,
            bottomLeftRow,
            bottomRightRow,
            resetCornersButton,
            statusLabel
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 18),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -18),
            topLeftRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            topRightRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            bottomLeftRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            bottomRightRow.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
    }

    func setCornerControlsEnabled(_ isEnabled: Bool) {
        topLeftRow.slider.isEnabled = isEnabled
        topRightRow.slider.isEnabled = isEnabled
        bottomLeftRow.slider.isEnabled = isEnabled
        bottomRightRow.slider.isEnabled = isEnabled
        resetCornersButton.isEnabled = isEnabled
    }
}

private final class TuningSliderRow: NSView {
    let slider: NSSlider
    let valueLabel = NSTextField(labelWithString: "Off")

    init(title: String, minValue: Double, maxValue: Double) {
        slider = NSSlider(value: 0, minValue: minValue, maxValue: maxValue, target: nil, action: nil)
        super.init(frame: .zero)
        configure(title: title)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    private func configure(title: String) {
        translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        slider.isContinuous = true
        slider.numberOfTickMarks = 0
        slider.translatesAutoresizingMaskIntoConstraints = false

        valueLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        valueLabel.alignment = .right
        valueLabel.textColor = .secondaryLabelColor
        valueLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(titleLabel)
        addSubview(slider)
        addSubview(valueLabel)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.widthAnchor.constraint(equalToConstant: 130),

            slider.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 12),
            slider.centerYAnchor.constraint(equalTo: centerYAnchor),

            valueLabel.leadingAnchor.constraint(equalTo: slider.trailingAnchor, constant: 12),
            valueLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            valueLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            valueLabel.widthAnchor.constraint(equalToConstant: 76),
            bottomAnchor.constraint(equalTo: slider.bottomAnchor)
        ])
    }
}

private final class CreditsSettingsPageView: NSView {
    init() {
        super.init(frame: .zero)
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    private func configure() {
        translatesAutoresizingMaskIntoConstraints = false

        let headingLabel = NSTextField(labelWithString: "Credits")
        headingLabel.font = .systemFont(ofSize: 17, weight: .semibold)

        let nameLabel = NSTextField(labelWithString: "Parishkar Singh")
        nameLabel.font = .systemFont(ofSize: 14, weight: .medium)

        let roleLabel = NSTextField(labelWithString: "Developer")
        roleLabel.font = .systemFont(ofSize: 12, weight: .regular)
        roleLabel.textColor = .secondaryLabelColor

        let profileLabel = NSTextField(labelWithString: "")
        profileLabel.allowsEditingTextAttributes = true
        profileLabel.isSelectable = true
        profileLabel.drawsBackground = false
        profileLabel.isBezeled = false
        profileLabel.font = .systemFont(ofSize: 13, weight: .regular)

        let profileURLString = "https://github.com/parishkar-singh"
        if let profileURL = URL(string: profileURLString) {
            let attributes: [NSAttributedString.Key: Any] = [
                .link: profileURL,
                .foregroundColor: NSColor.linkColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue
            ]
            profileLabel.attributedStringValue = NSAttributedString(string: profileURLString, attributes: attributes)
        } else {
            profileLabel.stringValue = profileURLString
            profileLabel.textColor = .secondaryLabelColor
        }

        let noteLabel = NSTextField(labelWithString: "Thank you for using MenuBarLG.")
        noteLabel.font = .systemFont(ofSize: 12, weight: .regular)
        noteLabel.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [headingLabel, nameLabel, roleLabel, profileLabel, noteLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 18),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -18)
        ])
    }
}
