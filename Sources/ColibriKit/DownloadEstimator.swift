import Foundation

/// Works out how fast a download is going from the progress the app has seen.
///
/// Colibri reports an average over the whole run, which keeps showing an old speed after the
/// connection slows down or speeds up. This looks only at the last few minutes instead.
public struct DownloadEstimator: Sendable, Equatable {
    private struct Sample: Sendable, Equatable {
        var time: Double
        var bytes: Double
    }

    private var samples: [Sample] = []
    /// How far back, in seconds, the speed is measured.
    public let window: Double
    /// How many seconds of progress are needed before a speed is given.
    public let minimumSpan: Double

    public init(window: Double = 240, minimumSpan: Double = 20) {
        self.window = window
        self.minimumSpan = minimumSpan
    }

    /// Records the bytes downloaded so far at `time` (seconds on any steady clock).
    public mutating func add(bytes: Double, at time: Double) {
        if let last = samples.last, bytes < last.bytes || time < last.time { samples.removeAll() }
        samples.append(Sample(time: time, bytes: bytes))
        let cutoff = time - window
        while samples.count > 2, samples[1].time <= cutoff { samples.removeFirst() }
    }

    public mutating func reset() { samples.removeAll() }

    /// Bytes per second over the window, or `nil` until there is enough to go on.
    public var bytesPerSecond: Double? {
        guard let first = samples.first, let last = samples.last, last.time - first.time >= minimumSpan else {
            return nil
        }
        return max(0, (last.bytes - first.bytes) / (last.time - first.time))
    }

    /// Seconds left, or `nil` when the speed is unknown or the download is not moving.
    public func etaSeconds(remainingBytes: Double) -> Double? {
        guard let rate = bytesPerSecond, rate > 0 else { return nil }
        return max(0, remainingBytes) / rate
    }
}

/// Wording for a time that is still to come.
public enum RemainingTime {
    public static func text(seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "" }
        if seconds < 45 { return "less than a minute" }
        let minutes = Int((seconds / 60).rounded())
        if minutes < 60 { return "\(minutes) min" }
        let rounded = Int((Double(minutes) / 5).rounded()) * 5
        let hours = rounded / 60
        let rest = rounded % 60
        if hours >= 48 {
            let days = hours / 24
            let extra = hours % 24
            return extra == 0 ? "\(days) days" : "\(days) days \(extra) h"
        }
        return rest == 0 ? "\(hours) h" : "\(hours) h \(rest) min"
    }
}

extension DownloadProgress {
    /// One line for the menu and the Models window.
    public func summary(rate: Double?, eta: Double?) -> String {
        var parts = ["\(Self.size(bytesDone)) of \(Self.size(bytesTotal))"]
        guard isRunning else { return parts.joined(separator: " · ") + " · paused" }
        if let rate {
            parts.append(rate > 0 ? "\(Self.size(rate))/s" : "no progress")
        }
        if let eta {
            parts.append("about \(RemainingTime.text(seconds: eta)) left")
        } else if rate == nil {
            parts.append("estimating time left")
        }
        return parts.joined(separator: " · ")
    }

    static func size(_ bytes: Double) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .decimal)
    }
}
