import Foundation
import Testing

@testable import ColibriKit

@Suite("Installing models")
struct InstallTests {
    @Test func argumentsForABackgroundInstall() {
        let request = InstallRequest(modelID: "qwen36-35b", port: 8003)
        #expect(
            request.arguments == [
                "setup", "--yes", "--no-browser", "--model", "qwen36-35b", "--port", "8003", "--background",
            ])
    }

    @Test func argumentsWithADirectoryAndNoStart() {
        let request = InstallRequest(
            modelID: "glm-5.3", port: 8001, modelsDirectory: URL(fileURLWithPath: "/Volumes/Models"),
            startWhenDone: false)
        #expect(request.arguments.suffix(3) == ["--dir", "/Volumes/Models", "--no-start"])
    }

    @Test func setupHomeFollowsTheFolderConvention() {
        let root = URL(fileURLWithPath: "/tmp/support")
        let home = InstallRequest(modelID: "kimi-k3", port: 8002).setupHome(root: root)
        #expect(home.path == "/tmp/support/colibri-kimi-k3")
    }

    @Test func discoveryFindsTheHomeAnInstallCreates() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("kolibrie-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let home = InstallRequest(modelID: "qwen36-35b", port: 8000).setupHome(root: root)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try Fixture.data("setup-qwen-ready").write(to: home.appendingPathComponent("setup.json"))
        let found = Discovery.installedModels(in: root)
        #expect(found.models.map(\.id) == ["colibri-qwen36-35b"])
    }
}

@Suite("Ports and disk space")
struct PortAndDiskTests {
    @Test func skipsPortsOtherModelsUse() {
        let port = PortPicker.nextFree(startingAt: 18_100, avoiding: [18_100, 18_101])
        #expect(port >= 18_102)
    }

    @Test func skipsAPortSomethingIsListeningOn() throws {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        defer { close(descriptor) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(UInt16(18_200).bigEndian)
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        try #require(bound == 0)
        try #require(listen(descriptor, 1) == 0)
        #expect(!PortPicker.isFree(18_200))
        #expect(PortPicker.nextFree(startingAt: 18_200) > 18_200)
    }

    @Test func warnsWhenTheDownloadWouldNotFit() {
        #expect(DiskSpace.warning(downloadGB: 23.1, freeGB: 40) == nil)
        #expect(DiskSpace.warning(downloadGB: 23.1, freeGB: 24)?.contains("25 GB") == true)
        #expect(DiskSpace.warning(downloadGB: nil, freeGB: 5) == nil)
    }

    @Test func freeSpaceIsFoundForAFolderThatDoesNotExistYet() {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("nope/not/here")
        #expect((DiskSpace.freeGB(at: missing) ?? 0) > 0)
    }
}

@Suite("Doctor")
struct DoctorTests {
    @Test func decodesARealReportWithAWarning() throws {
        let report = try Fixture.decode(DoctorReport.self, "doctor-qwen-warning")
        #expect(report.status == "warning")
        #expect(report.checks.count == 12)
        #expect(report.warnings.map(\.id) == ["accelerator.gpu"])
        #expect(report.failures.isEmpty)
        #expect(report.isHealthy)
    }

    @Test func aFailedCheckIsNotHealthy() throws {
        let json = #"{"status":"error","checks":[{"id":"config.arguments","status":"fail","summary":"no model"}]}"#
        let report = try JSONDecoder().decode(DoctorReport.self, from: Data(json.utf8))
        #expect(!report.isHealthy)
        #expect(report.failures.count == 1)
    }

    @Test func warningAcceleratorCheckMeansMetalIsUnavailable() throws {
        let report = try Fixture.decode(DoctorReport.self, "doctor-qwen-warning")
        #expect(
            report.metalAvailability
                == .unavailable("GPU detected but the engine is CPU-only"))
    }

    @Test func passingAcceleratorCheckMeansMetalIsAvailable() {
        let report = DoctorReport(
            status: "ok", model: "/models/x",
            checks: [DoctorReport.Check(id: "accelerator.gpu", status: "pass", summary: "Metal GPU engaged")])
        #expect(report.metalAvailability == .available("Metal GPU engaged"))
    }

    @Test func failingAcceleratorCheckAlsoMeansMetalIsUnavailable() {
        let report = DoctorReport(
            status: "error", model: "/models/x",
            checks: [DoctorReport.Check(id: "accelerator.gpu", status: "fail", summary: "no GPU found")])
        #expect(report.metalAvailability == .unavailable("no GPU found"))
    }

    @Test func noAcceleratorCheckAtAllMeansMetalAvailabilityIsUnknown() {
        let report = DoctorReport(status: "ok", model: "/models/x", checks: [])
        #expect(report.metalAvailability == .unknown)
        #expect(report.metalAvailability.summary == nil)
    }
}
