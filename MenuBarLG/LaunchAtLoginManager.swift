import AppKit
import ServiceManagement

extension Notification.Name {
    static let menuBarLaunchAtLoginChanged = Notification.Name("MenuBarLaunchAtLoginChanged")
}

@MainActor
final class LaunchAtLoginManager {
    private let appService: SMAppService
    private var applicationObserver: NSObjectProtocol?

    private(set) var status: SMAppService.Status

    init(appService: SMAppService = .mainApp) {
        self.appService = appService
        status = appService.status

        // Refresh when app becomes active so UI reflects user changes made in System Settings.
        applicationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshStatus()
            }
        }
    }

    deinit {
        if let applicationObserver {
            NotificationCenter.default.removeObserver(applicationObserver)
        }
    }

    var isEnabled: Bool {
        switch status {
        case .enabled, .requiresApproval:
            return true
        case .notRegistered, .notFound:
            return false
        @unknown default:
            return false
        }
    }

    var statusMessage: String {
        switch status {
        case .enabled:
            return "Launch at login is enabled."
        case .requiresApproval:
            return "Launch at login needs approval in System Settings > General > Login Items."
        case .notRegistered:
            return "Launch at login is disabled."
        case .notFound:
            return "Launch at login is unavailable for this build."
        @unknown default:
            return "Launch at login status is unavailable."
        }
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try appService.register()
        } else {
            try appService.unregister()
        }

        // Force notify so settings UI updates even if status value is unchanged by the framework.
        refreshStatus(forceNotify: true)
    }

    func refreshStatus(forceNotify: Bool = false) {
        let nextStatus = appService.status
        guard forceNotify || nextStatus != status else {
            return
        }

        status = nextStatus
        NotificationCenter.default.post(name: .menuBarLaunchAtLoginChanged, object: self)
    }
}
