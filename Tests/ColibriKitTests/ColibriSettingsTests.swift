import Foundation
import Testing

@testable import ColibriKit

@Suite("Colibri settings")
struct ColibriSettingsTests {
    @Test("flagArguments only emits flags for fields that were actually set")
    func sparseFlags() {
        var settings = ColibriSettings()
        settings.ramGB = 96
        settings.policy = .balanced
        settings.autoTier = true
        let args = settings.flagArguments
        #expect(args == ["--ram", "96", "--auto-tier", "--policy", "balanced"])
    }

    @Test("all the documented flags round-trip through flagArguments")
    func everyFlag() {
        var settings = ColibriSettings()
        settings.ramGB = 64
        settings.contextLength = 131_072
        settings.cap = 8
        settings.vramGB = 24
        settings.autoTier = true
        settings.maxGenerationTokens = 2048
        settings.temperature = 0.7
        settings.topP = 0.9
        settings.topK = 40
        settings.repin = 500
        settings.policy = .experimentalFast
        settings.think = false
        settings.reasoningEffort = .high
        settings.modelAPIID = "kolibrie-local"
        settings.apiKey = "secret"
        settings.corsOrigins = ["https://a.example", "https://b.example"]
        settings.allowedHosts = ["my-mac.local"]
        settings.maxQueue = 16
        settings.queueTimeoutSeconds = 600
        settings.kvSlots = 4

        let args = settings.flagArguments
        let expected = [
            "--ram", "64", "--ctx", "131072", "--cap", "8", "--vram", "24", "--auto-tier",
            "--ngen", "2048", "--temp", "0.7", "--topp", "0.9", "--topk", "40", "--repin", "500",
            "--policy", "experimental-fast", "--no-think", "--effort", "high",
            "--model-id", "kolibrie-local", "--api-key", "secret",
            "--cors-origin", "https://a.example", "--cors-origin", "https://b.example",
            "--allowed-host", "my-mac.local",
            "--max-queue", "16", "--queue-timeout", "600", "--kv-slots", "4",
        ]
        #expect(args == expected)
    }

    @Test("useMetal becomes COLI_METAL alongside the advanced environment")
    func metalEnvironment() {
        var settings = ColibriSettings()
        settings.useMetal = true
        settings.advancedEnvironment = ["PIPE": "1"]
        let env = settings.environmentOverrides
        #expect(env["COLI_METAL"] == "1")
        #expect(env["PIPE"] == "1")
    }

    @Test("parsing an empty setup.json yields settings with nothing set")
    func parseEmpty() {
        let settings = ColibriSettings.parse(args: nil, env: nil)
        #expect(settings == ColibriSettings())
    }

    @Test("parse round-trips flagArguments")
    func parseRoundTrip() {
        var original = ColibriSettings()
        original.ramGB = 96
        original.contextLength = 65536
        original.autoTier = true
        original.think = true
        original.policy = .quality
        original.corsOrigins = ["https://example.com"]

        let args =
            ["web", "--model", "/path/to/model", "--host", "127.0.0.1", "--port", "8000"]
            + original.flagArguments
        let parsed = ColibriSettings.parse(args: args, env: nil)

        #expect(parsed.ramGB == 96)
        #expect(parsed.contextLength == 65536)
        #expect(parsed.autoTier == true)
        #expect(parsed.think == true)
        #expect(parsed.policy == .quality)
        #expect(parsed.corsOrigins == ["https://example.com"])
    }

    @Test("parse pulls COLI_METAL out of the env block and leaves the rest as advanced")
    func parseMetal() {
        let parsed = ColibriSettings.parse(args: [], env: ["COLI_METAL": "1", "PIPE": "1", "DIRECT": "0"])
        #expect(parsed.useMetal == true)
        #expect(parsed.advancedEnvironment == ["PIPE": "1", "DIRECT": "0"])
    }

    @Test("the environment variable catalogue has no duplicate names")
    func catalogueIsUnique() {
        let names = EnvironmentVariableCatalog.variables.map(\.name)
        #expect(Set(names).count == names.count)
    }

    @Test("ReconfigureRequest builds the expected coli arguments")
    func reconfigureArguments() {
        var settings = ColibriSettings()
        settings.ramGB = 48
        let request = ReconfigureRequest(
            modelDirectory: URL(fileURLWithPath: "/models/qwen"), host: "127.0.0.1", port: 8010,
            settings: settings, startWhenDone: true)
        let args = request.arguments
        #expect(args.first == "setup")
        #expect(args.contains("--reconfigure"))
        #expect(args.contains("--model-dir"))
        #expect(args.contains("/models/qwen"))
        #expect(args.contains("--ram"))
        #expect(args.contains("48"))
        #expect(args.last == "--background")
    }

    @Test("ReconfigureRequest with startWhenDone false ends in --no-start")
    func reconfigureNoStart() {
        let request = ReconfigureRequest(
            modelDirectory: URL(fileURLWithPath: "/models/qwen"), host: "127.0.0.1", port: 8010,
            settings: ColibriSettings(), startWhenDone: false)
        #expect(request.arguments.last == "--no-start")
    }
}
