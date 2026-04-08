import AppKit

extension Notification.Name {
    static let menuBarBlurStyleChanged = Notification.Name("MenuBarBlurStyleChanged")
}

@MainActor
final class BlurStyleManager {
    enum MaterialPreset: Int, CaseIterable {
        case moreLiquid = 0
        case frosted = 1
        case normal = 2

        var title: String {
            switch self {
            case .moreLiquid:
                return "More Liquid"
            case .normal:
                return "Normal"
            case .frosted:
                return "Frosted"
            }
        }
    }

    static let materialPresetUserDefaultsKey = "menuBarMaterialPreset"
    // Settings UI order is explicit and decoupled from enum raw values.
    static let materialPresetDisplayOrder: [MaterialPreset] = [.moreLiquid, .normal, .frosted]

    private let userDefaults: UserDefaults

    private(set) var materialPreset: MaterialPreset

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        if let storedValue = userDefaults.object(forKey: Self.materialPresetUserDefaultsKey) as? Int,
           let storedPreset = MaterialPreset(rawValue: storedValue) {
            materialPreset = storedPreset
        } else {
            // Persist a stable default so future launches and migrations have deterministic behavior.
            materialPreset = .moreLiquid
            userDefaults.set(MaterialPreset.moreLiquid.rawValue, forKey: Self.materialPresetUserDefaultsKey)
        }
    }

    var materialPresetStatusMessage: String {
        switch materialPreset {
        case .moreLiquid:
            return "More Liquid maximizes clarity and keeps the edge treatment minimal."
        case .normal:
            return "Normal matches the current clear-glass baseline."
        case .frosted:
            return "Frosted uses richer regular glass with a denser edge treatment."
        }
    }

    func setMaterialPreset(_ materialPreset: MaterialPreset) {
        guard self.materialPreset != materialPreset else {
            return
        }

        self.materialPreset = materialPreset
        userDefaults.set(materialPreset.rawValue, forKey: Self.materialPresetUserDefaultsKey)
        NotificationCenter.default.post(name: .menuBarBlurStyleChanged, object: self)
    }
}
