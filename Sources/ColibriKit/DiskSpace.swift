import Foundation

/// Free-space checks before a large download.
public enum DiskSpace {
    /// Gigabytes (10^9 bytes, as Colibri's catalogue counts them) free on the volume holding `url`.
    /// Walks up to the nearest folder that exists, because the target may not be created yet.
    public static func freeGB(at url: URL) -> Double? {
        var folder = url
        while !FileManager.default.fileExists(atPath: folder.path), folder.pathComponents.count > 1 {
            folder = folder.deletingLastPathComponent()
        }
        guard
            let values = try? folder.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
            let bytes = values.volumeAvailableCapacityForImportantUsage
        else { return nil }
        return Double(bytes) / 1_000_000_000
    }

    /// A warning when a download of `downloadGB` would not leave room to spare, else `nil`.
    public static func warning(downloadGB: Double?, freeGB: Double?) -> String? {
        guard let downloadGB, let freeGB else { return nil }
        let needed = downloadGB * 1.1
        guard freeGB < needed else { return nil }
        return String(format: "Needs about %.0f GB of free disk space and %.0f GB is free.", needed, freeGB)
    }

    /// False when `url` is on an external volume that is not mounted, so a download would
    /// otherwise be written to the internal disk under `/Volumes`.
    public static func isVolumeMounted(for url: URL) -> Bool {
        let parts = url.standardizedFileURL.pathComponents
        guard parts.count >= 3, parts[1] == "Volumes" else { return true }
        return FileManager.default.fileExists(atPath: "/Volumes/" + parts[2])
    }
}
