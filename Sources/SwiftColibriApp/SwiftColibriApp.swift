import SwiftUI

@main
struct SwiftColibriApp: App {
    @State private var app = AppModel()

    init() {
        MainActor.assumeIsolated {
            _ = NSApplication.shared.setActivationPolicy(.accessory)
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(app: app)
        } label: {
            Image(systemName: app.menuBarSymbol)
        }
        .menuBarExtraStyle(.window)

        WindowGroup("Server log", id: "logs", for: String.self) { $modelID in
            LogsView(app: app, modelID: modelID)
        }
        .defaultSize(width: 760, height: 480)

        Window("About swiftColibri", id: "about") {
            AboutView(app: app)
        }
        .windowResizability(.contentSize)
    }
}
