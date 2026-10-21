import AppKit
import ScreenEdgesCore

@main
@MainActor
enum ScreenEdgesApp {
    private static var controller: StatusController?

    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let status = StatusController()
        controller = status
        status.start()
        app.run()
    }
}
