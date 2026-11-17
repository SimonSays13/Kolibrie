import Foundation

/// The result of `coli doctor --json` for one model directory.
public struct DoctorReport: Sendable, Equatable, Decodable {
    public struct Check: Sendable, Equatable, Decodable, Identifiable {
        public var id: String
        public var status: String
        public var summary: String?

        public var isFailure: Bool { status == "fail" || status == "error" }
        public var isWarning: Bool { status == "warn" || status == "warning" }
    }

    public var status: String
    public var model: String?
    public var checks: [Check]

    enum CodingKeys: String, CodingKey {
        case status, model, checks
    }

    public init(status: String, model: String?, checks: [Check]) {
        self.status = status
        self.model = model
        self.checks = checks
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decode(String.self, forKey: .status)
        model = try? container.decodeIfPresent(String.self, forKey: .model)
        checks = try container.decodeIfPresent([Check].self, forKey: .checks) ?? []
    }

    public var failures: [Check] { checks.filter(\.isFailure) }
    public var warnings: [Check] { checks.filter(\.isWarning) }
    public var isHealthy: Bool { failures.isEmpty && status != "error" }
}

extension ColiCLI {
    /// Runs Colibri's own health check against a model directory.
    public func doctor(modelDirectory: URL) async throws -> DoctorReport {
        let output = try await run(
            ["doctor", "--json", "--model", modelDirectory.path], timeout: .seconds(180))
        do {
            return try JSONDecoder().decode(DoctorReport.self, from: Self.jsonData(in: output.stdout, opener: "{"))
        } catch {
            throw ColiError.commandFailed(command: "doctor", exitCode: output.exitCode, output: output.combined)
        }
    }
}

/// Whether a model's engine build can actually use the Metal GPU, read from `coli doctor`'s
/// `accelerator.gpu` check (the only GPU accelerator relevant on macOS). Colibri reports this
/// per model because it depends on how that model's engine binary was built, not just on the
/// hardware.
public enum MetalAvailability: Sendable, Equatable {
    /// The engine can use the GPU; `summary` is Colibri's own wording.
    case available(String)
    /// Either no usable GPU, or (the common case on a prebuilt CPU engine) one is present but
    /// this engine build can't use it; `summary` is Colibri's own wording.
    case unavailable(String)
    /// `coli doctor` hasn't reported on this yet.
    case unknown

    public var summary: String? {
        switch self {
        case .available(let text), .unavailable(let text): return text
        case .unknown: return nil
        }
    }
}

extension DoctorReport {
    public var metalAvailability: MetalAvailability {
        guard let check = checks.first(where: { $0.id == "accelerator.gpu" }) else { return .unknown }
        if check.isFailure || check.isWarning {
            return .unavailable(check.summary ?? "A GPU was detected, but this engine build can't use it.")
        }
        if check.status == "pass" {
            return .available(check.summary ?? "GPU acceleration is available.")
        }
        return .unknown
    }
}
