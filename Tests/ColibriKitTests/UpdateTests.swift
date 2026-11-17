import CryptoKit
import Foundation
import Testing

@testable import ColibriKit

@Suite("Checking for updates")
struct UpdateTests {
    @Test func readsVersionsFromTagsAndFiles() {
        #expect(Version("v2.1.0")?.numbers == [2, 1, 0])
        #expect(Version("1.12.1")?.numbers == [1, 12, 1])
        #expect(Version("0.1.0 (development)")?.numbers == [0, 1, 0])
        #expect(Version("2.0.0-rc1")?.numbers == [2, 0, 0])
        #expect(Version("nonsense") == nil)
        #expect(Version("") == nil)
    }

    @Test func comparesNumbersNotText() {
        #expect(Version("1.12.1")! > Version("1.9.0")!)
        #expect(Version("2.0")! == Version("2.0.0")!)
        #expect(Version("2.1.0")! > Version("2.0.9")!)
        #expect(!(Version("2.1.0")! > Version("2.1.0")!))
    }

    private func release(_ tag: String) throws -> ColibriRelease {
        try JSONDecoder().decode(
            ColibriRelease.self,
            from: Data(#"{"tag_name":"\#(tag)","html_url":"https://example.test/r","assets":[]}"#.utf8))
    }

    @Test func offersOnlyNewerReleases() throws {
        #expect(UpdateCheck.isNewer(try release("v2.2.0"), than: "2.1.0"))
        #expect(!UpdateCheck.isNewer(try release("v2.1.0"), than: "2.1.0"))
        #expect(!UpdateCheck.isNewer(try release("v2.0.0"), than: "2.1.0"))  // a checkout ahead of the release
        #expect(!UpdateCheck.isNewer(try release("v2.2.0"), than: nil))
        #expect(!UpdateCheck.isNewer(try release("latest"), than: "2.1.0"))
        #expect(try release("v2.2.0").pageURL?.absoluteString == "https://example.test/r")
    }

    @Test func aRepositoryWithNoReleasesIsNotAnError() async throws {
        let none = try await UpdateCheck.latest(of: "someone/private") { _ in
            throw HTTPStatusError(status: 404, host: "api.github.com")
        }
        #expect(none == nil)
        await #expect(throws: HTTPStatusError.self) {
            _ = try await UpdateCheck.latest(of: "someone/broken") { _ in
                throw HTTPStatusError(status: 500, host: "api.github.com")
            }
        }
    }

    @Test func asksTheRightAddress() async throws {
        let seen = Seen()
        _ = try? await UpdateCheck.latest(of: "JustVugg/colibri") { url in
            seen.set(url)
            return try Fixture.data("release-v2.1.0")
        }
        #expect(seen.url?.absoluteString == "https://api.github.com/repos/JustVugg/colibri/releases/latest")
    }
}

private final class Seen: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: URL?
    func set(_ url: URL) {
        lock.lock()
        stored = url
        lock.unlock()
    }
    var url: URL? {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }
}

@Suite("Replacing the app")
struct AppUpdaterTests {
    private func makeZip(in scratch: URL, appName: String = "Kolibrie.app", marker: String) throws -> Data {
        let source = scratch.appendingPathComponent("zip-source")
        let app = source.appendingPathComponent(appName)
        try FileManager.default.createDirectory(
            at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        try Data(marker.utf8).write(to: app.appendingPathComponent("Contents/marker.txt"))
        let zip = scratch.appendingPathComponent("a.zip")
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-c", "-k", "--keepParent", app.path, zip.path]
        try ditto.run()
        ditto.waitUntilExit()
        return try Data(contentsOf: zip)
    }

    private func release(_ assetName: String) throws -> ColibriRelease {
        try JSONDecoder().decode(
            ColibriRelease.self,
            from: Data(
                """
                {"tag_name":"v0.2.0","assets":[
                 {"name":"\(assetName)","size":1,"browser_download_url":"https://example.test/\(assetName)"},
                 {"name":"SHA256SUMS.txt","size":1,"browser_download_url":"https://example.test/SHA256SUMS.txt"}]}
                """.utf8))
    }

    private func scratch() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("kolibrie-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func updater(zip: Data, name: String, checksum: String? = nil) -> AppUpdater {
        let sum = checksum ?? ColibriInstallerChecksum.sha256(zip)
        return AppUpdater { url in
            url.lastPathComponent == "SHA256SUMS.txt" ? Data("\(sum)  \(name)\n".utf8) : zip
        }
    }

    @Test func stagesAndReplacesTheApp() async throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let installed = dir.appendingPathComponent("Applications/Kolibrie.app")
        try FileManager.default.createDirectory(
            at: installed.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        try Data("old".utf8).write(to: installed.appendingPathComponent("Contents/marker.txt"))

        let zip = try makeZip(in: dir, marker: "new")
        let name = "Kolibrie-0.2.0.zip"
        let staged = try await updater(zip: zip, name: name).stage(try release(name), replacing: installed)
        #expect(staged.lastPathComponent == "Kolibrie.app")
        #expect(staged.deletingLastPathComponent().lastPathComponent.hasPrefix(".Kolibrie-update-"))

        // A finished process stands in for the app that is quitting.
        let finished = Process()
        finished.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        try finished.run()
        finished.waitUntilExit()
        try await AppUpdater.relaunch(
            after: finished.processIdentifier, replacing: installed, with: staged, opener: "/usr/bin/true")

        let marker = installed.appendingPathComponent("Contents/marker.txt")
        for _ in 0..<50 where (try? String(contentsOf: marker, encoding: .utf8)) != "new" {
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(try String(contentsOf: marker, encoding: .utf8) == "new")
        for _ in 0..<50 where FileManager.default.fileExists(atPath: staged.deletingLastPathComponent().path) {
            try await Task.sleep(for: .milliseconds(100))
        }
        let left = try FileManager.default.contentsOfDirectory(atPath: installed.deletingLastPathComponent().path)
        #expect(left == ["Kolibrie.app"])
    }

    @Test func refusesAnUpdateThatFailsItsChecksum() async throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let installed = dir.appendingPathComponent("Kolibrie.app")
        try FileManager.default.createDirectory(at: installed, withIntermediateDirectories: true)
        let zip = try makeZip(in: dir, marker: "new")
        let name = "Kolibrie-0.2.0.zip"
        await #expect(throws: ColibriInstaller.InstallError.checksumMismatch(name)) {
            _ = try await updater(zip: zip, name: name, checksum: String(repeating: "0", count: 64))
                .stage(try release(name), replacing: installed)
        }
        #expect(
            try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasPrefix(".Kolibrie-update") }
                .isEmpty)
    }

    @Test func needsAnAppDownloadInTheRelease() async throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        await #expect(throws: AppUpdater.UpdateError.noAppDownload("v0.2.0")) {
            _ = try await updater(zip: Data(), name: "x").stage(
                try release("source.tar.gz"), replacing: dir.appendingPathComponent("Kolibrie.app"))
        }
    }

    @Test func refusesWhenTheFolderCannotBeWritten() async throws {
        let name = "Kolibrie-0.2.0.zip"
        await #expect(throws: AppUpdater.UpdateError.self) {
            _ = try await updater(zip: Data(), name: name).stage(
                try release(name), replacing: URL(fileURLWithPath: "/System/Applications/Kolibrie.app"))
        }
    }
}

enum ColibriInstallerChecksum {
    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
