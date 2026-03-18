import SwiftUI

@main
struct GeoArtLabApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup("GeoArtLab") {
            MainWindowView(appState: appState)
                .frame(minWidth: 1260, minHeight: 820)
                .onAppear {
                    appState.start()
                }
        }
        .defaultSize(width: 1440, height: 900)
    }
}
