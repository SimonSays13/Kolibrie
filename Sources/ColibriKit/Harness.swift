import Foundation

/// A running Colibri server's connection info, as a harness launcher needs it.
public struct HarnessEndpoint: Sendable, Equatable {
    public var openaiBaseURL: URL?
    public var anthropicBaseURL: URL?
    public var modelID: String
    public var contextLength: Int?

    public init(
        openaiBaseURL: URL?, anthropicBaseURL: URL?, modelID: String, contextLength: Int? = nil
    ) {
        self.openaiBaseURL = openaiBaseURL
        self.anthropicBaseURL = anthropicBaseURL
        self.modelID = modelID
        self.contextLength = contextLength
    }
}

/// One file a harness launcher needs written before launch.
public struct HarnessConfigFile: Sendable, Equatable {
    /// Where the file goes.
    public var url: URL
    /// What it should contain.
    public var contents: String
    /// `true` when Kolibrie owns the whole file (a generated, isolated config it created just
    /// for this launch). `false` when the file is one the harness's own tools also write to,
    /// and Kolibrie has merged its block into whatever was already there.
    public var isolated: Bool

    public init(url: URL, contents: String, isolated: Bool) {
        self.url = url
        self.contents = contents
        self.isolated = isolated
    }
}

/// Everything needed to launch one harness against one running Colibri model.
public struct HarnessLaunchPlan: Sendable, Equatable {
    public var filesToWrite: [HarnessConfigFile]
    public var environment: [String: String]
    /// argv for the command to run in a terminal, e.g. `["codex", "--profile", "x"]`.
    public var command: [String]
    public var warnings: [String]

    public init(
        filesToWrite: [HarnessConfigFile] = [],
        environment: [String: String] = [:],
        command: [String],
        warnings: [String] = []
    ) {
        self.filesToWrite = filesToWrite
        self.environment = environment
        self.command = command
        self.warnings = warnings
    }
}

public enum HarnessError: Error, LocalizedError, Equatable {
    case missingEndpoint(HarnessEndpointKind)

    public var errorDescription: String? {
        switch self {
        case .missingEndpoint(let kind):
            return "This model's server does not expose a \(kind.rawValue) endpoint."
        }
    }
}

public enum HarnessEndpointKind: String, Sendable {
    case openAICompatible = "OpenAI-compatible"
    case anthropicCompatible = "Anthropic-compatible"
}

/// One coding harness Kolibrie can point at a running Colibri model.
public enum Harness: String, Sendable, CaseIterable, Identifiable {
    case claudeCode, codex, openCode, pi, hermesAgent, openClaw, mistralVibe, copilotCLI, deepSeekHarness

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .codex: return "Codex"
        case .openCode: return "OpenCode"
        case .pi: return "Pi"
        case .hermesAgent: return "Hermes Agent"
        case .openClaw: return "OpenClaw"
        case .mistralVibe: return "Mistral Vibe"
        case .copilotCLI: return "Copilot CLI"
        case .deepSeekHarness: return "DeepSeek Harness"
        }
    }

    /// The executable Kolibrie looks for on `PATH` to decide whether this harness is installed.
    public var executableName: String {
        switch self {
        case .claudeCode: return "claude"
        case .codex: return "codex"
        case .openCode: return "opencode"
        case .pi: return "pi"
        case .hermesAgent: return "hermes"
        case .openClaw: return "openclaw"
        case .mistralVibe: return "vibe"
        case .copilotCLI: return "copilot"
        case .deepSeekHarness: return "dsh"
        }
    }

    /// The smallest context window this harness expects, where Colibri's or the harness's own
    /// docs call one out. Kolibrie still offers to launch below this; it just warns first.
    public var minimumContextTokens: Int? {
        switch self {
        case .hermesAgent: return 64_000
        default: return nil
        }
    }
}

/// Builds the launch plan for one harness, given a model's endpoint.
///
/// Where a harness has no way to point at a server for just one launch, Kolibrie writes an
/// isolated config file of its own (under Kolibrie's support directory) rather than touching the
/// harness's real configuration. Where a harness's own config file is also written by the
/// harness itself (such as Pi's `models.json`), Kolibrie merges just the block it owns into
/// whatever is already there, which the caller supplies via `existingFiles`.
public enum HarnessLauncher {
    /// `home/Library/Application Support/Kolibrie/harnesses/<harness>` — where isolated,
    /// Kolibrie-owned config files for a harness are written.
    public static func harnessSupportDirectory(for harness: Harness, home: URL) -> URL {
        home
            .appendingPathComponent("Library/Application Support/Kolibrie/harnesses", isDirectory: true)
            .appendingPathComponent(harness.rawValue, isDirectory: true)
    }

    public static func plan(
        for harness: Harness,
        endpoint: HarnessEndpoint,
        home: URL,
        existingFiles: [URL: String] = [:]
    ) throws -> HarnessLaunchPlan {
        let contextWarnings = contextWarnings(for: harness, endpoint: endpoint)
        switch harness {
        case .claudeCode:
            return try claudeCodePlan(endpoint: endpoint, warnings: contextWarnings)
        case .codex:
            return try codexPlan(endpoint: endpoint, warnings: contextWarnings)
        case .openCode:
            return try openCodePlan(endpoint: endpoint, warnings: contextWarnings)
        case .pi:
            return try piPlan(endpoint: endpoint, home: home, existingFiles: existingFiles, warnings: contextWarnings)
        case .hermesAgent:
            return try hermesAgentPlan(endpoint: endpoint, warnings: contextWarnings)
        case .openClaw:
            return try openClawPlan(endpoint: endpoint, home: home, warnings: contextWarnings)
        case .mistralVibe:
            return try mistralVibePlan(endpoint: endpoint, home: home, warnings: contextWarnings)
        case .copilotCLI:
            return try copilotCLIPlan(endpoint: endpoint, warnings: contextWarnings)
        case .deepSeekHarness:
            return try deepSeekHarnessPlan(endpoint: endpoint, home: home, warnings: contextWarnings)
        }
    }

    private static func contextWarnings(for harness: Harness, endpoint: HarnessEndpoint) -> [String] {
        guard let minimum = harness.minimumContextTokens, let actual = endpoint.contextLength, actual < minimum
        else { return [] }
        return [
            "\(harness.displayName) expects at least \(minimum.formatted()) tokens of context; "
                + "\(endpoint.modelID) reports only \(actual.formatted())."
        ]
    }

    private static func requireOpenAI(_ endpoint: HarnessEndpoint) throws -> URL {
        guard let url = endpoint.openaiBaseURL else { throw HarnessError.missingEndpoint(.openAICompatible) }
        return url
    }

    private static func requireAnthropic(_ endpoint: HarnessEndpoint) throws -> URL {
        guard let url = endpoint.anthropicBaseURL else { throw HarnessError.missingEndpoint(.anthropicCompatible) }
        return url
    }

    // MARK: Claude Code — pure environment variables, no files.

    private static func claudeCodePlan(endpoint: HarnessEndpoint, warnings: [String]) throws -> HarnessLaunchPlan {
        let base = try requireAnthropic(endpoint)
        return HarnessLaunchPlan(
            environment: [
                "ANTHROPIC_BASE_URL": base.absoluteString,
                "ANTHROPIC_AUTH_TOKEN": "kolibrie-local",
                "ANTHROPIC_MODEL": endpoint.modelID,
            ],
            command: ["claude"],
            warnings: warnings
        )
    }

    // MARK: Codex — `--config` flags on the command line, no files touched.

    private static func codexPlan(endpoint: HarnessEndpoint, warnings: [String]) throws -> HarnessLaunchPlan {
        let base = try requireOpenAI(endpoint)
        return HarnessLaunchPlan(
            command: [
                "codex",
                "--config", "model_provider=kolibrie",
                "--config", "model_providers.kolibrie.name=Kolibrie",
                "--config", "model_providers.kolibrie.base_url=\(base.absoluteString)",
                "--config", "model_providers.kolibrie.wire_api=chat",
                "--config", "model=\(endpoint.modelID)",
            ],
            warnings: warnings
        )
    }

    // MARK: OpenCode — inline config via `OPENCODE_CONFIG_CONTENT`, no files.

    private static func openCodePlan(endpoint: HarnessEndpoint, warnings: [String]) throws -> HarnessLaunchPlan {
        let base = try requireOpenAI(endpoint)
        let config: [String: Any] = [
            "$schema": "https://opencode.ai/config.json",
            "model": "kolibrie/\(endpoint.modelID)",
            "provider": [
                "kolibrie": [
                    "npm": "@ai-sdk/openai-compatible",
                    "name": "Kolibrie (local)",
                    "options": ["baseURL": base.absoluteString],
                    "models": [endpoint.modelID: [String: Any]()],
                ]
            ],
        ]
        let json = try serializeJSON(config)
        return HarnessLaunchPlan(
            environment: ["OPENCODE_CONFIG_CONTENT": json],
            command: ["opencode"],
            warnings: warnings
        )
    }

    // MARK: Pi — merges a provider block into `~/.pi/agent/models.json`.

    private static func piPlan(
        endpoint: HarnessEndpoint, home: URL, existingFiles: [URL: String], warnings: [String]
    ) throws -> HarnessLaunchPlan {
        let base = try requireOpenAI(endpoint)
        let path = home.appendingPathComponent(".pi/agent/models.json")
        var root = (existingFiles[path].flatMap { try? parseJSONObject($0) }) ?? [:]
        var providers = (root["providers"] as? [String: Any]) ?? [:]
        providers["kolibrie"] = [
            "baseUrl": base.absoluteString,
            "api": "openai-completions",
            "models": [
                [
                    "id": endpoint.modelID,
                    "contextWindow": endpoint.contextLength as Any,
                ]
            ],
        ]
        root["providers"] = providers
        let json = try serializeJSON(root)
        return HarnessLaunchPlan(
            filesToWrite: [HarnessConfigFile(url: path, contents: json, isolated: false)],
            command: ["pi", "--provider", "kolibrie", "--model", endpoint.modelID],
            warnings: warnings
        )
    }

    // MARK: Hermes Agent — pure environment variables, no files.

    private static func hermesAgentPlan(endpoint: HarnessEndpoint, warnings: [String]) throws -> HarnessLaunchPlan {
        let base = try requireOpenAI(endpoint)
        return HarnessLaunchPlan(
            environment: [
                "HERMES_INFERENCE_PROVIDER": "custom",
                "OPENAI_BASE_URL": base.absoluteString,
                "OPENAI_API_KEY": "kolibrie-local",
            ],
            command: ["hermes", "chat", "--model", endpoint.modelID],
            warnings: warnings
        )
    }

    // MARK: OpenClaw — isolated config via `OPENCLAW_CONFIG_PATH`. Unverified schema.

    private static func openClawPlan(
        endpoint: HarnessEndpoint, home: URL, warnings: [String]
    ) throws -> HarnessLaunchPlan {
        let base = try requireOpenAI(endpoint)
        let path = harnessSupportDirectory(for: .openClaw, home: home).appendingPathComponent("openclaw.json")
        let config: [String: Any] = [
            "providers": [
                "kolibrie": [
                    "baseURL": base.absoluteString,
                    "apiKey": "kolibrie-local",
                ]
            ],
            "model": "kolibrie/\(endpoint.modelID)",
        ]
        let json = try serializeJSON(config)
        return HarnessLaunchPlan(
            filesToWrite: [HarnessConfigFile(url: path, contents: json, isolated: true)],
            environment: ["OPENCLAW_CONFIG_PATH": path.path],
            command: ["openclaw"],
            warnings: warnings + [
                "OpenClaw's provider schema has not been verified against Kolibrie; check its own docs if it doesn't connect."
            ]
        )
    }

    // MARK: Mistral Vibe — isolated `VIBE_HOME` with its own `config.toml`.

    private static func mistralVibePlan(
        endpoint: HarnessEndpoint, home: URL, warnings: [String]
    ) throws -> HarnessLaunchPlan {
        let base = try requireOpenAI(endpoint)
        let directory = harnessSupportDirectory(for: .mistralVibe, home: home)
        let path = directory.appendingPathComponent("config.toml")
        let toml = """
            [[providers]]
            name = "kolibrie"
            api_base = "\(base.absoluteString)"
            api_key_env_var = ""
            api_style = "openai"
            backend = "generic"

            [[models]]
            name = "\(endpoint.modelID)"
            provider = "kolibrie"
            alias = "kolibrie"

            active_model = "kolibrie"
            """
        return HarnessLaunchPlan(
            filesToWrite: [HarnessConfigFile(url: path, contents: toml, isolated: true)],
            environment: ["VIBE_HOME": directory.path],
            command: ["vibe"],
            warnings: warnings
        )
    }

    // MARK: Copilot CLI — pure environment variables (BYOK), no files.

    private static func copilotCLIPlan(endpoint: HarnessEndpoint, warnings: [String]) throws -> HarnessLaunchPlan {
        let base = try requireOpenAI(endpoint)
        return HarnessLaunchPlan(
            environment: [
                "COPILOT_PROVIDER_TYPE": "openai",
                "COPILOT_PROVIDER_BASE_URL": base.absoluteString,
                "COPILOT_PROVIDER_API_KEY": "kolibrie-local",
                "COPILOT_MODEL": endpoint.modelID,
            ],
            command: ["copilot"],
            warnings: warnings
        )
    }

    // MARK: DeepSeek Harness — isolated `DSH_HOME` with its own `settings.yaml`.

    private static func deepSeekHarnessPlan(
        endpoint: HarnessEndpoint, home: URL, warnings: [String]
    ) throws -> HarnessLaunchPlan {
        let base = try requireOpenAI(endpoint)
        let directory = harnessSupportDirectory(for: .deepSeekHarness, home: home)
        let path = directory.appendingPathComponent("settings.yaml")
        let yaml = """
            agent-default-model:
              provider: kolibrie
              model: \(endpoint.modelID)
            llm-pi-ai:
              providers:
                kolibrie:
                  apiKeyEnv: KOLIBRIE_DSH_KEY
                  api: openai-completions
                  baseURL: \(base.absoluteString)
                  models:
                    - id: \(endpoint.modelID)
            """
        return HarnessLaunchPlan(
            filesToWrite: [HarnessConfigFile(url: path, contents: yaml, isolated: true)],
            environment: ["DSH_HOME": directory.path, "KOLIBRIE_DSH_KEY": "kolibrie-local"],
            command: ["dsh"],
            warnings: warnings
        )
    }

    // MARK: JSON helpers

    private static func serializeJSON(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(
            withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        return String(decoding: data, as: UTF8.self)
    }

    private static func parseJSONObject(_ text: String) throws -> [String: Any] {
        guard let data = text.data(using: .utf8),
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return [:]
        }
        return object
    }
}
