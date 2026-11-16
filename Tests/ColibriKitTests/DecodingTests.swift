import Foundation
import Testing

@testable import ColibriKit

@Suite("Decoding real Colibri output")
struct DecodingTests {
    @Test func stoppedQwenStatus() throws {
        let report = try Fixture.decode(StatusReport.self, "status-qwen-stopped")
        #expect(report.server?.state == .stopped)
        #expect(report.server?.pid == nil)
        #expect(report.setup?.status == "ready")
        #expect(report.setup?.model?.id == "qwen36-35b")
        #expect(report.server?.urls?.openaiBaseURL == "http://127.0.0.1:8000/v1")
        #expect(report.server?.urls?.anthropicBaseURL == "http://127.0.0.1:8000")
    }

    @Test func readyQwenStatusFromARealRun() throws {
        let report = try Fixture.decode(StatusReport.self, "status-qwen-ready")
        #expect(report.server?.state == .ready)
        #expect(report.server?.modelID == "qwen3.6-colibri")
        #expect(report.server?.arch == "qwen36")
        #expect(try #require(report.server?.tokensPerSecond) > 1)
        #expect(report.server?.pid != nil)
        let config = try Fixture.decode(SetupConfig.self, "setup-qwen-ready")
        #expect(ModelState.derive(config: config, report: report, modelDirectoryExists: true) == .ready)
    }

    @Test func downloadingGLMStatus() throws {
        let report = try Fixture.decode(StatusReport.self, "status-glm-downloading")
        #expect(report.setup?.status == "pending")
        let progress = try #require(report.install.flatMap(DownloadProgress.init(install:)))
        #expect(progress.isRunning)
        #expect(progress.bytesTotal == 419_316_798_141)
        #expect(progress.fraction > 0.5 && progress.fraction < 1)
        #expect(progress.etaSeconds != nil)
    }

    @Test func readySetupFile() throws {
        let config = try Fixture.decode(SetupConfig.self, "setup-qwen-ready")
        #expect(config.isReady)
        #expect(config.port == 8000)
        #expect(config.backend == "cpu")
        #expect(config.environment.isEmpty)
        #expect(config.args?.contains("--auto-tier") == true)
        #expect(config.urls?.browser == "http://127.0.0.1:8000/")
    }

    @Test func pendingSetupFileHasNoEngineYet() throws {
        let config = try Fixture.decode(SetupConfig.self, "setup-glm-pending")
        #expect(!config.isReady)
        #expect(config.engine == nil)
        #expect(config.env == nil)
        #expect(config.port == 8001)
        #expect(config.modelsRoot == "/Volumes/HD-Ext/colibri-models")
    }

    @Test func catalogue() throws {
        let entries = try Fixture.decode([CatalogueEntry].self, "catalogue")
        #expect(entries.count == 12)
        #expect(entries.first?.id == "qwen36-35b")
        #expect(entries.first?.recommended == true)
        #expect(entries.first?.ramMinGB == 10)
    }

    @Test func environmentValuesBecomeStrings() throws {
        let json = #"{"env": {"COLI_METAL": 1, "COLI_ENGINE": "/x/engine", "FLAG": true, "NOTHING": null}}"#
        let config = try JSONDecoder().decode(SetupConfig.self, from: Data(json.utf8))
        #expect(config.environment["COLI_METAL"] == "1")
        #expect(config.environment["COLI_ENGINE"] == "/x/engine")
        #expect(config.environment["FLAG"] == "1")
        #expect(config.environment["NOTHING"] == "")
    }

    @Test func unknownServerStateIsKept() throws {
        let json = #"{"state": "paused"}"#
        let server = try JSONDecoder().decode(StatusReport.Server.self, from: Data(json.utf8))
        #expect(server.state.rawValue == "paused")
    }
}
