import CryptoKit
import Foundation

/// A Colibri release as GitHub's API describes it.
public struct ColibriRelease: Sendable, Equatable, Decodable {
    public struct Asset: Sendable, Equatable, Decodable {
        public var name: String
        public var size: Int?
        public var url: URL

        enum CodingKeys: String, CodingKey {
            case name, size
            case url = "browser_download_url"
        }
    }

    public var tag: String
    public var assets: [Asset]
    /// The release's page on GitHub, with its notes.
    public var pageURL: URL?

    enum CodingKeys: String, CodingKey {
        case tag = "tag_name"
        case assets
        case pageURL = "html_url"
    }

    /// The tag without a leading `v`.
    public var version: String { tag.hasPrefix("v") ? String(tag.dropFirst()) : tag }

    /// The archive for Macs with Apple silicon.
    public var macArchive: Asset? { assets.first { $0.name.hasSuffix("-macos-arm64.tar.gz") } }

    public var checksums: Asset? { assets.first { $0.name == "SHA256SUMS.txt" } }

    /// Checks downloaded bytes against the published checksum list, and throws if they do not match.
    public static func verify(_ data: Data, named name: String, against sums: String) throws {
        guard let expected = parseChecksum(sums, for: name) else {
            throw ColibriInstaller.InstallError.noChecksum(name)
        }
        let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard actual == expected else { throw ColibriInstaller.InstallError.checksumMismatch(name) }
    }

    /// Finds `name` in the text of a `sha256sum` file.
    public static func parseChecksum(_ text: String, for name: String) -> String? {
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "*" })
            if parts.count == 2, parts[1] == name { return parts[0].lowercased() }
        }
        return nil
    }
}

/// A web server answered with something other than success.
public struct HTTPStatusError: Error, LocalizedError, Equatable {
    public var status: Int
    public var host: String
    public var errorDescription: String? { "\(host) answered \(status)." }
}

/// Downloads a Colibri release archive, checks it against the published checksum, and unpacks
/// it into a folder Kolibrie owns, leaving anything already installed in place until the
/// new copy is ready.
public struct ColibriInstaller: Sendable {
    public typealias Download = @Sendable (URL) async throws -> Data

    public enum Step: Sendable, Equatable {
        case downloading(String)
        case verifying
        case unpacking
        case finishing
    }

    public enum InstallError: Error, LocalizedError, Equatable {
        case noMacArchive(String)
        case noChecksum(String)
        case checksumMismatch(String)
        case unpackFailed(String)
        case notColibri

        public var errorDescription: String? {
            switch self {
            case .noMacArchive(let tag):
                return "Colibri \(tag) has no download for Macs with Apple silicon."
            case .noChecksum(let name):
                return "Colibri's published checksums do not list \(name), so it cannot be checked."
            case .checksumMismatch(let name):
                return "\(name) does not match its published checksum, so it was not installed."
            case .unpackFailed(let reason):
                return "The download could not be unpacked. \(reason)"
            case .notColibri:
                return "The download does not look like Colibri (it has no coli launcher)."
            }
        }
    }

    public static let latestReleaseURL = URL(string: "https://api.github.com/repos/JustVugg/colibri/releases/latest")!

    /// Where Kolibrie keeps the Colibri it installs.
    public static func defaultDestination(
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        home.appendingPathComponent("Library/Application Support/Kolibrie/Colibri", isDirectory: true)
    }

    public let destination: URL
    private let download: Download

    public init(
        destination: URL = ColibriInstaller.defaultDestination(), download: @escaping Download = ColibriInstaller.fetch
    ) {
        self.destination = destination
        self.download = download
    }

    /// Fetches a URL, failing on anything but a successful answer.
    public static func fetch(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: 60)
        request.setValue("Kolibrie", forHTTPHeaderField: "User-Agent")
        if url.host == "api.github.com" {
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        if let status = (response as? HTTPURLResponse)?.statusCode, !(200..<300).contains(status) {
            throw HTTPStatusError(status: status, host: url.host ?? "The server")
        }
        return data
    }

    public func latestRelease() async throws -> ColibriRelease {
        try JSONDecoder().decode(ColibriRelease.self, from: try await download(Self.latestReleaseURL))
    }

    /// Installs `release` and returns the path of its `coli` launcher.
    @discardableResult
    public func install(_ release: ColibriRelease, progress: @Sendable (Step) -> Void = { _ in }) async throws -> URL {
        guard let asset = release.macArchive else { throw InstallError.noMacArchive(release.tag) }
        guard let sums = release.checksums else { throw InstallError.noChecksum(asset.name) }

        progress(.downloading(asset.name))
        let archive = try await download(asset.url)
        let sumsText = String(decoding: try await download(sums.url), as: UTF8.self)

        progress(.verifying)
        try ColibriRelease.verify(archive, named: asset.name, against: sumsText)

        progress(.unpacking)
        let fileManager = FileManager.default
        let parent = destination.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        let work = parent.appendingPathComponent(".install-\(UUID().uuidString)", isDirectory: true)
        let staging = work.appendingPathComponent("colibri", isDirectory: true)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: work) }

        let file = work.appendingPathComponent("colibri.tar.gz")
        try archive.write(to: file)
        let output = try await ProcessRunner.run(
            executable: URL(fileURLWithPath: "/usr/bin/tar"),
            arguments: ["-xzf", file.path, "-C", staging.path],
            environment: ["PATH": "/usr/bin:/bin"], timeout: .seconds(120))
        guard output.succeeded else { throw InstallError.unpackFailed(String(output.combined.suffix(300))) }
        guard fileManager.isReadableFile(atPath: staging.appendingPathComponent("coli").path) else {
            throw InstallError.notColibri
        }

        progress(.finishing)
        var previous: URL?
        if fileManager.fileExists(atPath: destination.path) {
            let aside = work.appendingPathComponent("previous", isDirectory: true)
            try fileManager.moveItem(at: destination, to: aside)
            previous = aside
        }
        do {
            try fileManager.moveItem(at: staging, to: destination)
        } catch {
            if let previous { try? fileManager.moveItem(at: previous, to: destination) }
            throw error
        }
        return destination.appendingPathComponent("coli")
    }
}
