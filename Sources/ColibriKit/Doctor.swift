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
