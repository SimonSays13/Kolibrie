import Foundation

/// An action the app has started and not yet seen finish.
public enum PendingAction: Sendable, Equatable {
    case starting
    case stopping
}

/// What a model is doing, as the app shows it.
public enum ModelState: Sendable, Equatable {
    case unavailable(String)
    case notInstalled(DownloadProgress?)
    case stopped
    case starting
    case ready
    case stopping
    case failed(String)

    public var label: String {
        switch self {
        case .unavailable: return "Unavailable"
        case .notInstalled(let progress):
            guard let progress else { return "Not installed" }
            let percent = Int((progress.fraction * 100).rounded())
            return progress.isRunning ? "Downloading \(percent)%" : "Download paused at \(percent)%"
        case .stopped: return "Stopped"
        case .starting: return "Starting"
        case .ready: return "Ready"
        case .stopping: return "Stopping"
        case .failed: return "Error"
        }
    }

    /// True while a start or stop is under way, or the model is loading.
    public var isTransitioning: Bool { self == .starting || self == .stopping }

    /// Works out the state from a fresh status report. The server's own state is the truth;
    /// `pending` only covers the moments while a command is still running.
    public static func derive(
        config: SetupConfig,
        report: StatusReport,
        modelDirectoryExists: Bool,
        pending: PendingAction? = nil
    ) -> ModelState {
        let status = report.setup?.status ?? config.status
        if status != "ready" {
            return .notInstalled(report.install.flatMap(DownloadProgress.init(install:)))
        }
        guard modelDirectoryExists else {
            return .unavailable("Model folder not found. Is its drive connected?")
        }
        let server = report.server?.state ?? .stopped
        if pending == .stopping {
            return server == .stopped ? .stopped : .stopping
        }
        if server == .ready { return .ready }
        if pending == .starting || server == .loading { return .starting }
        if server == .stopped { return .stopped }
        return .starting
    }
}
