import ColibriKit
import SwiftUI

/// Colibri's catalogue, checked against this Mac, with install buttons.
struct ModelsView: View {
    let app: AppModel
    @State private var confirming: CatalogueEntry?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(minWidth: 560, minHeight: 420)
        .task { await app.loadCatalogue() }
        .confirmationDialog(
            confirming.map { "Install \($0.name)?" } ?? "", isPresented: confirmationBinding, presenting: confirming
        ) { entry in
            Button("Download \(sizeText(entry.downloadGB))") { Task { await app.install(entry) } }
            Button("Cancel", role: .cancel) {}
        } message: { entry in
            Text(
                "Colibri downloads the model, builds or fetches its engine and starts the server. You can follow it from the menu bar."
            )
        }
    }

    private var confirmationBinding: Binding<Bool> {
        Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } })
    }

    private var header: some View {
        HStack {
            Text("Models").font(.title2.weight(.semibold))
            Spacer()
            Toggle(
                "Show models that do not fit",
                isOn: Binding(
                    get: { app.includeUnfit },
                    set: { value in Task { await app.setIncludeUnfit(value) } })
            )
            .toggleStyle(.checkbox)
            Button {
                Task { await app.loadCatalogue() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Reload the catalogue")
            .disabled(app.catalogueLoading)
        }
        .padding(12)
    }

    @ViewBuilder private var content: some View {
        if let error = app.catalogueError, app.catalogue.isEmpty {
            Text(error).foregroundStyle(.secondary).padding().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if app.catalogue.isEmpty {
            ProgressView("Reading the catalogue…").frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(app.catalogue) { entry in
                CatalogueRow(app: app, entry: entry) { confirming = entry }
            }
            .listStyle(.inset)
        }
    }

    private var footer: some View {
        HStack {
            if !app.modelsDirectoryAvailable {
                Label("The drive that holds your models is not connected.", systemImage: "externaldrive.badge.xmark")
                    .foregroundStyle(.orange)
            } else {
                Text(
                    "Downloads go to \(app.modelsDirectory?.path ?? "~/colibri-models")"
                        + (app.freeDiskGB.map { String(format: " · %.0f GB free", $0) } ?? ""))
            }
            Spacer()
        }
        .font(.caption).foregroundStyle(.secondary)
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    private func sizeText(_ gb: Double?) -> String { gb.map { String(format: "%.1f GB", $0) } ?? "model" }
}

private struct CatalogueRow: View {
    let app: AppModel
    let entry: CatalogueEntry
    let install: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(entry.name).fontWeight(.medium)
                    if entry.recommended == true {
                        Text("Recommended").font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(.tint.opacity(0.2), in: Capsule())
                    }
                }
                if let summary = entry.summary { Text(summary).font(.callout).foregroundStyle(.secondary) }
                Text(details).font(.caption).foregroundStyle(.secondary)
                if let reason = entry.reason {
                    Text(reason).font(.caption).foregroundStyle(entry.fits == false ? .orange : .secondary)
                }
                if let warning = DiskSpace.warning(downloadGB: entry.downloadGB, freeGB: app.freeDiskGB),
                    app.controller(for: entry) == nil
                {
                    Text(warning).font(.caption).foregroundStyle(.orange)
                }
                if let error = app.installErrors[entry.id] {
                    Text(error).font(.caption).foregroundStyle(.red).lineLimit(3)
                }
                if let controller = app.controller(for: entry), case .notInstalled(let progress?)? = controller.state {
                    ProgressView(value: progress.fraction)
                    Text(controller.downloadSummary(progress)).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.vertical, 4)
    }

    private var details: String {
        var parts: [String] = []
        if let size = entry.downloadGB { parts.append(String(format: "%.1f GB download", size)) }
        if let min = entry.ramMinGB { parts.append(String(format: "%.0f GB RAM minimum", min)) }
        if let runs = entry.runs { parts.append(runs) }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private var trailing: some View {
        if let controller = app.controller(for: entry) {
            HStack(spacing: 6) {
                MetalBadge(availability: controller.metalAvailability)
                Text(controller.state?.label ?? "Installed").font(.callout).foregroundStyle(.secondary)
            }
        } else if app.isStartingInstall(entry) {
            ProgressView().controlSize(.small)
        } else {
            Button("Install…", action: install)
                .disabled(!app.modelsDirectoryAvailable || app.runtime == nil)
        }
    }
}
