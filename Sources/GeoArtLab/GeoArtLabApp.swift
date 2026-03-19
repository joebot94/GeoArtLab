import AppKit
import SwiftUI

@MainActor
final class GeoArtLabApplication: NSObject, NSApplicationDelegate {
    private let appState = AppState()
    private var mainWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)

        let rootView = MainWindowView(appState: appState)
            .frame(minWidth: 1260, minHeight: 820)

        let hosting = NSHostingController(rootView: rootView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1440, height: 900),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.center()
        window.title = "GeoArtLab"
        window.contentViewController = hosting
        window.makeKeyAndOrderFront(nil)

        self.mainWindow = window
        appState.start()
        NSApp.activate(ignoringOtherApps: true)
    }
}
