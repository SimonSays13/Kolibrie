import Foundation
import Testing

@testable import ColibriKit

@Suite("Harness launch plans")
struct HarnessTests {
    static let home = URL(fileURLWithPath: "/Users/tester")
    static let openAI = URL(string: "http://127.0.0.1:8900/v1")!
    static let anthropic = URL(string: "http://127.0.0.1:8900/v1/messages")!
    static let endpoint = HarnessEndpoint(
        openaiBaseURL: openAI, anthropicBaseURL: anthropic, modelID: "qwen3-coder", contextLength: 128_000)

    @Test("every harness exposes a display name and an executable to look for")
    func metadata() {
        for harness in Harness.allCases {
            #expect(!harness.displayName.isEmpty)
            #expect(!harness.executableName.isEmpty)
        }
    }

    @Test("Claude Code uses pure environment variables")
    func claudeCode() throws {
        let plan = try HarnessLauncher.plan(for: .claudeCode, endpoint: Self.endpoint, home: Self.home)
        #expect(plan.filesToWrite.isEmpty)
        #expect(plan.command == ["claude"])
        #expect(plan.environment["ANTHROPIC_BASE_URL"] == Self.anthropic.absoluteString)
        #expect(plan.environment["ANTHROPIC_MODEL"] == "qwen3-coder")
        #expect(plan.environment["ANTHROPIC_AUTH_TOKEN"] != nil)
    }

    @Test("Claude Code fails without an Anthropic-compatible endpoint")
    func claudeCodeMissingEndpoint() {
        let endpoint = HarnessEndpoint(openaiBaseURL: Self.openAI, anthropicBaseURL: nil, modelID: "x")
        #expect(throws: HarnessError.missingEndpoint(.anthropicCompatible)) {
            try HarnessLauncher.plan(for: .claudeCode, endpoint: endpoint, home: Self.home)
        }
    }

    @Test("Codex configures a custom provider entirely via --config flags")
    func codex() throws {
        let plan = try HarnessLauncher.plan(for: .codex, endpoint: Self.endpoint, home: Self.home)
        #expect(plan.filesToWrite.isEmpty)
        #expect(plan.environment.isEmpty)
        #expect(plan.command.first == "codex")
        #expect(plan.command.contains("model_providers.kolibrie.base_url=\(Self.openAI.absoluteString)"))
        #expect(plan.command.contains("model=qwen3-coder"))
    }

    @Test("Codex fails without an OpenAI-compatible endpoint")
    func codexMissingEndpoint() {
        let endpoint = HarnessEndpoint(openaiBaseURL: nil, anthropicBaseURL: Self.anthropic, modelID: "x")
        #expect(throws: HarnessError.missingEndpoint(.openAICompatible)) {
            try HarnessLauncher.plan(for: .codex, endpoint: endpoint, home: Self.home)
        }
    }

    @Test("OpenCode passes its whole config inline, no files written")
    func openCode() throws {
        let plan = try HarnessLauncher.plan(for: .openCode, endpoint: Self.endpoint, home: Self.home)
        #expect(plan.filesToWrite.isEmpty)
        #expect(plan.command == ["opencode"])
        let content = try #require(plan.environment["OPENCODE_CONFIG_CONTENT"])
        let json = try #require(try JSONSerialization.jsonObject(with: Data(content.utf8)) as? [String: Any])
        #expect(json["model"] as? String == "kolibrie/qwen3-coder")
        let provider = try #require(json["provider"] as? [String: Any])
        let kolibrie = try #require(provider["kolibrie"] as? [String: Any])
        let options = try #require(kolibrie["options"] as? [String: Any])
        #expect(options["baseURL"] as? String == Self.openAI.absoluteString)
    }

    @Test("Pi merges its provider into an empty models.json")
    func piFromScratch() throws {
        let plan = try HarnessLauncher.plan(for: .pi, endpoint: Self.endpoint, home: Self.home, existingFiles: [:])
        #expect(plan.command == ["pi", "--provider", "kolibrie", "--model", "qwen3-coder"])
        let file = try #require(plan.filesToWrite.first)
        #expect(file.url == Self.home.appendingPathComponent(".pi/agent/models.json"))
        #expect(!file.isolated)
        let json = try #require(try JSONSerialization.jsonObject(with: Data(file.contents.utf8)) as? [String: Any])
        let providers = try #require(json["providers"] as? [String: Any])
        #expect(providers["kolibrie"] != nil)
    }

    @Test("Pi preserves an existing provider already in models.json")
    func piMerge() throws {
        let existingPath = Self.home.appendingPathComponent(".pi/agent/models.json")
        let existing = """
            {"providers":{"ollama":{"baseUrl":"http://localhost:11434/v1"}}}
            """
        let plan = try HarnessLauncher.plan(
            for: .pi, endpoint: Self.endpoint, home: Self.home, existingFiles: [existingPath: existing])
        let file = try #require(plan.filesToWrite.first)
        let json = try #require(try JSONSerialization.jsonObject(with: Data(file.contents.utf8)) as? [String: Any])
        let providers = try #require(json["providers"] as? [String: Any])
        #expect(providers["ollama"] != nil)
        #expect(providers["kolibrie"] != nil)
    }

    @Test("Hermes Agent warns when context is below its stated minimum")
    func hermesLowContext() throws {
        let endpoint = HarnessEndpoint(
            openaiBaseURL: Self.openAI, anthropicBaseURL: nil, modelID: "small", contextLength: 8_000)
        let plan = try HarnessLauncher.plan(for: .hermesAgent, endpoint: endpoint, home: Self.home)
        #expect(plan.warnings.contains { $0.contains("64,000") || $0.contains("64000") })
        #expect(plan.environment["HERMES_INFERENCE_PROVIDER"] == "custom")
    }

    @Test("Hermes Agent has no warning with plenty of context")
    func hermesEnoughContext() throws {
        let plan = try HarnessLauncher.plan(for: .hermesAgent, endpoint: Self.endpoint, home: Self.home)
        #expect(plan.warnings.isEmpty)
    }

    @Test("OpenClaw writes an isolated config and points OPENCLAW_CONFIG_PATH at it")
    func openClaw() throws {
        let plan = try HarnessLauncher.plan(for: .openClaw, endpoint: Self.endpoint, home: Self.home)
        let file = try #require(plan.filesToWrite.first)
        #expect(file.isolated)
        #expect(plan.environment["OPENCLAW_CONFIG_PATH"] == file.url.path)
        #expect(!plan.warnings.isEmpty)
    }

    @Test("Mistral Vibe gets its own VIBE_HOME with a config.toml")
    func mistralVibe() throws {
        let plan = try HarnessLauncher.plan(for: .mistralVibe, endpoint: Self.endpoint, home: Self.home)
        let file = try #require(plan.filesToWrite.first)
        #expect(file.isolated)
        #expect(file.contents.contains("api_base = \"\(Self.openAI.absoluteString)\""))
        #expect(plan.environment["VIBE_HOME"] == file.url.deletingLastPathComponent().path)
    }

    @Test("Copilot CLI is pure environment variables")
    func copilotCLI() throws {
        let plan = try HarnessLauncher.plan(for: .copilotCLI, endpoint: Self.endpoint, home: Self.home)
        #expect(plan.filesToWrite.isEmpty)
        #expect(plan.environment["COPILOT_PROVIDER_TYPE"] == "openai")
        #expect(plan.environment["COPILOT_MODEL"] == "qwen3-coder")
    }

    @Test("DeepSeek Harness gets its own DSH_HOME with a settings.yaml")
    func deepSeekHarness() throws {
        let plan = try HarnessLauncher.plan(for: .deepSeekHarness, endpoint: Self.endpoint, home: Self.home)
        let file = try #require(plan.filesToWrite.first)
        #expect(file.isolated)
        #expect(file.contents.contains("model: qwen3-coder"))
        #expect(plan.environment["DSH_HOME"] == file.url.deletingLastPathComponent().path)
    }
}
