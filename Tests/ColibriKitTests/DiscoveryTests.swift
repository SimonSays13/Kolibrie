import Foundation
import Testing

@testable import ColibriKit

@Suite("Discovery")
struct DiscoveryTests {
    func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    func install(_ name: String, contents: Data, in root: URL) throws {
        let home = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try contents.write(to: home.appendingPathComponent("setup.json"))
    }

    @Test func findsOnlyColibriHomesAndReportsBrokenOnes() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try install("colibri-glm-5.3", contents: Fixture.data("setup-glm-pending"), in: root)
        try install("colibri", contents: Fixture.data("setup-qwen-ready"), in: root)
        try install("Some Other App", contents: Fixture.data("setup-qwen-ready"), in: root)
        try install("colibri-broken", contents: Data("not json".utf8), in: root)

        let result = Discovery.installedModels(in: root)
        #expect(result.models.map(\.id) == ["colibri", "colibri-glm-5.3"])  // sorted by port
        #expect(result.problems.count == 1)
        #expect(result.problems.first?.hasPrefix("colibri-broken") == true)
    }

    @Test func modelDetails() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try install("colibri", contents: Fixture.data("setup-qwen-ready"), in: root)

        let model = try #require(Discovery.installedModels(in: root).models.first)
        #expect(model.displayName == "Qwen3.6-35B-A3B")
        #expect(model.port == 8000)
        #expect(model.serveLogURL.path.hasSuffix("colibri/logs/serve.log"))
    }

    @Test func missingRootGivesAProblemNotACrash() {
        let result = Discovery.installedModels(in: URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString)"))
        #expect(result.models.isEmpty)
        #expect(result.problems.count == 1)
    }
}
