import ColibriKit
import SwiftUI

/// Kolibrie's own settings.
struct SettingsView: View {
    let app: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Model location").font(.headline)
                Text("New models are downloaded into this folder. Models you already have stay where they are.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Text(app.modelsDirectory?.path ?? "Colibri's default (~/colibri-models)")
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(1).truncationMode(.middle)
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                    Button("Choose…") { choose() }
                    Button("Use automatic") { app.setModelsDirectory(nil) }
                        .disabled(app.modelsDirectoryPreference == nil)
                }
                caption
            }
        }
        .padding(20)
        .frame(width: 560)
    }

    @ViewBuilder private var caption: some View {
        if !app.modelsDirectoryAvailable {
            Label("The drive that holds this folder is not connected.", systemImage: "externaldrive.badge.xmark")
                .font(.caption).foregroundStyle(.orange)
        } else {
            Text(
                (app.modelsDirectoryPreference == nil
                    ? "Chosen automatically from the folder your existing models use."
                    : "Chosen in Settings.")
                    + (app.freeDiskGB.map { String(format: " %.0f GB free.", $0) } ?? "")
            )
            .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.title = "Choose where new models are downloaded"
        panel.prompt = "Choose"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        if let current = app.modelsDirectory {
            var start = current
            while !FileManager.default.fileExists(atPath: start.path), start.pathComponents.count > 1 {
                start.deleteLastPathComponent()
            }
            panel.directoryURL = start
        }
        NSApplication.shared.activate()
        if panel.runModal() == .OK, let url = panel.url { app.setModelsDirectory(url) }
    }
}
