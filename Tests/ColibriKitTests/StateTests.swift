import Foundation
import Testing

@testable import ColibriKit

@Suite("Model state")
struct StateTests {
    func qwen(server state: String = "stopped") throws -> (SetupConfig, StatusReport) {
        let text = try Fixture.text("status-qwen-stopped")
            .replacingOccurrences(of: "\"state\": \"stopped\"", with: "\"state\": \"\(state)\"")
        return (
            try Fixture.decode(SetupConfig.self, "setup-qwen-ready"),
            try JSONDecoder().decode(StatusReport.self, from: Data(text.utf8))
        )
    }

    @Test func stopped() throws {
        let (config, report) = try qwen()
        #expect(ModelState.derive(config: config, report: report, modelDirectoryExists: true) == .stopped)
    }

    @Test func ready() throws {
        let (config, report) = try qwen(server: "ready")
        #expect(ModelState.derive(config: config, report: report, modelDirectoryExists: true) == .ready)
    }

    @Test func loadingCountsAsStarting() throws {
        let (config, report) = try qwen(server: "loading")
        #expect(ModelState.derive(config: config, report: report, modelDirectoryExists: true) == .starting)
    }

    @Test func unknownServerStateIsTreatedAsStarting() throws {
        let (config, report) = try qwen(server: "paused")
        #expect(ModelState.derive(config: config, report: report, modelDirectoryExists: true) == .starting)
    }

    @Test func missingModelFolderIsUnavailable() throws {
        let (config, report) = try qwen()
        let state = ModelState.derive(config: config, report: report, modelDirectoryExists: false)
        guard case .unavailable = state else {
            Issue.record("expected unavailable, got \(state)")
            return
        }
    }

    @Test func downloadingModelIsNotInstalled() throws {
        let config = try Fixture.decode(SetupConfig.self, "setup-glm-pending")
        let report = try Fixture.decode(StatusReport.self, "status-glm-downloading")
        let state = ModelState.derive(config: config, report: report, modelDirectoryExists: false)
        guard case .notInstalled(let progress?) = state else {
            Issue.record("expected notInstalled with progress, got \(state)")
            return
        }
        #expect(progress.isRunning)
        #expect(state.label.hasPrefix("Downloading"))
    }

    @Test func pendingStartCoversTheGapBeforeTheServerAppears() throws {
        let (config, report) = try qwen()
        let state = ModelState.derive(config: config, report: report, modelDirectoryExists: true, pending: .starting)
        #expect(state == .starting)
    }

    @Test func readyWinsOverPendingStart() throws {
        let (config, report) = try qwen(server: "ready")
        let state = ModelState.derive(config: config, report: report, modelDirectoryExists: true, pending: .starting)
        #expect(state == .ready)
    }

    @Test func pendingStopShowsStoppingUntilServerIsGone() throws {
        let (config, ready) = try qwen(server: "ready")
        #expect(
            ModelState.derive(config: config, report: ready, modelDirectoryExists: true, pending: .stopping)
                == .stopping)
        let (_, stopped) = try qwen()
        #expect(
            ModelState.derive(config: config, report: stopped, modelDirectoryExists: true, pending: .stopping)
                == .stopped)
    }

    @Test func transitioningStates() {
        #expect(ModelState.starting.isTransitioning)
        #expect(ModelState.stopping.isTransitioning)
        #expect(!ModelState.ready.isTransitioning)
    }
}
