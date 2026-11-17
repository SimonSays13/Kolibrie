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
            MenuBarLabel(app: app)
        }
        .menuBarExtraStyle(.window)

        WindowGroup("Server log", id: "logs", for: String.self) { $modelID in
            LogsView(app: app, modelID: modelID)
        }
        .defaultSize(width: 760, height: 480)

        Window("Set up Colibri", id: "setup-colibri") {
            SetupColibriView(app: app)
        }
        .windowResizability(.contentSize)

        Window("Settings", id: "settings") {
            SettingsView(app: app)
        }
        .windowResizability(.contentSize)

        WindowGroup("Delete model", id: "delete", for: String.self) { $modelID in
            DeleteModelView(app: app, modelID: modelID)
        }
        .windowResizability(.contentSize)

        Window("Models", id: "models") {
            ModelsView(app: app)
        }
        .defaultSize(width: 640, height: 560)

        Window("About Kolibrie", id: "about") {
            AboutView(app: app)
        }
        .windowResizability(.contentSize)
    }
}

/// The menu bar icon. It also offers to set Colibri up when the app opens and Colibri is missing.
private struct MenuBarLabel: View {
    let app: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if app.menuBarShowsBird, let bird = Branding.menuBarBird(active: app.menuBarSymbol == "cpu.fill") {
                Image(nsImage: bird)
            } else {
                Image(systemName: app.menuBarSymbol)
            }
        }
        .task {
            if await app.colibriIsMissingAtLaunch() {
                openWindow(id: "setup-colibri")
                NSApplication.shared.activate()
            }
        }
    }
}
