import Foundation

/// A request to change an already-installed model's run configuration, via `coli setup
/// --reconfigure`. Because the model's files are already on disk, Colibri finds them and skips
/// straight to rewriting the run configuration and restarting — no re-download.
public struct ReconfigureRequest: Sendable, Equatable {
    public var modelDirectory: URL
    public var host: String
    public var port: Int
    public var settings: ColibriSettings
    public var startWhenDone: Bool

    public init(
        modelDirectory: URL, host: String, port: Int, settings: ColibriSettings, startWhenDone: Bool = true
    ) {
        self.modelDirectory = modelDirectory
        self.host = host
        self.port = port
        self.settings = settings
        self.startWhenDone = startWhenDone
    }

    /// The arguments for `coli`, after the launcher script.
    public var arguments: [String] {
        var result = [
            "setup", "--reconfigure", "--yes", "--no-browser",
            "--model-dir", modelDirectory.path,
            "--host", host, "--port", String(port),
        ]
        result += settings.flagArguments
        result.append(startWhenDone ? "--background" : "--no-start")
        return result
    }
}

extension ColiCLI {
    /// Applies new settings to a model already on disk and restarts it.
    public func reconfigure(_ request: ReconfigureRequest, home: URL) async throws {
        var environment = self.environment(setupHome: home)
        for (key, value) in request.settings.environmentOverrides { environment[key] = value }
        let output = try await ProcessRunner.run(
            executable: launcher.python,
            arguments: [launcher.script.path] + request.arguments,
            environment: environment,
            timeout: .seconds(120)
        )
        guard output.succeeded else {
            throw ColiError.commandFailed(
                command: "setup --reconfigure", exitCode: output.exitCode, output: output.combined)
        }
    }
}

extension ModelRuntime {
    /// Applies new settings to `model` and restarts it with them.
    public func reconfigure(_ model: InstalledModel, settings: ColibriSettings) async throws {
        guard let modelDirectory = model.modelDirectory else { throw ColiError.missingModelDirectory }
        let config = (try? Discovery.loadConfig(setupHome: model.setupHome)) ?? model.config
        let host = config.host ?? "127.0.0.1"
        let port = config.port ?? PortPicker.nextFree()
        let request = ReconfigureRequest(modelDirectory: modelDirectory, host: host, port: port, settings: settings)
        try await cli.reconfigure(request, home: model.setupHome)
    }
}
