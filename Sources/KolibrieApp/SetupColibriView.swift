import ColibriKit
import SwiftUI

/// Offered at launch when Colibri is not on this Mac.
struct SetupColibriView: View {
    let app: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow

    private var setup: ColibriSetupModel { app.colibriSetup }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(setup.colibriFound ? "Colibri needs a few things" : "Colibri is not installed").font(
                .title3.weight(.semibold))
            Text(
                "Kolibrie manages Colibri, a local inference engine for very large models. "
                    + (setup.colibriFound
                        ? "Colibri is here, but it cannot run yet."
                        : "Kolibrie can download it for you and keep it up to date.")
            )
            .fixedSize(horizontal: false, vertical: true)

            checklist
            plan
            result
            buttons
        }
        .padding(20)
        .frame(width: 520)
        .task {
            await app.refreshColibriSetup()
            await setup.loadRelease()
        }
    }

    private var checklist: some View {
        VStack(alignment: .leading, spacing: 6) {
            row(
                ok: setup.colibriFound, title: "Colibri",
                detail: setup.diagnosis.script?.path ?? "not found")
            row(
                ok: setup.prerequisites.python != nil, title: "Python 3.10 or newer",
                detail: setup.prerequisites.python?.path ?? "not found")
            row(
                ok: setup.prerequisites.hasOpenMP, title: "OpenMP (libomp)",
                detail: setup.prerequisites.hasOpenMP ? "found" : "not found; the engine needs it")
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    private func row(ok: Bool, title: String, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(ok ? .green : .orange)
            Text(title).fontWeight(.medium)
            Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder private var plan: some View {
        if setup.needsSetup, case .idle = setup.phase {
            VStack(alignment: .leading, spacing: 4) {
                Text("Setting up will:").font(.callout.weight(.medium))
                if !setup.prerequisites.isReady {
                    if setup.canInstallPackages, let command = setup.prerequisites.brewCommand {
                        bullet("run `\(command)` with Homebrew")
                    } else if let command = setup.prerequisites.brewCommand {
                        bullet(
                            "need `\(command)` first. Homebrew (brew.sh) is not installed here, so run it yourself, then choose Check again."
                        )
                    }
                }
                if !setup.colibriFound {
                    bullet(
                        "download Colibri \(setup.release?.version ?? "")"
                            + (setup.release?.macArchive?.size.map {
                                " (\(ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file)))"
                            } ?? "")
                            + " from github.com/JustVugg/colibri and check its checksum")
                    bullet("keep it in \(setup.destinationPath)")
                }
                if let error = setup.releaseError, !setup.colibriFound {
                    Text(error).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                }
            }
            .font(.callout)
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("•")
            Text(.init(text)).fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var result: some View {
        switch setup.phase {
        case .idle:
            EmptyView()
        case .working(let text):
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(text).fixedSize(horizontal: false, vertical: true)
            }
        case .done(let text):
            Label(text, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed(let text):
            Label(text, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var buttons: some View {
        HStack {
            if case .done = setup.phase {
                Spacer()
                Button("Install a model…") {
                    openWindow(id: "models")
                    dismiss()
                }
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            } else {
                Button("Check again") { Task { await app.refreshColibriSetup() } }.disabled(setup.isWorking)
                Spacer()
                Button("Not now") { dismiss() }.disabled(setup.isWorking)
                Button(setup.colibriFound ? "Install what is missing" : "Set up Colibri") {
                    Task { await app.setUpColibri() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(
                    setup.isWorking || !setup.needsSetup || (!setup.canInstallPackages && !setup.prerequisites.isReady))
            }
        }
    }
}
