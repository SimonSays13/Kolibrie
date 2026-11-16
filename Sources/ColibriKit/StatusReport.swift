import Foundation

/// The state of a server as `coli status --json` reports it. Colibri uses `ready`, `loading`
/// and `stopped`; any other value is kept as it came.
public struct ServerState: RawRepresentable, Sendable, Hashable, Decodable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public static let stopped = ServerState(rawValue: "stopped")
    public static let loading = ServerState(rawValue: "loading")
    public static let ready = ServerState(rawValue: "ready")
}

/// The output of `coli status --json` for one setup home.
public struct StatusReport: Sendable, Equatable, Decodable {
    public struct Setup: Sendable, Equatable, Decodable {
        public var status: String?
        public var model: SetupConfig.Model?
        public var modelDir: String?
        public var backend: String?
        public var engine: String?
        public var ready: Bool?

        enum CodingKeys: String, CodingKey {
            case status, model, backend, engine, ready
            case modelDir = "model_dir"
        }
    }

    public struct Server: Sendable, Equatable, Decodable {
        public var state: ServerState
        public var pid: Int?
        public var urls: Endpoints?
        public var model: String?
        public var modelDir: String?
        public var backend: String?
        public var modelID: String?
        public var tokensPerSecond: Double?
        public var arch: String?

        enum CodingKeys: String, CodingKey {
            case state, pid, urls, model, backend, arch
            case modelDir = "model_dir"
            case modelID = "model_id"
            case tokensPerSecond = "tokens_per_second"
        }
    }

    public struct Install: Sendable, Equatable, Decodable {
        public var phase: String?
        public var pid: Int?
        public var updated: Double?
        public var model: String?
        public var file: String?
        public var done: Double?
        public var total: Double?
        public var rate: Double?
        public var etaSeconds: Double?
        public var modelDir: String?
        public var running: Bool?
        public var urls: Endpoints?

        enum CodingKeys: String, CodingKey {
            case phase, pid, updated, model, file, done, total, rate, running, urls
            case etaSeconds = "eta_seconds"
            case modelDir = "model_dir"
        }
    }

    public var configured: Bool?
    public var configPath: String?
    public var setup: Setup?
    public var server: Server?
    public var install: Install?

    enum CodingKeys: String, CodingKey {
        case configured, setup, server, install
        case configPath = "config_path"
    }
}

/// How far a model download has got, taken from the install block of a status report.
public struct DownloadProgress: Sendable, Equatable {
    public var file: String?
    public var bytesDone: Double
    public var bytesTotal: Double
    public var bytesPerSecond: Double?
    public var etaSeconds: Double?
    public var isRunning: Bool

    public var fraction: Double { bytesTotal > 0 ? min(1, bytesDone / bytesTotal) : 0 }

    public init?(install: StatusReport.Install) {
        guard install.phase == "download", let total = install.total, total > 0 else { return nil }
        file = install.file
        bytesDone = install.done ?? 0
        bytesTotal = total
        bytesPerSecond = install.rate
        etaSeconds = install.etaSeconds
        isRunning = install.running ?? false
    }
}
