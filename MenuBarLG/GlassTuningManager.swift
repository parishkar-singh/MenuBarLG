import AppKit

extension Notification.Name {
    static let menuBarGlassTuningChanged = Notification.Name("MenuBarGlassTuningChanged")
}

@MainActor
final class GlassTuningManager {
    struct PresetTuning: Codable, Equatable {
        var alphaValue: Double
        var style: String
        // Signed tint strength: +1 means white tint, -1 means black tint.
        var tintWhiteAlpha: Double
    }

    struct TuningFile: Codable, Equatable {
        var moreLiquid: PresetTuning
        var normal: PresetTuning
        var frosted: PresetTuning
    }

    static let defaultTuningFile = TuningFile(
        moreLiquid: PresetTuning(alphaValue: 0.90, style: "clear", tintWhiteAlpha: 0.00),
        normal: PresetTuning(alphaValue: 0.90, style: "regular", tintWhiteAlpha: 0.05),
        frosted: PresetTuning(alphaValue: 1.00, style: "regular", tintWhiteAlpha: 0.50)
    )

    private static let userDefaultsKey = "menuBarGlassTuningFileV1"
    private static let persistenceDebounceInterval: TimeInterval = 0.30

    private let userDefaults: UserDefaults
    private var persistWorkItem: DispatchWorkItem?

    // Live state drives immediate on-screen updates while the user drags sliders.
    private(set) var tuningFile: TuningFile
    // Persisted snapshot lets us skip redundant writes and keep writes coalesced.
    private(set) var persistedTuningFile: TuningFile

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults

        let initial = Self.loadPersistedTuningFile(from: userDefaults)
        tuningFile = initial
        persistedTuningFile = initial
    }

    deinit {
        persistWorkItem?.cancel()
    }

    func tuning(for preset: BlurStyleManager.MaterialPreset) -> PresetTuning {
        switch preset {
        case .moreLiquid:
            return tuningFile.moreLiquid
        case .normal:
            return tuningFile.normal
        case .frosted:
            return tuningFile.frosted
        }
    }

    func alpha(for preset: BlurStyleManager.MaterialPreset) -> Double {
        tuning(for: preset).alphaValue
    }

    func tint(for preset: BlurStyleManager.MaterialPreset) -> Double {
        tuning(for: preset).tintWhiteAlpha
    }

    func setAlpha(_ alphaValue: Double, for preset: BlurStyleManager.MaterialPreset) {
        mutateLiveTuning(for: preset) { tuning in
            tuning.alphaValue = Self.clamp01(alphaValue)
            tuning.style = Self.defaultStyle(for: preset)
        }
    }

    func setTint(_ tintWhiteAlpha: Double, for preset: BlurStyleManager.MaterialPreset) {
        mutateLiveTuning(for: preset) { tuning in
            tuning.tintWhiteAlpha = Self.clampSignedTint(tintWhiteAlpha)
            tuning.style = Self.defaultStyle(for: preset)
        }
    }

    func resetToDefaults() {
        setLiveTuningFile(Self.defaultTuningFile, notify: true, schedulePersistence: true)
    }

    // Persist any pending writes immediately (used when the app is terminating).
    func flushPendingPersistence() {
        persistWorkItem?.cancel()
        persistWorkItem = nil
        persistIfNeeded()
    }

    private func mutateLiveTuning(
        for preset: BlurStyleManager.MaterialPreset,
        mutation: (inout PresetTuning) -> Void
    ) {
        var updated = tuningFile

        switch preset {
        case .moreLiquid:
            mutation(&updated.moreLiquid)
        case .normal:
            mutation(&updated.normal)
        case .frosted:
            mutation(&updated.frosted)
        }

        setLiveTuningFile(updated, notify: true, schedulePersistence: true)
    }

    private func setLiveTuningFile(_ tuningFile: TuningFile, notify: Bool, schedulePersistence: Bool) {
        // Normalize untrusted input before publishing it to renderer paths.
        let sanitized = Self.sanitized(tuningFile)
        let didChange = sanitized != self.tuningFile
        self.tuningFile = sanitized

        if schedulePersistence {
            scheduleDebouncedPersistence()
        }

        guard notify, didChange else {
            return
        }

        NotificationCenter.default.post(name: .menuBarGlassTuningChanged, object: self)
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
        let sanitized = Self.sanitized(tuningFile)
        guard sanitized != persistedTuningFile else {
            return
        }

        do {
            let data = try JSONEncoder().encode(sanitized)
            userDefaults.set(data, forKey: Self.userDefaultsKey)
            persistedTuningFile = sanitized
        } catch {
            NSLog("MenuBarLG: Failed to persist glass tuning: %@", error.localizedDescription)
        }
    }

    private static func loadPersistedTuningFile(from userDefaults: UserDefaults) -> TuningFile {
        guard let data = userDefaults.data(forKey: Self.userDefaultsKey) else {
            let defaults = Self.defaultTuningFile
            if let encodedDefaults = try? JSONEncoder().encode(defaults) {
                userDefaults.set(encodedDefaults, forKey: Self.userDefaultsKey)
            }

            return defaults
        }

        do {
            let decoded = try JSONDecoder().decode(TuningFile.self, from: data)
            return sanitized(decoded)
        } catch {
            NSLog("MenuBarLG: Failed to decode persisted glass tuning: %@", error.localizedDescription)
            return Self.defaultTuningFile
        }
    }

    private static func sanitized(_ file: TuningFile) -> TuningFile {
        TuningFile(
            moreLiquid: sanitized(file.moreLiquid),
            normal: sanitized(file.normal),
            frosted: sanitized(file.frosted)
        )
    }

    private static func sanitized(_ preset: PresetTuning) -> PresetTuning {
        PresetTuning(
            alphaValue: clamp01(preset.alphaValue),
            style: normalizedStyle(preset.style),
            tintWhiteAlpha: clampSignedTint(preset.tintWhiteAlpha)
        )
    }

    private static func normalizedStyle(_ style: String) -> String {
        style.lowercased() == "regular" ? "regular" : "clear"
    }

    private static func defaultStyle(for preset: BlurStyleManager.MaterialPreset) -> String {
        switch preset {
        case .moreLiquid:
            return "clear"
        case .normal, .frosted:
            return "regular"
        }
    }

    private static func clamp01(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    private static func clampSignedTint(_ value: Double) -> Double {
        min(max(value, -1), 1)
    }
}
