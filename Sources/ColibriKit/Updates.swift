import Foundation

/// A release number such as `2.1.0`, as found in tags (`v2.1.0`) and in version files.
public struct Version: Sendable, Equatable, Comparable, CustomStringConvertible {
    public let numbers: [Int]

    /// Reads the leading dotted number, ignoring a `v` before it and anything after it,
    /// so `v2.1.0`, `2.1.0-rc1` and `0.1.0 (development)` all work.
    public init?(_ text: String) {
        var rest = Substring(text.trimmingCharacters(in: .whitespaces))
        if rest.first == "v" || rest.first == "V" { rest = rest.dropFirst() }
        let leading = rest.prefix { $0.isNumber || $0 == "." }
        let parsed = leading.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard !parsed.isEmpty, !parsed.contains(nil) else { return nil }
        numbers = parsed.compactMap { $0 }
    }

    public static func < (lhs: Version, rhs: Version) -> Bool {
        let length = max(lhs.numbers.count, rhs.numbers.count)
        for index in 0..<length {
            let a = index < lhs.numbers.count ? lhs.numbers[index] : 0
            let b = index < rhs.numbers.count ? rhs.numbers[index] : 0
            if a != b { return a < b }
        }
        return false
    }

    public static func == (lhs: Version, rhs: Version) -> Bool { !(lhs < rhs) && !(rhs < lhs) }

    public var description: String { numbers.map(String.init).joined(separator: ".") }
}

/// Looks for newer releases on GitHub.
public enum UpdateCheck {
    public static let colibriRepository = "JustVugg/colibri"
    public static let kolibrieRepository = "SimonSays13/Kolibrie"

    /// The newest published release of `repository`, or `nil` when it has none (or it is private).
    public static func latest(
        of repository: String, download: ColibriInstaller.Download = ColibriInstaller.fetch
    ) async throws -> ColibriRelease? {
        let url = URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!
        do {
            return try JSONDecoder().decode(ColibriRelease.self, from: try await download(url))
        } catch let error as HTTPStatusError where error.status == 404 {
            return nil
        }
    }

    /// True when `release` is newer than `installed`. An unreadable version is never newer.
    public static func isNewer(_ release: ColibriRelease, than installed: String?) -> Bool {
        guard let installed, let current = Version(installed), let latest = Version(release.tag) else {
            return false
        }
        return latest > current
    }
}

/// Replaces the running Kolibrie app with a newer release and opens it again.
public struct AppUpdater: Sendable {
    public enum UpdateError: Error, LocalizedError, Equatable {
        case noAppDownload(String)
        case notWritable(String)
        case unpackFailed(String)
        case noApp

        public var errorDescription: String? {
            switch self {
            case .noAppDownload(let tag): return "Kolibrie \(tag) has no app download."
            case .notWritable(let folder):
                return "Kolibrie cannot replace itself because it cannot write to \(folder)."
            case .unpackFailed(let reason): return "The update could not be unpacked. \(reason)"
            case .noApp: return "The update does not contain the Kolibrie app."
            }
        }
    }

    private let download: ColibriInstaller.Download

    public init(download: @escaping ColibriInstaller.Download = ColibriInstaller.fetch) {
        self.download = download
    }

    /// The zip that holds the app: `Kolibrie-<version>.zip` beside a `SHA256SUMS.txt`.
    public static func appAsset(in release: ColibriRelease) -> ColibriRelease.Asset? {
        release.assets.first { $0.name.hasPrefix("Kolibrie") && $0.name.hasSuffix(".zip") }
    }

    /// Downloads, checks and unpacks the update next to `app`, and returns the new app's location.
    public func stage(
        _ release: ColibriRelease, replacing app: URL, progress: @Sendable (ColibriInstaller.Step) -> Void = { _ in }
    ) async throws -> URL {
        guard let asset = Self.appAsset(in: release) else { throw UpdateError.noAppDownload(release.tag) }
        guard let sums = release.checksums else { throw ColibriInstaller.InstallError.noChecksum(asset.name) }
        let parent = app.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: parent.path) else {
            throw UpdateError.notWritable(parent.path)
        }

        progress(.downloading(asset.name))
        let archive = try await download(asset.url)
        let sumsText = String(decoding: try await download(sums.url), as: UTF8.self)
        progress(.verifying)
        try ColibriRelease.verify(archive, named: asset.name, against: sumsText)

        progress(.unpacking)
        let staging = parent.appendingPathComponent(".Kolibrie-update-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        do {
            let zip = staging.appendingPathComponent("update.zip")
            try archive.write(to: zip)
            let output = try await ProcessRunner.run(
                executable: URL(fileURLWithPath: "/usr/bin/ditto"),
                arguments: ["-x", "-k", zip.path, staging.path],
                environment: ["PATH": "/usr/bin:/bin"], timeout: .seconds(120))
            guard output.succeeded else { throw UpdateError.unpackFailed(String(output.combined.suffix(300))) }
            try? FileManager.default.removeItem(at: zip)
            let entries = try FileManager.default.contentsOfDirectory(atPath: staging.path)
            guard let name = entries.first(where: { $0.hasSuffix(".app") }) else { throw UpdateError.noApp }
            return staging.appendingPathComponent(name)
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw error
        }
    }

    static let relaunchScript = """
        PID="$1"; OLD="$2"; NEW="$3"; OPEN="${4:-open}"
        while kill -0 "$PID" 2>/dev/null; do sleep 0.2; done
        BACKUP="$OLD.previous"
        rm -rf "$BACKUP"
        if mv "$OLD" "$BACKUP" && mv "$NEW" "$OLD"; then
          rm -rf "$BACKUP"
        elif [ -d "$BACKUP" ] && [ ! -e "$OLD" ]; then
          mv "$BACKUP" "$OLD"
        fi
        STAGE="$(dirname "$NEW")"
        case "$(basename "$STAGE")" in .Kolibrie-update-*) rm -rf "$STAGE" ;; esac
        "$OPEN" "$OLD"
        """

    /// Starts a helper that waits for `pid` to exit, swaps the app in place and opens it. It runs
    /// on its own, so the caller can quit straight after this returns.
    public static func relaunch(
        after pid: Int32, replacing app: URL, with staged: URL, opener: String = "open"
    ) async throws {
        _ = try await ProcessRunner.run(
            executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: [
                "-c", "nohup sh -c \"$0\" sh \"$@\" > /dev/null 2>&1 < /dev/null &",
                relaunchScript, String(pid), app.path, staged.path, opener,
            ],
            environment: ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"], timeout: .seconds(20))
    }
}
