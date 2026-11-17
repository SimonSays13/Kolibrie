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
    private(set) var catalogue: [CatalogueEntry] = []
    private(set) var catalogueError: String?
    private(set) var catalogueLoading = false
    private(set) var includeUnfit = false
    private(set) var installErrors: [String: String] = [:]
    private var pendingInstalls: [String: Date] = [:]
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
        settleInstalls(found: result.models)
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

    // MARK: Models and installs

    /// Where new models are downloaded: the folder the existing installs use, so a new model
    /// lands beside them. `nil` leaves the choice to Colibri's default.
    var modelsDirectory: URL? {
        let roots = controllers.compactMap { $0.installed.config.modelsRoot }
        let counts = Dictionary(roots.map { ($0, 1) }, uniquingKeysWith: +)
        return counts.max { $0.value < $1.value }.map { URL(fileURLWithPath: $0.key) }
    }

    var modelsDirectoryAvailable: Bool {
        modelsDirectory.map(DiskSpace.isVolumeMounted(for:)) ?? true
    }

    var freeDiskGB: Double? {
        DiskSpace.freeGB(at: modelsDirectory ?? URL(fileURLWithPath: NSHomeDirectory()))
    }

    func setIncludeUnfit(_ value: Bool) async {
        includeUnfit = value
        await loadCatalogue()
    }

    func loadCatalogue() async {
        guard let runtime else {
            catalogueError = "Colibri's launcher was not found."
            return
        }
        catalogueLoading = true
        defer { catalogueLoading = false }
        do {
            catalogue = try await runtime.cli.catalogue(includeUnfit: includeUnfit)
            catalogueError = nil
        } catch {
            catalogueError = error.localizedDescription
        }
    }

    /// The install of this catalogue model, if there is one.
    func controller(for entry: CatalogueEntry) -> ModelController? {
        controllers.first { $0.installed.config.model?.id == entry.id }
    }

    func isStartingInstall(_ entry: CatalogueEntry) -> Bool { pendingInstalls[entry.id] != nil }

    func install(_ entry: CatalogueEntry) async {
        guard let runtime, pendingInstalls[entry.id] == nil, controller(for: entry) == nil else { return }
        guard modelsDirectoryAvailable else {
            installErrors[entry.id] = "The folder your other models use is on a drive that is not connected."
            return
        }
        installErrors[entry.id] = nil
        let port = PortPicker.nextFree(avoiding: Set(controllers.compactMap { $0.installed.port }))
        let request = InstallRequest(modelID: entry.id, port: port, modelsDirectory: modelsDirectory)
        pendingInstalls[entry.id] = Date()
        do {
            try await runtime.cli.install(request)
        } catch {
            pendingInstalls[entry.id] = nil
            installErrors[entry.id] = error.localizedDescription
        }
    }

    /// Forgets installs that have shown up as a setup home, and reports ones that never did.
    private func settleInstalls(found: [InstalledModel]) {
        let known = Set(found.compactMap { $0.config.model?.id })
        for (id, started) in pendingInstalls {
            if known.contains(id) {
                pendingInstalls[id] = nil
            } else if Date().timeIntervalSince(started) > 120 {
                pendingInstalls[id] = nil
                installErrors[id] = "The installer did not start. See colibri-\(id)/logs/install.log."
            }
        }
    }
}
