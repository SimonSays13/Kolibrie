import Foundation

/// The URLs a Colibri server publishes for itself.
public struct Endpoints: Sendable, Equatable, Decodable {
    public var browser: String?
    public var openaiBaseURL: String?
    public var anthropicBaseURL: String?

    enum CodingKeys: String, CodingKey {
        case browser
        case openaiBaseURL = "openai_base_url"
        case anthropicBaseURL = "anthropic_base_url"
    }
}

/// The contents of a model's `setup.json`. Every field is optional because a model that is
/// still downloading has a much smaller file than one that is ready.
public struct SetupConfig: Sendable, Equatable, Decodable {
    public struct Model: Sendable, Equatable, Decodable {
        public var id: String
        public var name: String?
        public var repo: String?
        public var revision: String?
    }

    public var status: String?
    public var model: Model?
    public var modelDir: String?
    public var modelsRoot: String?
    public var family: String?
    public var launcher: String?
    public var engine: String?
    public var engineSource: String?
    public var backend: String?
    public var requestedBackend: String?
    public var env: [String: JSONValue]?
    public var args: [String]?
    public var ctx: Int?
    public var host: String?
    public var port: Int?
    public var urls: Endpoints?
    public var version: Int?

    enum CodingKeys: String, CodingKey {
        case status, model, family, launcher, engine, backend, env, args, ctx, host, port, urls, version
        case modelDir = "model_dir"
        case modelsRoot = "models_root"
        case engineSource = "engine_source"
        case requestedBackend = "requested_backend"
    }

    public var isReady: Bool { status == "ready" }

    /// The `env` block as plain strings, in the form Colibri passes to the server.
    public var environment: [String: String] {
        (env ?? [:]).mapValues(\.displayString)
    }
}
