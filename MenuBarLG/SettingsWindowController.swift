import AppKit
import ServiceManagement

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let toggleManager: ToggleManager
    private let themeManager: ThemeManager
    private let blurStyleManager: BlurStyleManager
    private let glassTuningManager: GlassTuningManager
    private let launchAtLoginManager: LaunchAtLoginManager
    private let statusItemVisibilityManager: StatusItemVisibilityManager

    var settingsVisibilityChangedHandler: ((Bool) -> Void)?

    private let subtitleLabel = NSTextField(labelWithString: "Liquid Glass menu bar overlay (macOS 26+)")
    private let tabView = NSTabView(frame: .zero)
    private let generalSection = GeneralSettingsSectionView()
    private let appearanceSection = AppearanceSettingsSectionView()
    private let tuningSection = TuningSettingsSectionView()
    private let creditsSection = CreditsSettingsSectionView()

    private var observers: [NSObjectProtocol] = []

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
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.center()
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 560, height: 560)

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
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        settingsVisibilityChangedHandler?(true)
        // Bring the app forward only when opening settings from the menu bar.
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

        tabView.translatesAutoresizingMaskIntoConstraints = false
        tabView.tabViewType = .topTabsBezelBorder
        configureTabs()

        contentView.addSubview(titleLabel)
        contentView.addSubview(subtitleLabel)
        contentView.addSubview(tabView)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 22),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -24),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            subtitleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            subtitleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),

            tabView.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 16),
            tabView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            tabView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            tabView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -24)
        ])

        window.contentView = contentView
    }

    private func configureTabs() {
        tabView.tabViewItems.forEach { tabView.removeTabViewItem($0) }
        addTab(title: "General", sectionView: generalSection)
        addTab(title: "Appearance", sectionView: appearanceSection)
        addTab(title: "Tuning", sectionView: tuningSection)
        addTab(title: "Credits", sectionView: creditsSection)
        tabView.selectTabViewItem(at: 0)
    }

    private func addTab(title: String, sectionView: NSView) {
        let containerView = NSView(frame: .zero)
        containerView.translatesAutoresizingMaskIntoConstraints = false

        containerView.addSubview(sectionView)
        NSLayoutConstraint.activate([
            sectionView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 8),
            sectionView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            sectionView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            sectionView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])

        let tabItem = NSTabViewItem(identifier: title)
        tabItem.label = title
        tabItem.view = containerView
        tabView.addTabViewItem(tabItem)
    }

    private func configureControlOptions() {
        appearanceSection.appearancePopupButton.removeAllItems()
        appearanceSection.appearancePopupButton.addItems(withTitles: ThemeManager.ThemeMode.allCases.map(\.title))

        appearanceSection.materialPresetPopupButton.removeAllItems()
        appearanceSection.materialPresetPopupButton.addItems(withTitles: BlurStyleManager.materialPresetDisplayOrder.map(\.title))

        generalSection.menuBarIconPopupButton.removeAllItems()
        generalSection.menuBarIconPopupButton.addItems(withTitles: StatusItemVisibilityManager.VisibilityMode.allCases.map(\.title))

        generalSection.recoveryHintLabel.stringValue =
            "Recovery: when icon mode is \"Show 5s On Startup\", press \(Self.statusIconRecoveryShortcut) to restore the icon for 25 seconds."
    }

    private func bindActions() {
        generalSection.toggleButton.target = self
        generalSection.toggleButton.action = #selector(toggleBlur)

        generalSection.launchAtLoginButton.target = self
        generalSection.launchAtLoginButton.action = #selector(toggleLaunchAtLogin)

        generalSection.menuBarIconPopupButton.target = self
        generalSection.menuBarIconPopupButton.action = #selector(changeMenuBarIconVisibilityMode)

        appearanceSection.appearancePopupButton.target = self
        appearanceSection.appearancePopupButton.action = #selector(changeThemeMode)

        appearanceSection.materialPresetPopupButton.target = self
        appearanceSection.materialPresetPopupButton.action = #selector(changeMaterialPreset)

        tuningSection.moreLiquidAlphaRow.slider.target = self
        tuningSection.moreLiquidAlphaRow.slider.action = #selector(changeMoreLiquidAlpha)
        tuningSection.moreLiquidTintRow.slider.target = self
        tuningSection.moreLiquidTintRow.slider.action = #selector(changeMoreLiquidTint)
        tuningSection.normalAlphaRow.slider.target = self
        tuningSection.normalAlphaRow.slider.action = #selector(changeNormalAlpha)
        tuningSection.normalTintRow.slider.target = self
        tuningSection.normalTintRow.slider.action = #selector(changeNormalTint)
        tuningSection.frostedAlphaRow.slider.target = self
        tuningSection.frostedAlphaRow.slider.action = #selector(changeFrostedAlpha)
        tuningSection.frostedTintRow.slider.target = self
        tuningSection.frostedTintRow.slider.action = #selector(changeFrostedTint)
        tuningSection.resetButton.target = self
        tuningSection.resetButton.action = #selector(resetTuningToDefaults)
    }

    private func installObservers() {
        let center = NotificationCenter.default

        observers.append(
            center.addObserver(forName: .menuBarToggleChanged, object: toggleManager, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.refreshGeneralSection() }
            }
        )

        observers.append(
            center.addObserver(forName: .menuBarThemeChanged, object: themeManager, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.refreshAppearanceSection() }
            }
        )

        observers.append(
            center.addObserver(forName: .menuBarBlurStyleChanged, object: blurStyleManager, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refreshAppearanceSection()
                    self?.refreshTuningSection()
                }
            }
        )

        observers.append(
            center.addObserver(forName: .menuBarGlassTuningChanged, object: glassTuningManager, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.refreshTuningSection() }
            }
        )

        observers.append(
            center.addObserver(forName: .menuBarLaunchAtLoginChanged, object: launchAtLoginManager, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.refreshGeneralSection() }
            }
        )

        observers.append(
            center.addObserver(forName: .menuBarStatusItemVisibilityChanged, object: statusItemVisibilityManager, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.refreshGeneralSection() }
            }
        )
    }

    @objc private func toggleBlur() {
        toggleManager.setEnabled(generalSection.toggleButton.state == .on)
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            try launchAtLoginManager.setEnabled(generalSection.launchAtLoginButton.state == .on)
        } catch {
            refreshGeneralSection()
            presentErrorAlert(message: "Unable to update the login item setting.", error: error)
        }
    }

    @objc private func changeMenuBarIconVisibilityMode() {
        let selectedIndex = generalSection.menuBarIconPopupButton.indexOfSelectedItem
        guard StatusItemVisibilityManager.VisibilityMode.allCases.indices.contains(selectedIndex) else {
            return
        }

        statusItemVisibilityManager.setVisibilityMode(StatusItemVisibilityManager.VisibilityMode.allCases[selectedIndex])
    }

    @objc private func changeThemeMode() {
        let selectedIndex = appearanceSection.appearancePopupButton.indexOfSelectedItem
        guard ThemeManager.ThemeMode.allCases.indices.contains(selectedIndex) else {
            return
        }

        themeManager.setThemeMode(ThemeManager.ThemeMode.allCases[selectedIndex])
    }

    @objc private func changeMaterialPreset() {
        let selectedIndex = appearanceSection.materialPresetPopupButton.indexOfSelectedItem
        guard BlurStyleManager.materialPresetDisplayOrder.indices.contains(selectedIndex) else {
            return
        }

        blurStyleManager.setMaterialPreset(BlurStyleManager.materialPresetDisplayOrder[selectedIndex])
    }

    @objc private func changeMoreLiquidAlpha() {
        glassTuningManager.setAlpha(tuningSection.moreLiquidAlphaRow.slider.doubleValue, for: .moreLiquid)
    }

    @objc private func changeMoreLiquidTint() {
        glassTuningManager.setTint(tuningSection.moreLiquidTintRow.slider.doubleValue, for: .moreLiquid)
    }

    @objc private func changeNormalAlpha() {
        glassTuningManager.setAlpha(tuningSection.normalAlphaRow.slider.doubleValue, for: .normal)
    }

    @objc private func changeNormalTint() {
        glassTuningManager.setTint(tuningSection.normalTintRow.slider.doubleValue, for: .normal)
    }

    @objc private func changeFrostedAlpha() {
        glassTuningManager.setAlpha(tuningSection.frostedAlphaRow.slider.doubleValue, for: .frosted)
    }

    @objc private func changeFrostedTint() {
        glassTuningManager.setTint(tuningSection.frostedTintRow.slider.doubleValue, for: .frosted)
    }

    @objc private func resetTuningToDefaults() {
        glassTuningManager.resetToDefaults()
    }

    private func refresh() {
        refreshGeneralSection()
        refreshAppearanceSection()
        refreshTuningSection()
    }

    private func refreshGeneralSection() {
        generalSection.toggleButton.state = toggleManager.isEnabled ? .on : .off
        generalSection.launchAtLoginButton.state = launchAtLoginManager.isEnabled ? .on : .off
        generalSection.menuBarIconPopupButton.selectItem(at: statusItemVisibilityManager.visibilityMode.rawValue)
        generalSection.launchAtLoginStatusLabel.stringValue = launchAtLoginManager.statusMessage
        generalSection.launchAtLoginStatusLabel.textColor = launchAtLoginManager.status == .requiresApproval ? .systemOrange : .secondaryLabelColor
        generalSection.menuBarIconStatusLabel.stringValue = statusItemVisibilityManager.statusMessage
    }

    private func refreshAppearanceSection() {
        appearanceSection.appearancePopupButton.selectItem(at: themeManager.themeMode.rawValue)

        if let selectedIndex = BlurStyleManager.materialPresetDisplayOrder.firstIndex(of: blurStyleManager.materialPreset) {
            appearanceSection.materialPresetPopupButton.selectItem(at: selectedIndex)
        } else {
            appearanceSection.materialPresetPopupButton.selectItem(at: 0)
        }

        appearanceSection.materialStatusLabel.stringValue = blurStyleManager.materialPresetStatusMessage
    }

    private func refreshTuningSection() {
        update(row: tuningSection.moreLiquidAlphaRow, value: glassTuningManager.alpha(for: .moreLiquid), formatter: Self.percentString)
        update(row: tuningSection.moreLiquidTintRow, value: glassTuningManager.tint(for: .moreLiquid), formatter: Self.tintString)
        update(row: tuningSection.normalAlphaRow, value: glassTuningManager.alpha(for: .normal), formatter: Self.percentString)
        update(row: tuningSection.normalTintRow, value: glassTuningManager.tint(for: .normal), formatter: Self.tintString)
        update(row: tuningSection.frostedAlphaRow, value: glassTuningManager.alpha(for: .frosted), formatter: Self.percentString)
        update(row: tuningSection.frostedTintRow, value: glassTuningManager.tint(for: .frosted), formatter: Self.tintString)
    }

    private func update(row: TuningSliderRow, value: Double, formatter: (Double) -> String) {
        row.slider.doubleValue = value
        row.valueLabel.stringValue = formatter(value)
    }

    private static func percentString(from value: Double) -> String {
        let clamped = min(max(value, 0), 1)
        return "\(Int((clamped * 100).rounded()))%"
    }

    private static func tintString(from value: Double) -> String {
        let clamped = min(max(value, -1), 1)
        let magnitude = Int((abs(clamped) * 100).rounded())
        if magnitude == 0 {
            return "Off"
        }

        return clamped > 0 ? "W \(magnitude)%" : "B \(magnitude)%"
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

private final class GeneralSettingsSectionView: NSView {
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

        toggleButton.font = .systemFont(ofSize: 14, weight: .medium)
        launchAtLoginButton.font = .systemFont(ofSize: 14, weight: .medium)

        let iconTitle = NSTextField(labelWithString: "Menu Bar Icon")
        iconTitle.font = .systemFont(ofSize: 13, weight: .medium)

        launchAtLoginStatusLabel.font = .systemFont(ofSize: 12, weight: .regular)
        launchAtLoginStatusLabel.textColor = .secondaryLabelColor
        launchAtLoginStatusLabel.maximumNumberOfLines = 0

        menuBarIconStatusLabel.font = .systemFont(ofSize: 12, weight: .regular)
        menuBarIconStatusLabel.textColor = .secondaryLabelColor
        menuBarIconStatusLabel.maximumNumberOfLines = 0

        recoveryHintLabel.font = .systemFont(ofSize: 12, weight: .regular)
        recoveryHintLabel.textColor = .secondaryLabelColor
        recoveryHintLabel.maximumNumberOfLines = 0

        let iconRow = NSStackView(views: [iconTitle, menuBarIconPopupButton])
        iconRow.orientation = .horizontal
        iconRow.alignment = .centerY
        iconRow.spacing = 12

        let stack = NSStackView(views: [toggleButton, launchAtLoginButton, iconRow, launchAtLoginStatusLabel, menuBarIconStatusLabel, recoveryHintLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16)
        ])
    }
}

private final class AppearanceSettingsSectionView: NSView {
    let appearancePopupButton = NSPopUpButton(frame: .zero, pullsDown: false)
    let materialPresetPopupButton = NSPopUpButton(frame: .zero, pullsDown: false)
    let materialStatusLabel = NSTextField(labelWithString: "")

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

        let modeLabel = NSTextField(labelWithString: "Theme")
        modeLabel.font = .systemFont(ofSize: 13, weight: .medium)

        let presetLabel = NSTextField(labelWithString: "Glass Feel")
        presetLabel.font = .systemFont(ofSize: 13, weight: .medium)

        materialStatusLabel.font = .systemFont(ofSize: 12, weight: .regular)
        materialStatusLabel.textColor = .secondaryLabelColor
        materialStatusLabel.maximumNumberOfLines = 0

        let modeRow = NSStackView(views: [modeLabel, appearancePopupButton])
        modeRow.orientation = .horizontal
        modeRow.alignment = .centerY
        modeRow.spacing = 12

        let presetRow = NSStackView(views: [presetLabel, materialPresetPopupButton])
        presetRow.orientation = .horizontal
        presetRow.alignment = .centerY
        presetRow.spacing = 12

        let stack = NSStackView(views: [modeRow, presetRow, materialStatusLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16)
        ])
    }
}

private final class TuningSettingsSectionView: NSView {
    let moreLiquidAlphaRow = TuningSliderRow(title: "More Liquid Alpha", minValue: 0, maxValue: 1)
    let moreLiquidTintRow = TuningSliderRow(title: "More Liquid Tint", minValue: -1, maxValue: 1)
    let normalAlphaRow = TuningSliderRow(title: "Normal Alpha", minValue: 0, maxValue: 1)
    let normalTintRow = TuningSliderRow(title: "Normal Tint", minValue: -1, maxValue: 1)
    let frostedAlphaRow = TuningSliderRow(title: "Frosted Alpha", minValue: 0, maxValue: 1)
    let frostedTintRow = TuningSliderRow(title: "Frosted Tint", minValue: -1, maxValue: 1)
    let resetButton = NSButton(title: "Reset Tuning to Defaults", target: nil, action: nil)

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

        let noteLabel = NSTextField(
            labelWithString: "Each preset has independent Alpha/Tint. Tint supports black and white: negative is black, positive is white."
        )
        noteLabel.font = .systemFont(ofSize: 12, weight: .regular)
        noteLabel.textColor = .secondaryLabelColor
        noteLabel.maximumNumberOfLines = 0

        for row in allRows {
            row.translatesAutoresizingMaskIntoConstraints = false
        }

        resetButton.bezelStyle = .rounded

        let stack = NSStackView(views: [
            moreLiquidAlphaRow,
            moreLiquidTintRow,
            normalAlphaRow,
            normalTintRow,
            frostedAlphaRow,
            frostedTintRow,
            resetButton,
            noteLabel
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
            moreLiquidAlphaRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            moreLiquidTintRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            normalAlphaRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            normalTintRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            frostedAlphaRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            frostedTintRow.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
    }

    private var allRows: [TuningSliderRow] {
        [moreLiquidAlphaRow, moreLiquidTintRow, normalAlphaRow, normalTintRow, frostedAlphaRow, frostedTintRow]
    }
}

private final class TuningSliderRow: NSView {
    let slider: NSSlider
    let valueLabel = NSTextField(labelWithString: "0%")

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
            valueLabel.widthAnchor.constraint(equalToConstant: 58),
            bottomAnchor.constraint(equalTo: slider.bottomAnchor)
        ])
    }
}

private final class CreditsSettingsSectionView: NSView {
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

        let headingLabel = NSTextField(labelWithString: "Developer")
        headingLabel.font = .systemFont(ofSize: 14, weight: .semibold)

        let nameLabel = NSTextField(labelWithString: "Parishkar Singh")
        nameLabel.font = .systemFont(ofSize: 13, weight: .medium)

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

        let stack = NSStackView(views: [headingLabel, nameLabel, profileLabel, noteLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -16)
        ])
    }
}
