import Darwin
import Foundation

/// Pausing a download means stopping the `coli setup` process that is doing it. Colibri writes
/// each file as `<name>.part` and carries on from it, so running the install again resumes.
public enum InstallProcess {
    /// True when `pid` is a running `coli ... setup` process. A saved pid can be stale, and
    /// the number may by now belong to something else, so this checks before anything is stopped.
    public static func isColiSetup(pid: Int) async -> Bool {
        guard pid > 1,
            let output = try? await ProcessRunner.run(
                executable: URL(fileURLWithPath: "/bin/ps"),
                arguments: ["-p", String(pid), "-o", "command="],
                environment: ["PATH": "/bin:/usr/bin"], timeout: .seconds(10)),
            output.succeeded
        else { return false }
        let words = output.stdout.split(separator: " ").map(String.init)
        return words.contains { $0.hasSuffix("/coli") || $0 == "coli" } && words.contains("setup")
    }

    /// Stops the install and waits for it to exit.
    public static func stop(pid: Int) async throws {
        guard await isColiSetup(pid: pid) else { throw ColiError.installNotRunning }
        kill(pid_t(pid), SIGTERM)
        for _ in 0..<50 {
            if kill(pid_t(pid), 0) != 0 { return }
            try? await Task.sleep(for: .milliseconds(200))
        }
        throw ColiError.installDidNotStop
    }
}
