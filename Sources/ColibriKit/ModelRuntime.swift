import Foundation

/// A model's state and the status report it came from.
public struct ModelSnapshot: Sendable, Equatable {
    public var state: ModelState
    public var report: StatusReport?
}

/// Reads and changes the state of one model through `coli`.
public struct ModelRuntime: Sendable {
    public let cli: ColiCLI

    public init(cli: ColiCLI) { self.cli = cli }

    public func snapshot(of model: InstalledModel, pending: PendingAction? = nil) async -> ModelSnapshot {
        do {
            let report = try await cli.status(setupHome: model.setupHome)
            let directory = report.setup?.modelDir ?? model.config.modelDir
            let exists = directory.map { FileManager.default.fileExists(atPath: $0) } ?? true
            let state = ModelState.derive(
                config: model.config, report: report, modelDirectoryExists: exists, pending: pending)
            return ModelSnapshot(state: state, report: report)
        } catch {
            return ModelSnapshot(state: .failed(error.localizedDescription), report: nil)
        }
    }

    public func start(_ model: InstalledModel) async throws {
        let output = try await cli.start(setupHome: model.setupHome)
        guard output.succeeded else {
            throw ColiError.commandFailed(command: "start", exitCode: output.exitCode, output: output.combined)
        }
    }

    public func stop(_ model: InstalledModel) async throws {
        // Colibri can move a model to a new port when it starts, so read the file again.
        let config = (try? Discovery.loadConfig(setupHome: model.setupHome)) ?? model.config
        guard let port = config.port else { throw ColiError.missingPort }
        let output = try await cli.stop(setupHome: model.setupHome, port: port)
        guard output.succeeded else {
            throw ColiError.commandFailed(command: "stop", exitCode: output.exitCode, output: output.combined)
        }
    }

    /// Stops the download that is running for `model`. Colibri keeps the partial files.
    public func pauseDownload(_ model: InstalledModel, report: StatusReport?) async throws {
        guard let install = report?.install, install.running == true, let pid = install.pid else {
            throw ColiError.installNotRunning
        }
        try await InstallProcess.stop(pid: pid)
    }

    /// Runs the install again with the model's saved settings; Colibri carries on from the partial files.
    public func resumeDownload(_ model: InstalledModel) async throws {
        guard let id = model.config.model?.id else { throw ColiError.unparsableOutput(command: "setup") }
        let config = (try? Discovery.loadConfig(setupHome: model.setupHome)) ?? model.config
        let port = config.port ?? PortPicker.nextFree()
        let request = InstallRequest(
            modelID: id, port: port, modelsDirectory: config.modelsRoot.map { URL(fileURLWithPath: $0) })
        try await cli.install(request, home: model.setupHome)
    }

    /// Stops the server or download if one is running, then removes what `plan` lists.
    public func delete(_ model: InstalledModel, plan: DeletionPlan, snapshot: ModelSnapshot?) async throws {
        if snapshot?.state == .ready { try await stop(model) }
        if snapshot?.report?.install?.running == true {
            try await pauseDownload(model, report: snapshot?.report)
        }
        try await Task.detached(priority: .userInitiated) { try ModelDeletion.delete(plan) }.value
    }
}
