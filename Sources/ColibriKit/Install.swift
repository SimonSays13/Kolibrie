import Foundation

/// A request to install a catalogue model with `coli setup`.
public struct InstallRequest: Sendable, Equatable {
    public var modelID: String
    public var port: Int
    /// Where Colibri downloads models. `nil` keeps Colibri's default, `~/colibri-models`.
    public var modelsDirectory: URL?
    /// Start the server once the download has finished.
    public var startWhenDone: Bool

    public init(modelID: String, port: Int, modelsDirectory: URL? = nil, startWhenDone: Bool = true) {
        self.modelID = modelID
        self.port = port
        self.modelsDirectory = modelsDirectory
        self.startWhenDone = startWhenDone
    }

    /// The setup home for this model, next to any others in Application Support.
    public func setupHome(root: URL = Discovery.defaultRoot) -> URL {
        root.appendingPathComponent("colibri-\(modelID)", isDirectory: true)
    }

    /// The arguments for `coli`, after the launcher script.
    public var arguments: [String] {
        var result = ["setup", "--yes", "--no-browser", "--model", modelID, "--port", String(port)]
        if let modelsDirectory { result += ["--dir", modelsDirectory.path] }
        result.append(startWhenDone ? "--background" : "--no-start")
        return result
    }
}

extension ColiCLI {
    /// Starts `coli setup` for a model and returns as soon as it is running on its own.
    ///
    /// The download can take hours, so it is started through `nohup` with its output going to
    /// the setup home's `install.log`. It carries on if this app quits, and progress is read
    /// back through `coli status`.
    @discardableResult
    public func install(_ request: InstallRequest, root: URL = Discovery.defaultRoot) async throws -> URL {
        try await install(request, home: request.setupHome(root: root))
    }

    /// The same, for a setup folder that already exists, as when resuming a paused download.
    @discardableResult
    public func install(_ request: InstallRequest, home: URL) async throws -> URL {
        let logs = home.appendingPathComponent("logs", isDirectory: true)
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        let log = logs.appendingPathComponent("install.log")

        var environment = self.environment(setupHome: home)
        environment["PYTHONUNBUFFERED"] = "1"
        environment["KOLIBRIE_INSTALL_LOG"] = log.path

        let output = try await ProcessRunner.run(
            executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: [
                "-c",
                "echo \"--- install $(date '+%Y-%m-%d %H:%M:%S'): $*\" >> \"$KOLIBRIE_INSTALL_LOG\"; "
                    + "nohup \"$@\" >> \"$KOLIBRIE_INSTALL_LOG\" 2>&1 < /dev/null &",
                "sh", launcher.python.path, launcher.script.path,
            ] + request.arguments,
            environment: environment,
            timeout: .seconds(20)
        )
        guard output.succeeded else {
            throw ColiError.commandFailed(command: "setup", exitCode: output.exitCode, output: output.combined)
        }
        return log
    }
}
