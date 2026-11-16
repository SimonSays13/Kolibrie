import AppKit
import ColibriKit
import Foundation
import Observation

/// One model as the menu shows it: its latest state plus the actions on it.
@MainActor @Observable
final class ModelController: Identifiable {
    let id: String
    private(set) var installed: InstalledModel
    private(set) var snapshot: ModelSnapshot?
    private(set) var message: String?
    private var pending: PendingAction?
    private unowned let app: AppModel

    init(installed: InstalledModel, app: AppModel) {
        id = installed.id
        self.installed = installed
        self.app = app
    }

    var state: ModelState? { snapshot?.state }
    var server: StatusReport.Server? { snapshot?.report?.server }

    var pendingAction: PendingAction? { pending }

    func update(_ installed: InstalledModel) { self.installed = installed }

    func apply(_ snapshot: ModelSnapshot) { self.snapshot = snapshot }

    func refresh() async {
        guard let runtime = app.runtime else { return }
        snapshot = await runtime.snapshot(of: installed, pending: pending)
    }

    func start() async {
        guard let runtime = app.runtime, pending == nil else { return }
        message = nil
        pending = .starting
        await refresh()
        do {
            try await runtime.start(installed)
        } catch {
            message = error.localizedDescription
        }
        pending = nil
        app.rescan()  // Colibri can move a model to another port when it starts
        await refresh()
        if message == nil, snapshot?.state == .stopped {
            message = "The server stopped straight after starting. Check the log."
        }
    }

    func stop() async {
        guard let runtime = app.runtime, pending == nil else { return }
        message = nil
        pending = .stopping
        await refresh()
        do {
            try await runtime.stop(installed)
        } catch {
            message = error.localizedDescription
        }
        pending = nil
        await refresh()
    }

    // MARK: Quick actions

    private var endpoints: Endpoints? { server?.urls ?? installed.config.urls }

    var canOpenDashboard: Bool { endpoints?.browser != nil }

    func openDashboard() {
        if let text = endpoints?.browser, let url = URL(string: text) { NSWorkspace.shared.open(url) }
    }

    func copyOpenAIURL() { copy(endpoints?.openaiBaseURL) }
    func copyAnthropicURL() { copy(endpoints?.anthropicBaseURL) }
    func copyModelID() { copy(server?.modelID) }

    var hasModelID: Bool { server?.modelID != nil }

    private func copy(_ text: String?) {
        guard let text else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
