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
}
