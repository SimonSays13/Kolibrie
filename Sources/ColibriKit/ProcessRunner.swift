import Foundation
import os

public struct ProcessOutput: Sendable, Equatable {
    public var exitCode: Int32
    public var stdout: String
    public var stderr: String

    public var succeeded: Bool { exitCode == 0 }

    /// Both streams, for error messages.
    public var combined: String {
        [stdout, stderr].filter { !$0.isEmpty }.joined(separator: "\n")
    }
}

public enum ProcessError: Error, LocalizedError, Equatable {
    case launchFailed(String)
    case timedOut

    public var errorDescription: String? {
        switch self {
        case .launchFailed(let reason): return "Could not run the command: \(reason)"
        case .timedOut: return "The command took too long and was stopped."
        }
    }
}

private final class RunState: @unchecked Sendable {
    private struct Flags {
        var timedOut = false
        var timeoutTask: Task<Void, Never>?
    }

    private let flags = OSAllocatedUnfairLock(initialState: Flags())
    private let process: Process

    init(_ process: Process) { self.process = process }

    var didTimeOut: Bool { flags.withLock { $0.timedOut } }

    func armTimeout(_ duration: Duration) {
        let task = Task { [self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            flags.withLock { $0.timedOut = true }
            terminate()
        }
        flags.withLock { $0.timeoutTask = task }
    }

    func terminate() {
        if process.isRunning { process.terminate() }
    }

    func finish() {
        flags.withLock { $0.timeoutTask }?.cancel()
    }
}

/// Runs a command and captures its output.
///
/// Output goes to temporary files, not pipes. `coli start` leaves a server running in the
/// background, and a pipe would stay open for as long as that server lives.
public enum ProcessRunner {
    public static func run(
        executable: URL,
        arguments: [String] = [],
        environment: [String: String],
        timeout: Duration? = nil
    ) async throws -> ProcessOutput {
        let fileManager = FileManager.default
        let scratch = fileManager.temporaryDirectory
            .appendingPathComponent("kolibrie-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: scratch) }

        let outURL = scratch.appendingPathComponent("stdout")
        let errURL = scratch.appendingPathComponent("stderr")
        fileManager.createFile(atPath: outURL.path, contents: nil)
        fileManager.createFile(atPath: errURL.path, contents: nil)
        let outHandle = try FileHandle(forWritingTo: outURL)
        let errHandle = try FileHandle(forWritingTo: errURL)
        defer {
            try? outHandle.close()
            try? errHandle.close()
        }

        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = outHandle
        process.standardError = errHandle

        let state = RunState(process)
        let exitCode: Int32 = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int32, any Error>) in
                process.terminationHandler = { finished in
                    continuation.resume(returning: finished.terminationStatus)
                }
                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: ProcessError.launchFailed(error.localizedDescription))
                    return
                }
                if let timeout { state.armTimeout(timeout) }
            }
        } onCancel: {
            state.terminate()
        }
        state.finish()
        if state.didTimeOut { throw ProcessError.timedOut }

        return ProcessOutput(
            exitCode: exitCode,
            stdout: String(decoding: (try? Data(contentsOf: outURL)) ?? Data(), as: UTF8.self),
            stderr: String(decoding: (try? Data(contentsOf: errURL)) ?? Data(), as: UTF8.self)
        )
    }
}
