import AppKit

extension Notification.Name {
    static let menuBarGlassTuningChanged = Notification.Name("MenuBarGlassTuningChanged")
}

@MainActor
final class GlassTuningManager {
    enum Corner: CaseIterable {
        case topLeft
        case topRight
        case bottomLeft
        case bottomRight
    }

    struct CornerRadii: Equatable {
        var topLeft: Double
        var topRight: Double
        var bottomLeft: Double
        var bottomRight: Double

        static let zero = CornerRadii(topLeft: 0, topRight: 0, bottomLeft: 0, bottomRight: 0)

        func value(for corner: Corner) -> Double {
            switch corner {
            case .topLeft:
                return topLeft
            case .topRight:
                return topRight
            case .bottomLeft:
                return bottomLeft
            case .bottomRight:
                return bottomRight
            }
        }

        mutating func setValue(_ value: Double, for corner: Corner) {
            switch corner {
            case .topLeft:
                topLeft = value
            case .topRight:
                topRight = value
            case .bottomLeft:
                bottomLeft = value
            case .bottomRight:
                bottomRight = value
            }
        }
    }

    static let minTintWhiteAlpha: Double = -2.0
    static let maxTintWhiteAlpha: Double = 2.0
    static let minCornerRadius: Double = 0.0
    static let maxCornerRadius: Double = 100.0

    private static let tintUserDefaultsKey = "menuBarGlassTintWhiteAlpha"
    private static let customCornersEnabledUserDefaultsKey = "menuBarGlassCustomCornersEnabled"
    private static let legacyCornerRadiusUserDefaultsKey = "menuBarGlassCornerRadius"
    private static let topLeftCornerRadiusUserDefaultsKey = "menuBarGlassCornerRadiusTopLeft"
    private static let topRightCornerRadiusUserDefaultsKey = "menuBarGlassCornerRadiusTopRight"
    private static let bottomLeftCornerRadiusUserDefaultsKey = "menuBarGlassCornerRadiusBottomLeft"
    private static let bottomRightCornerRadiusUserDefaultsKey = "menuBarGlassCornerRadiusBottomRight"
    private static let persistenceDebounceInterval: TimeInterval = 0.30

    private let userDefaults: UserDefaults
    private var persistWorkItem: DispatchWorkItem?

    private(set) var tintWhiteAlpha: Double
    private(set) var customCornersEnabled: Bool
    private(set) var cornerRadii: CornerRadii
    private(set) var persistedTintWhiteAlpha: Double
    private(set) var persistedCustomCornersEnabled: Bool
    private(set) var persistedCornerRadii: CornerRadii

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults

        let storedTint = userDefaults.object(forKey: Self.tintUserDefaultsKey) as? Double ?? 0
        let sanitizedTint = Self.clampSignedTint(storedTint)
        let storedCustomCornersEnabled = userDefaults.object(forKey: Self.customCornersEnabledUserDefaultsKey) as? Bool ?? false

        let legacyCornerRadius = userDefaults.object(forKey: Self.legacyCornerRadiusUserDefaultsKey) as? Double
        let storedTopLeft = userDefaults.object(forKey: Self.topLeftCornerRadiusUserDefaultsKey) as? Double ?? legacyCornerRadius ?? 0
        let storedTopRight = userDefaults.object(forKey: Self.topRightCornerRadiusUserDefaultsKey) as? Double ?? legacyCornerRadius ?? 0
        let storedBottomLeft = userDefaults.object(forKey: Self.bottomLeftCornerRadiusUserDefaultsKey) as? Double ?? legacyCornerRadius ?? 0
        let storedBottomRight = userDefaults.object(forKey: Self.bottomRightCornerRadiusUserDefaultsKey) as? Double ?? legacyCornerRadius ?? 0

        let sanitizedCornerRadii = Self.sanitizeCornerRadii(
            CornerRadii(
                topLeft: storedTopLeft,
                topRight: storedTopRight,
                bottomLeft: storedBottomLeft,
                bottomRight: storedBottomRight
            )
        )

        tintWhiteAlpha = sanitizedTint
        customCornersEnabled = storedCustomCornersEnabled
        cornerRadii = sanitizedCornerRadii
        persistedTintWhiteAlpha = sanitizedTint
        persistedCustomCornersEnabled = storedCustomCornersEnabled
        persistedCornerRadii = sanitizedCornerRadii
    }

    deinit {
        persistWorkItem?.cancel()
    }

    func setTint(_ tintWhiteAlpha: Double) {
        let sanitized = Self.clampSignedTint(tintWhiteAlpha)
        guard sanitized != self.tintWhiteAlpha else {
            return
        }

        self.tintWhiteAlpha = sanitized
        scheduleDebouncedPersistence()
        notifyChanged()
    }

    func resetToDefaults() {
        setTint(0)
    }

    func setCustomCornersEnabled(_ enabled: Bool) {
        guard enabled != customCornersEnabled else {
            return
        }

        customCornersEnabled = enabled
        scheduleDebouncedPersistence()
        notifyChanged()
    }

    func setCornerRadius(_ cornerRadius: Double) {
        let sanitizedValue = Self.clampCornerRadius(cornerRadius)
        setCornerRadii(
            CornerRadii(
                topLeft: sanitizedValue,
                topRight: sanitizedValue,
                bottomLeft: sanitizedValue,
                bottomRight: sanitizedValue
            )
        )
    }

    func setCornerRadius(_ cornerRadius: Double, for corner: Corner) {
        let sanitizedValue = Self.clampCornerRadius(cornerRadius)
        var nextRadii = cornerRadii
        nextRadii.setValue(sanitizedValue, for: corner)
        setCornerRadii(nextRadii)
    }

    func setCornerRadii(_ cornerRadii: CornerRadii) {
        let sanitized = Self.sanitizeCornerRadii(cornerRadii)
        guard sanitized != self.cornerRadii else {
            return
        }

        self.cornerRadii = sanitized
        scheduleDebouncedPersistence()
        notifyChanged()
    }

    func resetCornerRadiusToDefault() {
        resetCornerRadiiToDefault()
    }

    func resetCornerRadiiToDefault() {
        setCornerRadii(.zero)
    }

    func flushPendingPersistence() {
        persistWorkItem?.cancel()
        persistWorkItem = nil
        persistIfNeeded()
    }

    private func scheduleDebouncedPersistence() {
        persistWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.persistIfNeeded()
        }

        persistWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.persistenceDebounceInterval, execute: workItem)
    }

    private func persistIfNeeded() {
        let sanitizedTint = Self.clampSignedTint(tintWhiteAlpha)
        let sanitizedCustomCornersEnabled = customCornersEnabled
        let sanitizedCornerRadii = Self.sanitizeCornerRadii(cornerRadii)
        guard sanitizedTint != persistedTintWhiteAlpha
            || sanitizedCustomCornersEnabled != persistedCustomCornersEnabled
            || sanitizedCornerRadii != persistedCornerRadii else {
            return
        }

        if sanitizedTint != persistedTintWhiteAlpha {
            userDefaults.set(sanitizedTint, forKey: Self.tintUserDefaultsKey)
            persistedTintWhiteAlpha = sanitizedTint
        }

        if sanitizedCustomCornersEnabled != persistedCustomCornersEnabled {
            userDefaults.set(sanitizedCustomCornersEnabled, forKey: Self.customCornersEnabledUserDefaultsKey)
            persistedCustomCornersEnabled = sanitizedCustomCornersEnabled
        }

        if sanitizedCornerRadii != persistedCornerRadii {
            userDefaults.set(sanitizedCornerRadii.topLeft, forKey: Self.topLeftCornerRadiusUserDefaultsKey)
            userDefaults.set(sanitizedCornerRadii.topRight, forKey: Self.topRightCornerRadiusUserDefaultsKey)
            userDefaults.set(sanitizedCornerRadii.bottomLeft, forKey: Self.bottomLeftCornerRadiusUserDefaultsKey)
            userDefaults.set(sanitizedCornerRadii.bottomRight, forKey: Self.bottomRightCornerRadiusUserDefaultsKey)
            userDefaults.removeObject(forKey: Self.legacyCornerRadiusUserDefaultsKey)
            persistedCornerRadii = sanitizedCornerRadii
        }
    }

    private func notifyChanged() {
        NotificationCenter.default.post(name: .menuBarGlassTuningChanged, object: self)
    }

    private static func clampSignedTint(_ value: Double) -> Double {
        min(max(value, minTintWhiteAlpha), maxTintWhiteAlpha)
    }

    private static func clampCornerRadius(_ value: Double) -> Double {
        min(max(value, minCornerRadius), maxCornerRadius)
    }

    private static func sanitizeCornerRadii(_ cornerRadii: CornerRadii) -> CornerRadii {
        CornerRadii(
            topLeft: clampCornerRadius(cornerRadii.topLeft),
            topRight: clampCornerRadius(cornerRadii.topRight),
            bottomLeft: clampCornerRadius(cornerRadii.bottomLeft),
            bottomRight: clampCornerRadius(cornerRadii.bottomRight)
        )
    }
}
