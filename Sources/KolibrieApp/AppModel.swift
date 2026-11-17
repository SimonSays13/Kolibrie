import AppKit
import ColibriKit
import Foundation
import Observation

private let modelsDirectoryKey = "modelsDirectory"
private let checkForUpdatesKey = "checkForUpdatesAtLaunch"

/// The app's view of every Colibri install on this Mac. It rescans the setup homes and asks
/// each model for its state on a timer; Colibri itself stays the source of truth.
@MainActor @Observable
final class AppModel {
    private(set) var controllers: [ModelController] = []
    private(set) var problems: [String] = []
    private(set) var launcherMissing = false
    private(set) var hasScanned = false
    @ObservationIgnored
    private(set) lazy var colibriSetup = ColibriSetupModel { [weak self] in
        self?.runtimeNeedsRefresh = true
        self?.rescan()
    }
    private var runtimeNeedsRefresh = false
    let updates = UpdatesModel()
    private(set) var checksForUpdatesAtLaunch =
        UserDefaults.standard.object(forKey: checkForUpdatesKey) as? Bool ?? true
    private(set) var runtime: ModelRuntime?
    private(set) var catalogue: [CatalogueEntry] = []
    private(set) var catalogueError: String?
    private(set) var catalogueLoading = false
    private(set) var includeUnfit = false
    private(set) var installErrors: [String: String] = [:]
    private var pendingInstalls: [String: Date] = [:]
    private(set) var modelsDirectoryPreference: String? = UserDefaults.standard.string(forKey: modelsDirectoryKey)
    private var polling: Task<Void, Never>?
    private(set) var installedHarnesses: Set<Harness> = []

    init() {
        polling = Task { [weak self] in await self?.pollLoop() }
        Task { [weak self] in await self?.detectHarnesses() }
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

    func detectHarnesses() async {
        var found: Set<Harness> = []
        for harness in Harness.allCases where await HarnessDetector.isInstalled(harness) {
            found.insert(harness)
        }
        installedHarnesses = found
    }

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
        if runtime == nil || runtimeNeedsRefresh {
            runtimeNeedsRefresh = false
            let hints = result.models.compactMap { $0.config.launcher }
            if let launcher = LauncherLocator.locate(hints: hints) {
                runtime = ModelRuntime(cli: ColiCLI(launcher: launcher))
                launcherMissing = false
            } else {
                launcherMissing = true
            }
        }
        settleInstalls(found: result.models)
        hasScanned = true
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

    // MARK: Setting Colibri up

    private var launcherHints: [String] { Discovery.installedModels().models.compactMap { $0.config.launcher } }

    func refreshColibriSetup() async { await colibriSetup.refresh(hints: launcherHints) }

    func setUpColibri() async { await colibriSetup.setUp(hints: launcherHints) }

    /// Waits for the first look at this Mac's installs, then reports whether Colibri is missing.
    func colibriIsMissingAtLaunch() async -> Bool {
        while !hasScanned { try? await Task.sleep(for: .milliseconds(100)) }
        return launcherMissing
    }

    // MARK: Updates

    func setChecksForUpdatesAtLaunch(_ value: Bool) {
        checksForUpdatesAtLaunch = value
        UserDefaults.standard.set(value, forKey: checkForUpdatesKey)
    }

    func checkForUpdates() async {
        await updates.check(installedColibri: colibriVersion, installedKolibrie: AppInfo.versionNumber)
    }

    /// True when Colibri is the copy Kolibrie installed, which is the only one it will replace.
    var colibriIsManaged: Bool {
        guard let script = runtime?.cli.launcher.script.path else { return false }
        return script.hasPrefix(ColibriInstaller.defaultDestination().path + "/")
    }

    var runningModelNames: [String] {
        controllers.filter { $0.state == .ready }.map { $0.installed.displayName }
    }

    /// Stops running models, installs the new Colibri, and starts the same models again.
    func updateColibri() async {
        guard let release = updates.colibriRelease, colibriIsManaged, !updates.colibriPhase.isWorking else { return }
        let running = controllers.filter { $0.state == .ready }
        do {
            for controller in running {
                updates.setColibriPhase(.working("Stopping \(controller.installed.displayName)…"))
                await controller.stop()
                if let message = controller.message {
                    throw ColiError.commandFailed(command: "stop", exitCode: 1, output: message)
                }
            }
            updates.setColibriPhase(.working("Downloading Colibri \(release.version)…"))
            try await ColibriInstaller().install(release) { step in
                let text: String
                switch step {
                case .downloading: text = "Downloading Colibri \(release.version)…"
                case .verifying: text = "Checking the download against its published checksum…"
                case .unpacking: text = "Unpacking…"
                case .finishing: text = "Putting Colibri in place…"
                }
                Task { @MainActor in self.updates.setColibriPhase(.working(text)) }
            }
            runtimeNeedsRefresh = true
            rescan()
            for controller in running {
                updates.setColibriPhase(.working("Starting \(controller.installed.displayName) again…"))
                await controller.start()
            }
            updates.markColibriUpdated(to: colibriVersion ?? release.version)
        } catch {
            updates.setColibriPhase(.failed(error.localizedDescription))
        }
    }

    /// Downloads the new Kolibrie, then quits so a helper can swap it in and open it.
    func updateKolibrie() async {
        guard let release = updates.kolibrieRelease, AppInfo.canSelfUpdate, !updates.kolibriePhase.isWorking else {
            return
        }
        let app = Bundle.main.bundleURL
        do {
            let staged = try await AppUpdater().stage(release, replacing: app) { step in
                let text: String
                switch step {
                case .downloading: text = "Downloading Kolibrie \(release.version)…"
                case .verifying: text = "Checking the download against its published checksum…"
                case .unpacking, .finishing: text = "Unpacking…"
                }
                Task { @MainActor in self.updates.setKolibriePhase(.working(text)) }
            }
            updates.setKolibriePhase(.working("Restarting Kolibrie…"))
            try await AppUpdater.relaunch(
                after: ProcessInfo.processInfo.processIdentifier, replacing: app, with: staged)
            NSApplication.shared.terminate(nil)
        } catch {
            updates.setKolibriePhase(.failed(error.localizedDescription))
        }
    }

    // MARK: Models and installs

    /// Where new models are downloaded: the folder the existing installs use, so a new model
    /// lands beside them. `nil` leaves the choice to Colibri's default.
    var modelsDirectory: URL? {
        if let chosen = modelsDirectoryPreference { return URL(fileURLWithPath: chosen) }
        return automaticModelsDirectory
    }

    /// The folder the existing installs use most, when no folder has been chosen in Settings.
    var automaticModelsDirectory: URL? {
        let roots = controllers.compactMap { $0.installed.config.modelsRoot }
        let counts = Dictionary(roots.map { ($0, 1) }, uniquingKeysWith: +)
        return counts.max { $0.value < $1.value }.map { URL(fileURLWithPath: $0.key) }
    }

    /// Chooses where new models are downloaded; `nil` goes back to the automatic folder.
    func setModelsDirectory(_ url: URL?) {
        modelsDirectoryPreference = url?.path
        UserDefaults.standard.set(url?.path, forKey: modelsDirectoryKey)
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
