import AppKit
import ColibriAPI
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
    private(set) var isDeleting = false
    private(set) var isChangingDownload = false
    private var estimator = DownloadEstimator()
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

    func apply(_ snapshot: ModelSnapshot) {
        self.snapshot = snapshot
        recordDownload(snapshot.state)
    }

    func refresh() async {
        guard let runtime = app.runtime else { return }
        let fresh = await runtime.snapshot(of: installed, pending: pending)
        snapshot = fresh
        recordDownload(fresh.state)
    }

    // MARK: Downloads

    /// Feeds the speed estimate; it starts again whenever the download is not running.
    private func recordDownload(_ state: ModelState) {
        if case .notInstalled(let progress?) = state, progress.isRunning {
            estimator.add(bytes: progress.bytesDone, at: Date.timeIntervalSinceReferenceDate)
        } else {
            estimator.reset()
        }
    }

    func downloadETA(_ progress: DownloadProgress) -> Double? {
        estimator.etaSeconds(remainingBytes: progress.bytesTotal - progress.bytesDone)
    }

    func downloadSummary(_ progress: DownloadProgress) -> String {
        progress.summary(rate: estimator.bytesPerSecond, eta: downloadETA(progress))
    }

    var isDownloadRunning: Bool {
        if case .notInstalled(let progress?)? = state { return progress.isRunning }
        return false
    }

    var isDownloadPaused: Bool {
        if case .notInstalled(let progress?)? = state { return !progress.isRunning }
        return false
    }

    func pauseDownload() async {
        guard let runtime = app.runtime, !isChangingDownload else { return }
        message = nil
        isChangingDownload = true
        defer { isChangingDownload = false }
        do {
            try await runtime.pauseDownload(installed, report: snapshot?.report)
        } catch {
            message = error.localizedDescription
        }
        await refresh()
    }

    func resumeDownload() async {
        guard let runtime = app.runtime, !isChangingDownload else { return }
        message = nil
        isChangingDownload = true
        defer { isChangingDownload = false }
        do {
            try await runtime.resumeDownload(installed)
        } catch {
            message = error.localizedDescription
        }
        try? await Task.sleep(for: .seconds(2))
        await refresh()
    }

    // MARK: Deleting

    var canDelete: Bool {
        guard !isDeleting, pending == nil else { return false }
        switch state {
        case .starting?, .stopping?: return false
        default: return true
        }
    }

    func deletionPlan() -> DeletionPlan {
        ModelDeletion.plan(for: installed, among: app.controllers.map(\.installed))
    }

    /// Stops the server or download, removes the files and the setup folder, and rescans.
    func delete(_ plan: DeletionPlan) async -> Bool {
        guard let runtime = app.runtime, canDelete else { return false }
        message = nil
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await runtime.delete(installed, plan: plan, snapshot: snapshot)
        } catch {
            message = error.localizedDescription
            return false
        }
        app.rescan()
        return true
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

    // MARK: Harness launching

    var canLaunchHarness: Bool { state == .ready }

    var availableHarnesses: [Harness] {
        app.installedHarnesses.sorted { $0.displayName < $1.displayName }
    }

    private func harnessEndpoint() async -> HarnessEndpoint? {
        guard let modelID = server?.modelID ?? installed.config.model?.id else { return nil }
        let openaiURL = endpoints?.openaiBaseURL.flatMap(URL.init(string:))
        let anthropicURL = endpoints?.anthropicBaseURL.flatMap(URL.init(string:))
        var contextLength: Int?
        if let openaiURL {
            let models = try? await ServerProbe(baseURL: openaiURL).models()
            contextLength = models?.first(where: { $0.id == modelID })?.contextLength
        }
        return HarnessEndpoint(
            openaiBaseURL: openaiURL, anthropicBaseURL: anthropicURL, modelID: modelID, contextLength: contextLength)
    }

    func launch(_ harness: Harness) async {
        message = nil
        guard let endpoint = await harnessEndpoint() else {
            message = "No model ID is available yet to launch \(harness.displayName)."
            return
        }
        do {
            try HarnessRunner.launch(harness, endpoint: endpoint)
        } catch {
            message = error.localizedDescription
        }
    }

    private func copy(_ text: String?) {
        guard let text else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
