import Foundation
import Testing

@testable import ColibriKit

@Suite("Download time estimate")
struct EstimateTests {
    /// Real readings from a running 1.5 TB download, taken 15 seconds apart. Colibri's own
    /// figure at the time was 102.6 MB/s, an average over the whole run.
    @Test func measuresTheCurrentSpeedNotTheRunAverage() throws {
        var estimator = DownloadEstimator()
        let readings: [(Double, Double)] = [
            (0, 288_181_355_790), (15, 289_000_293_646), (30, 289_832_869_366), (45, 290_626_641_398),
        ]
        for (time, bytes) in readings { estimator.add(bytes: bytes, at: time) }
        let rate = try #require(estimator.bytesPerSecond)
        #expect(abs(rate - 54.3e6) < 0.5e6)
        let remaining = 1_560_998_988_078 - 290_626_641_398.0
        let eta = try #require(estimator.etaSeconds(remainingBytes: remaining))
        #expect(eta > 6 * 3600 && eta < 7 * 3600)  // Colibri said 3.4 hours
    }

    @Test func givesNoSpeedUntilThereIsEnoughToGoOn() {
        var estimator = DownloadEstimator()
        estimator.add(bytes: 0, at: 0)
        estimator.add(bytes: 100, at: 5)
        #expect(estimator.bytesPerSecond == nil)
        #expect(estimator.etaSeconds(remainingBytes: 1000) == nil)
    }

    @Test func followsASpeedChange() throws {
        var estimator = DownloadEstimator(window: 60, minimumSpan: 10)
        var bytes = 0.0
        for second in 0...120 {
            bytes += second < 60 ? 100 : 10  // fast for a minute, then slow
            estimator.add(bytes: bytes, at: Double(second))
        }
        let rate = try #require(estimator.bytesPerSecond)
        #expect(abs(rate - 10) < 1)
    }

    @Test func startsAgainWhenProgressGoesBackwards() throws {
        var estimator = DownloadEstimator()
        estimator.add(bytes: 5000, at: 0)
        estimator.add(bytes: 6000, at: 30)
        estimator.add(bytes: 100, at: 40)  // the download restarted
        #expect(estimator.bytesPerSecond == nil)
        estimator.add(bytes: 1100, at: 70)
        #expect(try #require(estimator.bytesPerSecond) > 30)
    }

    @Test func aStalledDownloadHasNoTimeLeft() {
        var estimator = DownloadEstimator(window: 60, minimumSpan: 10)
        for second in 0...100 { estimator.add(bytes: 1000, at: Double(second)) }
        #expect(estimator.bytesPerSecond == 0)
        #expect(estimator.etaSeconds(remainingBytes: 5000) == nil)
    }

    @Test func wordsForTimeLeft() {
        #expect(RemainingTime.text(seconds: 20) == "less than a minute")
        #expect(RemainingTime.text(seconds: 50) == "1 min")
        #expect(RemainingTime.text(seconds: 12 * 60) == "12 min")
        #expect(RemainingTime.text(seconds: 59.7 * 60) == "1 h")
        #expect(RemainingTime.text(seconds: 3 * 3600 + 26 * 60) == "3 h 25 min")
        #expect(RemainingTime.text(seconds: 12_291) == "3 h 25 min")
        #expect(RemainingTime.text(seconds: 50 * 3600) == "2 days 2 h")
        #expect(RemainingTime.text(seconds: .infinity) == "")
    }

    @Test func summaryLineCoversEachStage() throws {
        let install = try Fixture.decode(StatusReport.self, "status-glm-downloading").install
        var progress = try #require(install.flatMap(DownloadProgress.init(install:)))
        progress.isRunning = true
        #expect(progress.summary(rate: nil, eta: nil).hasSuffix("estimating time left"))
        #expect(progress.summary(rate: 54.3e6, eta: 3600).contains("54.3 MB/s · about 1 h left"))
        #expect(progress.summary(rate: 0, eta: nil).hasSuffix("no progress"))
        progress.isRunning = false
        #expect(progress.summary(rate: nil, eta: nil).hasSuffix("paused"))
    }
}

@Suite("Deleting a model")
struct DeletionTests {
    /// A support folder and a models folder in a scratch area, with one installed model.
    private struct Scratch {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("kolibrie-\(UUID().uuidString)")
        var support: URL { root.appendingPathComponent("support") }
        var models: URL { root.appendingPathComponent("colibri-models") }

        func install(_ id: String, directory: URL? = nil, config extra: String = "") throws -> InstalledModel {
            let home = support.appendingPathComponent("colibri-\(id)")
            let dir = directory ?? models.appendingPathComponent(id)
            for folder in [home, dir] {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            }
            try Data(repeating: 1, count: 4096).write(to: dir.appendingPathComponent("model.safetensors"))
            let json = #"{"status":"ready","model":{"id":"\#(id)"},"model_dir":"\#(dir.path)","port":8000\#(extra)}"#
            try Data(json.utf8).write(to: home.appendingPathComponent("setup.json"))
            return InstalledModel(setupHome: home, config: try Discovery.loadConfig(setupHome: home))
        }
    }

    @Test func removesTheModelFilesAndTheSetupFolder() throws {
        let scratch = Scratch()
        defer { try? FileManager.default.removeItem(at: scratch.root) }
        let model = try scratch.install("qwen36-35b")
        let other = try scratch.install("glm-5.3")

        let plan = ModelDeletion.plan(for: model, among: [model, other], supportRoot: scratch.support)
        #expect(plan.blocked == nil)
        #expect(plan.modelDirectory?.lastPathComponent == "qwen36-35b")
        #expect(ModelDeletion.size(of: scratch.models.appendingPathComponent("qwen36-35b")) >= 4096)

        try ModelDeletion.delete(plan)
        #expect(!FileManager.default.fileExists(atPath: model.setupHome.path))
        #expect(!FileManager.default.fileExists(atPath: scratch.models.appendingPathComponent("qwen36-35b").path))
        // Nothing else is touched.
        #expect(FileManager.default.fileExists(atPath: other.setupHome.path))
        #expect(FileManager.default.fileExists(atPath: scratch.models.appendingPathComponent("glm-5.3").path))
        #expect(FileManager.default.fileExists(atPath: scratch.models.path))
    }

    @Test func keepsFilesWhenTheFolderIsNotNamedAfterTheModel() throws {
        let scratch = Scratch()
        defer { try? FileManager.default.removeItem(at: scratch.root) }
        let model = try scratch.install("qwen36-35b", directory: scratch.root.appendingPathComponent("Documents/stuff"))
        let plan = ModelDeletion.plan(for: model, among: [model], supportRoot: scratch.support)
        #expect(plan.modelDirectory == nil)
        #expect(plan.filesNote?.contains("not named after the model") == true)
        try ModelDeletion.delete(plan)
        #expect(FileManager.default.fileExists(atPath: scratch.root.appendingPathComponent("Documents/stuff").path))
        #expect(!FileManager.default.fileExists(atPath: model.setupHome.path))
    }

    @Test func keepsFilesAnotherInstallUses() throws {
        let scratch = Scratch()
        defer { try? FileManager.default.removeItem(at: scratch.root) }
        let shared = scratch.models.appendingPathComponent("qwen36-35b")
        let first = try scratch.install("qwen36-35b")
        var second = try scratch.install("copy", directory: shared)
        second = InstalledModel(setupHome: second.setupHome, config: first.config)
        let plan = ModelDeletion.plan(for: first, among: [first, second], supportRoot: scratch.support)
        #expect(plan.modelDirectory == nil)
        #expect(plan.filesNote?.contains("another install") == true)
    }

    @Test func refusesAFolderThatIsNotAColibriSetupFolder() throws {
        let scratch = Scratch()
        defer { try? FileManager.default.removeItem(at: scratch.root) }
        let model = try scratch.install("qwen36-35b")
        let elsewhere = FileManager.default.temporaryDirectory
        let plan = ModelDeletion.plan(for: model, among: [model], supportRoot: elsewhere)
        #expect(plan.blocked != nil)
        #expect(throws: ColiError.self) { try ModelDeletion.delete(plan) }
        #expect(FileManager.default.fileExists(atPath: model.setupHome.path))
    }

    @Test func refusesWhileTheDriveIsNotConnected() throws {
        let scratch = Scratch()
        defer { try? FileManager.default.removeItem(at: scratch.root) }
        let home = scratch.support.appendingPathComponent("colibri-ghost")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let json =
            #"{"status":"ready","model":{"id":"ghost"},"model_dir":"/Volumes/NoSuchDrive-\#(UUID().uuidString)/colibri-models/ghost"}"#
        try Data(json.utf8).write(to: home.appendingPathComponent("setup.json"))
        let model = InstalledModel(setupHome: home, config: try Discovery.loadConfig(setupHome: home))
        let plan = ModelDeletion.plan(for: model, among: [model], supportRoot: scratch.support)
        #expect(plan.blocked?.contains("not connected") == true)
    }
}

@Suite("Pausing downloads")
struct PauseTests {
    @Test func willNotStopAProcessThatIsNotAColiSetup() async {
        #expect(await InstallProcess.isColiSetup(pid: Int(ProcessInfo.processInfo.processIdentifier)) == false)
        #expect(await InstallProcess.isColiSetup(pid: 1) == false)
        await #expect(throws: ColiError.installNotRunning) {
            try await InstallProcess.stop(pid: Int(ProcessInfo.processInfo.processIdentifier))
        }
    }
}
