import SwiftUI

@main
struct KolibrieApp: App {
    @State private var app = AppModel()

    init() {
        MainActor.assumeIsolated {
            _ = NSApplication.shared.setActivationPolicy(.accessory)
            if let icon = Branding.icon { NSApplication.shared.applicationIconImage = icon }
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(app: app)
        } label: {
            if app.menuBarShowsBird, let bird = Branding.menuBarBird(active: app.menuBarSymbol == "cpu.fill") {
                Image(nsImage: bird)
            } else {
                Image(systemName: app.menuBarSymbol)
            }
        }
        .menuBarExtraStyle(.window)

        WindowGroup("Server log", id: "logs", for: String.self) { $modelID in
            LogsView(app: app, modelID: modelID)
        }
        .defaultSize(width: 760, height: 480)

        Window("About Kolibrie", id: "about") {
            AboutView(app: app)
        }
        .windowResizability(.contentSize)
    }
}
