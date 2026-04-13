import AppKit

extension Notification.Name {
    static let menuBarBlurStyleChanged = Notification.Name("MenuBarBlurStyleChanged")
}

@MainActor
final class BlurStyleManager {
    static let minBackdropAlpha = 0.0
    static let maxBackdropAlpha = 1.0
    static let minBackdropIntensity = 0.0
    static let maxBackdropIntensity = 1.0
    static let defaultBackdropMaterial: BackdropMaterial = .hudWindow
    static let defaultBackdropBlendMode: BackdropBlendMode = .withinWindow
    static let defaultBackdropEmphasized = true
    static let defaultBackdropAlpha = 1.0
    static let defaultBackdropIntensity = 0.76

    enum BlurMode: Int, CaseIterable {
        case liquidGlass
        case backdropBlur

        var title: String {
            switch self {
            case .liquidGlass:
                return "Liquid Glass"
            case .backdropBlur:
                return "Backdrop Blur"
            }
        }
    }

    enum PrivateGlassVariant: Int, CaseIterable {
        case regular = 0
        case clear = 1
        case dock = 2
        case avPlayer = 6
        case controlCenter = 8
        case notificationCenter = 9
        case monogram = 10

        var title: String {
            switch self {
            case .regular:
                return "Regular"
            case .clear:
                return "Clear"
            case .dock:
                return "Dock"
            case .avPlayer:
                return "AV Player"
            case .controlCenter:
                return "Control Center"
            case .notificationCenter:
                return "Notification Center"
            case .monogram:
                return "Monogram"
            }
        }

        var supportsStyleOverride: Bool {
            switch self {
            case .regular, .clear:
                return true
            default:
                return false
            }
        }
    }

    enum GlassStyle: Int, CaseIterable {
        case clear
        case regular

        var title: String {
            switch self {
            case .clear:
                return "Clear"
            case .regular:
                return "Regular"
            }
        }
    }

    enum BackdropMaterial: Int, CaseIterable {
        case menu
        case sidebar
        case headerView
        case windowBackground
        case underWindowBackground
        case hudWindow

        var title: String {
            switch self {
            case .menu:
                return "Menu"
            case .sidebar:
                return "Sidebar"
            case .headerView:
                return "Header View"
            case .windowBackground:
                return "Window Background"
            case .underWindowBackground:
                return "Under Window Background"
            case .hudWindow:
                return "HUD Window"
            }
        }

        var visualEffectMaterial: NSVisualEffectView.Material {
            switch self {
            case .menu:
                return .menu
            case .sidebar:
                return .sidebar
            case .headerView:
                return .headerView
            case .windowBackground:
                return .windowBackground
            case .underWindowBackground:
                return .underWindowBackground
            case .hudWindow:
                return .hudWindow
            }
        }
    }

    enum BackdropBlendMode: Int, CaseIterable {
        case behindWindow
        case withinWindow

        var title: String {
            switch self {
            case .behindWindow:
                return "Behind Window"
            case .withinWindow:
                return "Within Window"
            }
        }

        var visualEffectBlendMode: NSVisualEffectView.BlendingMode {
            switch self {
            case .behindWindow:
                return .behindWindow
            case .withinWindow:
                return .withinWindow
            }
        }
    }

    struct Configuration: Equatable {
        var blurMode: BlurMode
        var variant: PrivateGlassVariant
        var style: GlassStyle
        var scrim: Bool
        var subdued: Bool
        var backdropMaterial: BackdropMaterial
        var backdropBlendMode: BackdropBlendMode
        var backdropEmphasized: Bool
        var backdropAlpha: Double
        var backdropIntensity: Double
    }

    private enum DefaultsKey {
        static let blurMode = "menuBarBlurMode"
        static let variant = "menuBarPrivateGlassVariant"
        static let style = "menuBarPrivateGlassStyle"
        static let scrim = "menuBarPrivateGlassScrim"
        static let subdued = "menuBarPrivateGlassSubdued"
        static let backdropMaterial = "menuBarBackdropMaterial"
        static let backdropBlendMode = "menuBarBackdropBlendMode"
        static let backdropEmphasized = "menuBarBackdropEmphasized"
        static let backdropAlpha = "menuBarBackdropAlpha"
        static let backdropIntensity = "menuBarBackdropIntensity"
    }

    private let userDefaults: UserDefaults

    private(set) var configuration: Configuration

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults

        let storedBlurMode = BlurMode(rawValue: userDefaults.integer(forKey: DefaultsKey.blurMode)) ?? .liquidGlass
        let storedVariant = PrivateGlassVariant(rawValue: userDefaults.integer(forKey: DefaultsKey.variant)) ?? .dock
        let storedStyle = GlassStyle(rawValue: userDefaults.integer(forKey: DefaultsKey.style)) ?? .clear
        let storedScrim = userDefaults.object(forKey: DefaultsKey.scrim) as? Bool ?? false
        let storedSubdued = userDefaults.object(forKey: DefaultsKey.subdued) as? Bool ?? false
        let storedBackdropMaterial = (userDefaults.object(forKey: DefaultsKey.backdropMaterial) as? Int)
            .flatMap(BackdropMaterial.init(rawValue:))
            ?? Self.defaultBackdropMaterial
        let storedBackdropBlendMode = (userDefaults.object(forKey: DefaultsKey.backdropBlendMode) as? Int)
            .flatMap(BackdropBlendMode.init(rawValue:))
            ?? Self.defaultBackdropBlendMode
        let storedBackdropEmphasized = userDefaults.object(forKey: DefaultsKey.backdropEmphasized) as? Bool ?? Self.defaultBackdropEmphasized
        let storedBackdropAlpha = userDefaults.object(forKey: DefaultsKey.backdropAlpha) as? Double ?? Self.defaultBackdropAlpha
        let storedBackdropIntensity = userDefaults.object(forKey: DefaultsKey.backdropIntensity) as? Double ?? Self.defaultBackdropIntensity

        configuration = Configuration(
            blurMode: storedBlurMode,
            variant: storedVariant,
            style: storedStyle,
            scrim: storedScrim,
            subdued: storedSubdued,
            backdropMaterial: storedBackdropMaterial,
            backdropBlendMode: storedBackdropBlendMode,
            backdropEmphasized: storedBackdropEmphasized,
            backdropAlpha: Self.clampedBackdropAlpha(storedBackdropAlpha),
            backdropIntensity: Self.clampedBackdropIntensity(storedBackdropIntensity)
        )
    }

    var configurationStatusMessage: String {
        switch configuration.blurMode {
        case .liquidGlass:
            let styleSummary = configuration.style == .clear ? "clear glass" : "regular glass"
            let scrimSummary = configuration.scrim ? "Scrim is on." : "Scrim is off."
            let subduedSummary = configuration.subdued ? "Subdued is on." : "Subdued is off."
            let styleCompatibility = configuration.variant.supportsStyleOverride
                ? "\(configuration.variant.title) uses \(styleSummary)."
                : "\(configuration.variant.title) ignores Style."
            return "\(styleCompatibility) \(scrimSummary) \(subduedSummary)"
        case .backdropBlur:
            let emphasizedSummary = configuration.backdropEmphasized ? "Emphasized is on." : "Emphasized is off."
            let alphaSummary = Self.backdropAlphaSummary(configuration.backdropAlpha)
            let intensitySummary = Self.backdropIntensitySummary(configuration.backdropIntensity)
            return "\(configuration.backdropMaterial.title) material with \(configuration.backdropBlendMode.title). \(emphasizedSummary) Alpha \(alphaSummary). Intensity \(intensitySummary)."
        }
    }

    func setBlurMode(_ blurMode: BlurMode) {
        guard configuration.blurMode != blurMode else {
            return
        }

        configuration.blurMode = blurMode
        userDefaults.set(blurMode.rawValue, forKey: DefaultsKey.blurMode)
        notifyChanged()
    }

    func setVariant(_ variant: PrivateGlassVariant) {
        guard configuration.variant != variant else {
            return
        }

        configuration.variant = variant
        userDefaults.set(variant.rawValue, forKey: DefaultsKey.variant)
        notifyChanged()
    }

    func setStyle(_ style: GlassStyle) {
        guard configuration.style != style else {
            return
        }

        configuration.style = style
        userDefaults.set(style.rawValue, forKey: DefaultsKey.style)
        notifyChanged()
    }

    func setScrim(_ scrim: Bool) {
        guard configuration.scrim != scrim else {
            return
        }

        configuration.scrim = scrim
        userDefaults.set(scrim, forKey: DefaultsKey.scrim)
        notifyChanged()
    }

    func setSubdued(_ subdued: Bool) {
        guard configuration.subdued != subdued else {
            return
        }

        configuration.subdued = subdued
        userDefaults.set(subdued, forKey: DefaultsKey.subdued)
        notifyChanged()
    }

    func setBackdropMaterial(_ material: BackdropMaterial) {
        guard configuration.backdropMaterial != material else {
            return
        }

        configuration.backdropMaterial = material
        userDefaults.set(material.rawValue, forKey: DefaultsKey.backdropMaterial)
        notifyChanged()
    }

    func setBackdropBlendMode(_ blendMode: BackdropBlendMode) {
        guard configuration.backdropBlendMode != blendMode else {
            return
        }

        configuration.backdropBlendMode = blendMode
        userDefaults.set(blendMode.rawValue, forKey: DefaultsKey.backdropBlendMode)
        notifyChanged()
    }

    func setBackdropEmphasized(_ emphasized: Bool) {
        guard configuration.backdropEmphasized != emphasized else {
            return
        }

        configuration.backdropEmphasized = emphasized
        userDefaults.set(emphasized, forKey: DefaultsKey.backdropEmphasized)
        notifyChanged()
    }

    func setBackdropAlpha(_ alpha: Double) {
        let clampedAlpha = Self.clampedBackdropAlpha(alpha)
        guard configuration.backdropAlpha != clampedAlpha else {
            return
        }

        configuration.backdropAlpha = clampedAlpha
        userDefaults.set(clampedAlpha, forKey: DefaultsKey.backdropAlpha)
        notifyChanged()
    }

    func setBackdropIntensity(_ intensity: Double) {
        let clampedIntensity = Self.clampedBackdropIntensity(intensity)
        guard configuration.backdropIntensity != clampedIntensity else {
            return
        }

        configuration.backdropIntensity = clampedIntensity
        userDefaults.set(clampedIntensity, forKey: DefaultsKey.backdropIntensity)
        notifyChanged()
    }

    private static func clampedBackdropAlpha(_ value: Double) -> Double {
        min(max(value, minBackdropAlpha), maxBackdropAlpha)
    }

    private static func clampedBackdropIntensity(_ value: Double) -> Double {
        min(max(value, minBackdropIntensity), maxBackdropIntensity)
    }

    private static func backdropAlphaSummary(_ value: Double) -> String {
        let clampedValue = clampedBackdropAlpha(value)
        return "\(Int((clampedValue * 100).rounded()))%"
    }

    private static func backdropIntensitySummary(_ value: Double) -> String {
        let clampedValue = clampedBackdropIntensity(value)
        return "\(Int((clampedValue * 100).rounded()))%"
    }

    private func notifyChanged() {
        NotificationCenter.default.post(name: .menuBarBlurStyleChanged, object: self)
    }
}
