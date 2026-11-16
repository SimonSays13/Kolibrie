import Foundation

public enum ColiError: Error, LocalizedError, Equatable {
    case launcherNotFound
    case commandFailed(command: String, exitCode: Int32, output: String)
    case unparsableOutput(command: String)
    case missingPort

    public var errorDescription: String? {
        switch self {
        case .launcherNotFound:
            return "Colibri's launcher (coli) and a Python 3.10 or newer were not found."
        case .commandFailed(let command, let exitCode, let output):
            let tail = String(output.trimmingCharacters(in: .whitespacesAndNewlines).suffix(400))
            return "coli \(command) failed (exit \(exitCode)). \(tail)"
        case .unparsableOutput(let command):
            return "coli \(command) returned output the app could not read."
        case .missingPort:
            return "This model's setup has no port."
        }
    }
}

/// The Python interpreter and the `coli` script that together run Colibri's launcher.
public struct ColiLauncher: Sendable, Equatable {
    public var python: URL
    public var script: URL

    public init(python: URL, script: URL) {
        self.python = python
        self.script = script
    }
}

public enum LauncherLocator {
    static let pythonCandidates = [
        "/opt/homebrew/bin/python3", "/usr/local/bin/python3", "/usr/bin/python3",
    ]

    /// Looks for a usable `coli` script and a Python 3.10 or newer.
    /// - Parameter hints: launcher paths taken from `setup.json` files, tried first.
    public static func locate(
        hints: [String] = [],
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> ColiLauncher? {
        var scripts = hints
        if let override = environment["SWIFTCOLIBRI_COLI"] { scripts.append(override) }
        scripts.append(home.appendingPathComponent("Development/colibri/c/coli").path)
        guard let script = scripts.first(where: { FileManager.default.isReadableFile(atPath: $0) }) else {
            return nil
        }
        guard let python = pythonCandidates.first(where: isUsablePython) else { return nil }
        return ColiLauncher(python: URL(fileURLWithPath: python), script: URL(fileURLWithPath: script))
    }

    static func isUsablePython(_ path: String) -> Bool {
        guard FileManager.default.isExecutableFile(atPath: path) else { return false }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["--version"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do { try process.run() } catch { return false }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return parsePythonVersion(String(decoding: data, as: UTF8.self)).map { $0 >= (3, 10) } ?? false
    }

    static func parsePythonVersion(_ text: String) -> (Int, Int)? {
        let parts = text.split(whereSeparator: { $0 == " " || $0 == "\n" })
        guard parts.count >= 2, parts[0] == "Python" else { return nil }
        let numbers = parts[1].split(separator: ".").compactMap { Int($0) }
        guard numbers.count >= 2 else { return nil }
        return (numbers[0], numbers[1])
    }
}
