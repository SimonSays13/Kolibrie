import ColibriKit
import SwiftUI

/// Offered at launch when Colibri or Kolibrie has a newer release.
struct UpdatesView: View {
    let app: AppModel
    @Environment(\.dismiss) private var dismiss
    private var updates: UpdatesModel { app.updates }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(updates.hasUpdates ? "Updates are available" : "Updates").font(.title3.weight(.semibold))

            component(
                name: "Kolibrie", installed: AppInfo.versionNumber, status: updates.kolibrie,
                phase: updates.kolibriePhase, release: updates.kolibrieRelease
            ) {
                if AppInfo.canSelfUpdate {
                    Button("Update and restart") { Task { await app.updateKolibrie() } }
                } else if let page = updates.kolibrieRelease?.pageURL {
                    Link("Open release page", destination: page)
                }
            } note: {
                if !AppInfo.canSelfUpdate, updates.kolibrie.isAvailable {
                    "This copy is running from a build folder, so it cannot replace itself. Pull the new source and build it, or install the release."
                } else {
                    nil
                }
            }

            component(
                name: "Colibri", installed: app.colibriVersion, status: updates.colibri,
                phase: updates.colibriPhase, release: updates.colibriRelease
            ) {
                if app.colibriIsManaged {
                    Button(app.runningModelNames.isEmpty ? "Update" : "Update and restart models") {
                        Task { await app.updateColibri() }
                    }
                } else if let page = updates.colibriRelease?.pageURL {
                    Link("Open release page", destination: page)
                }
            } note: {
                if updates.colibri.isAvailable {
                    if !app.colibriIsManaged {
                        "This Colibri is not the copy Kolibrie installed, so it will not change it. If it is a git checkout, `git pull` updates it."
                    } else if !app.runningModelNames.isEmpty {
                        "Running models (\(app.runningModelNames.joined(separator: ", "))) are stopped first and started again afterwards."
                    } else {
                        nil
                    }
                } else {
                    nil
                }
            }

            HStack {
                Button("Check again") { Task { await app.checkForUpdates() } }.disabled(updates.isChecking)
                if updates.isChecking { ProgressView().controlSize(.small) }
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    private func component<Action: View>(
        name: String, installed: String?, status: UpdatesModel.Status, phase: UpdatesModel.Phase,
        release: ColibriRelease?, @ViewBuilder action: () -> Action, note: () -> String?
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(name).font(.headline)
                Text(installed.map { "version \($0)" } ?? "not installed").foregroundStyle(.secondary)
                Spacer()
                if status.isAvailable, !phase.isWorking { action() }
            }
            switch status {
            case .unknown: Text("Not checked.").foregroundStyle(.secondary)
            case .checking: ProgressView().controlSize(.small)
            case .upToDate: Label("Up to date", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            case .available(let version):
                HStack {
                    Label("Version \(version) is available", systemImage: "arrow.down.circle.fill").foregroundStyle(
                        .tint)
                    if let page = release?.pageURL { Link("Release notes", destination: page).font(.callout) }
                }
            case .notPublished:
                Text("No release has been published yet.").foregroundStyle(.secondary)
            case .failed(let reason):
                Label(reason, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let text = note() {
                Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            switch phase {
            case .idle: EmptyView()
            case .working(let text):
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(text).fixedSize(horizontal: false, vertical: true)
                }
            case .failed(let text):
                Label(text, systemImage: "xmark.octagon.fill").foregroundStyle(.red).fixedSize(
                    horizontal: false, vertical: true)
            case .done(let text): Label(text, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}
