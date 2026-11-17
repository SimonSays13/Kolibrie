import ColibriKit
import SwiftUI

/// Asks before deleting a model, and says exactly what will be removed.
struct DeleteModelView: View {
    let app: AppModel
    let modelID: String?
    @Environment(\.dismiss) private var dismiss
    @State private var plan: DeletionPlan?
    @State private var sizeText: String?
    @State private var working = false

    private var controller: ModelController? { app.controllers.first { $0.id == modelID } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let controller {
                Text("Delete \(controller.installed.displayName)?").font(.headline)
                if let plan {
                    details(plan)
                } else {
                    ProgressView().controlSize(.small)
                }
                if let message = controller.message {
                    Text(message).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    Spacer()
                    Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                    if working || controller.isDeleting {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Delete", role: .destructive) { delete(controller) }
                            .disabled(plan == nil || plan?.blocked != nil || !controller.canDelete)
                    }
                }
            } else {
                Text("This model is no longer installed.")
                HStack {
                    Spacer()
                    Button("Close") { dismiss() }
                }
            }
        }
        .padding(20)
        .frame(width: 480)
        .task(id: modelID) { await load() }
    }

    @ViewBuilder private func details(_ plan: DeletionPlan) -> some View {
        if let blocked = plan.blocked {
            Text(blocked).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                if let directory = plan.modelDirectory {
                    Text(
                        "This permanently deletes the downloaded model files\(sizeText.map { " (\($0))" } ?? ""), and cannot be undone:"
                    )
                    .fixedSize(horizontal: false, vertical: true)
                    path(directory.path)
                }
                Text(
                    plan.modelDirectory == nil
                        ? "This removes the install's settings and logs:" : "It also removes the settings and logs:")
                path(plan.setupHome.path)
                if let note = plan.filesNote {
                    Text(note).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                if controller?.state == .ready {
                    Text("The server is running and will be stopped first.").font(.callout).foregroundStyle(.secondary)
                } else if controller?.isDownloadRunning == true {
                    Text("The download is running and will be stopped first.").font(.callout).foregroundStyle(
                        .secondary)
                }
            }
        }
    }

    private func path(_ text: String) -> some View {
        Text(text).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
            .lineLimit(2).truncationMode(.middle)
    }

    private func load() async {
        guard let controller else { return }
        let plan = controller.deletionPlan()
        self.plan = plan
        if let directory = plan.modelDirectory {
            let bytes = await Task.detached(priority: .utility) { ModelDeletion.size(of: directory) }.value
            sizeText = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        }
    }

    private func delete(_ controller: ModelController) {
        guard let plan else { return }
        working = true
        Task {
            let deleted = await controller.delete(plan)
            working = false
            if deleted { dismiss() }
        }
    }
}
