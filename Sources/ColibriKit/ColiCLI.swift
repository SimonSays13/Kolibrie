import Foundation

/// Runs Colibri's `coli` launcher with the right setup home and a clean environment.
///
/// The environment is built from scratch because a variable set in the calling process
/// overrides the `env` block of a model's `setup.json`.
public struct ColiCLI: Sendable {
    public let launcher: ColiLauncher

    public init(launcher: ColiLauncher) { self.launcher = launcher }

    public func environment(setupHome: URL?) -> [String: String] {
        var env = [
            "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
            "HOME": NSHomeDirectory(),
            "LANG": "en_US.UTF-8",
        ]
        if let tmp = ProcessInfo.processInfo.environment["TMPDIR"] { env["TMPDIR"] = tmp }
        if let setupHome { env["COLI_SETUP_HOME"] = setupHome.path }
        return env
    }

    public func run(
        _ arguments: [String], setupHome: URL? = nil, timeout: Duration? = nil
    ) async throws -> ProcessOutput {
        try await ProcessRunner.run(
            executable: launcher.python,
            arguments: [launcher.script.path] + arguments,
            environment: environment(setupHome: setupHome),
            timeout: timeout
        )
    }

    public func status(setupHome: URL) async throws -> StatusReport {
        let output = try await run(["status", "--json"], setupHome: setupHome, timeout: .seconds(30))
        if let report = try? JSONDecoder().decode(
            StatusReport.self, from: Self.jsonData(in: output.stdout, opener: "{"))
        {
            return report
        }
        if output.succeeded { throw ColiError.unparsableOutput(command: "status") }
        throw ColiError.commandFailed(command: "status", exitCode: output.exitCode, output: output.combined)
    }

    /// Starts the server in the background and returns after Colibri's short wait.
    public func start(setupHome: URL) async throws -> ProcessOutput {
        try await run(["start", "--json", "--no-browser"], setupHome: setupHome, timeout: .seconds(120))
    }

    /// Stops the server on `port`. Colibri saves its cache first, so this can take about 30 seconds.
    public func stop(setupHome: URL, port: Int) async throws -> ProcessOutput {
        try await run(["stop", "--port", String(port)], setupHome: setupHome, timeout: .seconds(180))
    }

    public func catalogue(includeUnfit: Bool = false) async throws -> [CatalogueEntry] {
        var arguments = ["setup", "--list", "--json"]
        if includeUnfit { arguments.append("--all") }
        let output = try await run(arguments, timeout: .seconds(60))
        guard output.succeeded else {
            throw ColiError.commandFailed(command: "setup --list", exitCode: output.exitCode, output: output.combined)
        }
        do {
            return try JSONDecoder().decode([CatalogueEntry].self, from: Self.jsonData(in: output.stdout, opener: "["))
        } catch {
            throw ColiError.unparsableOutput(command: "setup --list")
        }
    }

    /// Drops any text Colibri prints before the JSON itself.
    static func jsonData(in text: String, opener: Character) -> Data {
        guard let start = text.firstIndex(of: opener) else { return Data(text.utf8) }
        return Data(text[start...].utf8)
    }
}
