import AppKit
import ColibriKit
import Foundation
import Observation

/// The app's view of every Colibri install on this Mac. It rescans the setup homes and asks
/// each model for its state on a timer; Colibri itself stays the source of truth.
@MainActor @Observable
final class AppModel {
    private(set) var controllers: [ModelController] = []
    private(set) var problems: [String] = []
    private(set) var launcherMissing = false
    private(set) var runtime: ModelRuntime?
    private var polling: Task<Void, Never>?

    init() {
        polling = Task { [weak self] in await self?.pollLoop() }
    }

    var colibriVersion: String? { runtime?.cli.launcher.installedVersion }

    var menuBarSymbol: String {
        let states = controllers.compactMap(\.state)
        if states.contains(where: { if case .failed = $0 { return true } else { return false } }) {
            return "exclamationmark.triangle"
        }
        if states.contains(.ready) { return "cpu.fill" }
        if states.contains(where: \.isTransitioning) { return "arrow.triangle.2.circlepath" }
        if states.contains(where: {
            if case .notInstalled(let p) = $0 { return p?.isRunning == true } else { return false }
        }) {
            return "arrow.down.circle"
        }
        return "cpu"
    }

    /// The bird is shown when idle or serving; other states keep a status symbol.
    var menuBarShowsBird: Bool { menuBarSymbol == "cpu" || menuBarSymbol == "cpu.fill" }

    func pollLoop() async {
        while !Task.isCancelled {
            rescan()
            await refreshAll()
            let busy = controllers.contains { $0.state?.isTransitioning == true }
            try? await Task.sleep(for: .seconds(busy ? 1 : 4))
        }
    }

    func rescan() {
        let result = Discovery.installedModels()
        problems = result.problems
        if runtime == nil {
            let hints = result.models.compactMap { $0.config.launcher }
            if let launcher = LauncherLocator.locate(hints: hints) {
                runtime = ModelRuntime(cli: ColiCLI(launcher: launcher))
                launcherMissing = false
            } else {
                launcherMissing = true
            }
        }
        let existing = Dictionary(uniqueKeysWithValues: controllers.map { ($0.id, $0) })
        controllers = result.models.map { installed in
            if let controller = existing[installed.id] {
                controller.update(installed)
                return controller
            }
            return ModelController(installed: installed, app: self)
        }
    }

    func refreshAll() async {
        guard let runtime else { return }
        let jobs = controllers.map { (id: $0.id, installed: $0.installed, pending: $0.pendingAction) }
        let snapshots = await withTaskGroup(of: (String, ModelSnapshot).self) { group in
            for job in jobs {
                group.addTask { (job.id, await runtime.snapshot(of: job.installed, pending: job.pending)) }
            }
            var results: [String: ModelSnapshot] = [:]
            for await (id, snapshot) in group { results[id] = snapshot }
            return results
        }
        for controller in controllers {
            if let snapshot = snapshots[controller.id] { controller.apply(snapshot) }
        }
    }
}
