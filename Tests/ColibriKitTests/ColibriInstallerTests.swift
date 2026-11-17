import CryptoKit
import Foundation
import Testing

@testable import ColibriKit

@Suite("Installing Colibri")
struct ColibriInstallerTests {
    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// A small tar.gz shaped like Colibri's macOS archive, built with the system `tar`.
    private func makeArchive(in scratch: URL, files: [String: String]) throws -> Data {
        let content = scratch.appendingPathComponent("content")
        try FileManager.default.createDirectory(at: content, withIntermediateDirectories: true)
        for (name, text) in files { try Data(text.utf8).write(to: content.appendingPathComponent(name)) }
        let archive = scratch.appendingPathComponent("a.tar.gz")
        let tar = Process()
        tar.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        tar.arguments = ["-czf", archive.path, "-C", content.path] + files.keys.sorted()
        try tar.run()
        tar.waitUntilExit()
        return try Data(contentsOf: archive)
    }

    private func release(archiveName: String = "colibri-v9.9.9-macos-arm64.tar.gz") throws -> ColibriRelease {
        let json = """
            {"tag_name":"v9.9.9","assets":[
              {"name":"\(archiveName)","size":1,"browser_download_url":"https://example.test/\(archiveName)"},
              {"name":"SHA256SUMS.txt","size":1,"browser_download_url":"https://example.test/SHA256SUMS.txt"}]}
            """
        return try JSONDecoder().decode(ColibriRelease.self, from: Data(json.utf8))
    }

    private func installer(
        destination: URL, archive: Data, checksum: String, name: String = "colibri-v9.9.9-macos-arm64.tar.gz"
    ) -> ColibriInstaller {
        ColibriInstaller(destination: destination) { url in
            url.lastPathComponent == "SHA256SUMS.txt" ? Data("\(checksum)  \(name)\n".utf8) : archive
        }
    }

    @Test func decodesTheRealReleaseFromGitHub() throws {
        let release = try Fixture.decode(ColibriRelease.self, "release-v2.1.0")
        #expect(release.tag == "v2.1.0")
        #expect(release.version == "2.1.0")
        #expect(release.macArchive?.name == "colibri-v2.1.0-macos-arm64.tar.gz")
        #expect(release.macArchive?.url.host == "github.com")
        #expect(release.checksums?.name == "SHA256SUMS.txt")
    }

    @Test func readsTheRightLineFromAChecksumFile() {
        let text = """
            aaaa  colibri-v2.1.0-linux-x86_64.tar.gz
            BBBB  colibri-v2.1.0-macos-arm64.tar.gz
            """
        #expect(ColibriRelease.parseChecksum(text, for: "colibri-v2.1.0-macos-arm64.tar.gz") == "bbbb")
        #expect(ColibriRelease.parseChecksum(text, for: "missing.tar.gz") == nil)
    }

    @Test func installsAVerifiedArchive() async throws {
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("kolibrie-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: scratch) }
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        let archive = try makeArchive(
            in: scratch, files: ["coli": "#!/usr/bin/env python3\n", "version.py": "__version__ = \"9.9.9\"\n"])
        let destination = scratch.appendingPathComponent("Support/Kolibrie/Colibri")

        let steps = StepLog()
        let launcher = try await installer(destination: destination, archive: archive, checksum: sha256(archive))
            .install(try release()) { steps.add($0) }

        #expect(launcher.path == destination.appendingPathComponent("coli").path)
        #expect(FileManager.default.isReadableFile(atPath: launcher.path))
        let version = ColiLauncher(python: URL(fileURLWithPath: "/usr/bin/python3"), script: launcher).installedVersion
        #expect(version == "9.9.9")
        #expect(
            steps.values == [.downloading("colibri-v9.9.9-macos-arm64.tar.gz"), .verifying, .unpacking, .finishing])
        // No scratch folders are left beside the install.
        let leftovers = try FileManager.default.contentsOfDirectory(
            atPath: destination.deletingLastPathComponent().path)
        #expect(leftovers == ["Colibri"])
    }

    @Test func refusesAnArchiveThatDoesNotMatchItsChecksum() async throws {
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("kolibrie-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: scratch) }
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        let archive = try makeArchive(in: scratch, files: ["coli": "x"])
        let destination = scratch.appendingPathComponent("Colibri")
        await #expect(throws: ColibriInstaller.InstallError.checksumMismatch("colibri-v9.9.9-macos-arm64.tar.gz")) {
            try await installer(destination: destination, archive: archive, checksum: String(repeating: "0", count: 64))
                .install(try release())
        }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
    }

    @Test func refusesAnArchiveWithoutALauncher() async throws {
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("kolibrie-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: scratch) }
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        let archive = try makeArchive(in: scratch, files: ["readme.txt": "not colibri"])
        await #expect(throws: ColibriInstaller.InstallError.notColibri) {
            try await installer(
                destination: scratch.appendingPathComponent("Colibri"), archive: archive, checksum: sha256(archive)
            )
            .install(try release())
        }
    }

    @Test func replacesAnEarlierInstallOnlyOnceTheNewOneIsReady() async throws {
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("kolibrie-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let destination = scratch.appendingPathComponent("Colibri")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: destination.appendingPathComponent("coli"))

        // A bad download leaves the old copy alone.
        let bad = try makeArchive(in: scratch, files: ["readme.txt": "x"])
        _ = try? await installer(destination: destination, archive: bad, checksum: sha256(bad)).install(try release())
        #expect(try String(contentsOf: destination.appendingPathComponent("coli"), encoding: .utf8) == "old")

        // A good one replaces it.
        let scratch2 = scratch.appendingPathComponent("second")
        try FileManager.default.createDirectory(at: scratch2, withIntermediateDirectories: true)
        let good = try makeArchive(in: scratch2, files: ["coli": "new"])
        try await installer(destination: destination, archive: good, checksum: sha256(good)).install(try release())
        #expect(try String(contentsOf: destination.appendingPathComponent("coli"), encoding: .utf8) == "new")
    }

    @Test func reportsAReleaseWithNoMacDownload() async throws {
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("kolibrie-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: scratch) }
        await #expect(throws: ColibriInstaller.InstallError.noMacArchive("v9.9.9")) {
            try await installer(destination: scratch, archive: Data(), checksum: "")
                .install(try release(archiveName: "colibri-v9.9.9-linux-x86_64.tar.gz"))
        }
    }
}

private final class StepLog: @unchecked Sendable {
    private let lock = NSLock()
    private var steps: [ColibriInstaller.Step] = []
    func add(_ step: ColibriInstaller.Step) {
        lock.lock()
        steps.append(step)
        lock.unlock()
    }
    var values: [ColibriInstaller.Step] {
        lock.lock()
        defer { lock.unlock() }
        return steps
    }
}

@Suite("Finding Colibri and what it needs")
struct LocatorTests {
    @Test func findsTheCopyKolibrieInstalls() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("kolibrie-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let managed = ColibriInstaller.defaultDestination(home: home)
        try FileManager.default.createDirectory(at: managed, withIntermediateDirectories: true)
        #expect(LauncherLocator.diagnose(home: home, environment: [:]).script == nil)
        try Data("#!/usr/bin/env python3\n".utf8).write(to: managed.appendingPathComponent("coli"))
        #expect(LauncherLocator.diagnose(home: home, environment: [:]).script == managed.appendingPathComponent("coli"))
    }

    @Test func aHintFromAnExistingInstallComesFirst() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("kolibrie-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let hint = home.appendingPathComponent("elsewhere-coli")
        try Data("x".utf8).write(to: hint)
        #expect(LauncherLocator.diagnose(hints: [hint.path], home: home, environment: [:]).script == hint)
    }

    @Test func namesWhatToInstall() {
        let none = Prerequisites(python: nil, hasOpenMP: false, homebrew: nil, isAppleSilicon: true)
        #expect(none.missingPackages == ["python", "libomp"])
        #expect(none.brewCommand == "brew install python libomp")
        #expect(!none.isReady)
        let python = URL(fileURLWithPath: "/opt/homebrew/bin/python3")
        #expect(
            Prerequisites(python: python, hasOpenMP: false, homebrew: nil, isAppleSilicon: true).brewCommand
                == "brew install libomp")
        let ready = Prerequisites(python: python, hasOpenMP: true, homebrew: nil, isAppleSilicon: true)
        #expect(ready.isReady && ready.brewCommand == nil)
    }
}
