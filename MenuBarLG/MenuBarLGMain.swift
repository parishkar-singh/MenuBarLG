import AppKit

@main
enum MenuBarLGMain {
    @MainActor
    static func main() {
        // Keep the delegate in a local strong reference for the lifetime of `application.run()`.
        let application = NSApplication.shared
        let applicationDelegate = AppDelegate()

        application.delegate = applicationDelegate
        application.run()
    }
}
