import ColibriKit
import Foundation
import Observation

/// Sets Colibri up when this Mac does not have it: installs what it needs through Homebrew when
/// that is available, then downloads and checks Colibri's own release.
@MainActor @Observable
final class ColibriSetupModel {
    enum Phase: Equatable {
        case idle
        case working(String)
        case done(String)
        case failed(String)
    }

    private(set) var prerequisites = Prerequisites.check()
    private(set) var diagnosis = LauncherDiagnosis(script: nil, python: nil)
    private(set) var release: ColibriRelease?
    private(set) var releaseError: String?
    private(set) var phase: Phase = .idle
    private let installer = ColibriInstaller()
    private let onInstalled: () -> Void

    init(onInstalled: @escaping () -> Void) { self.onInstalled = onInstalled }

    var isWorking: Bool {
        if case .working = phase { return true }
        return false
    }

    var colibriFound: Bool { diagnosis.script != nil }

    /// True when Colibri still needs a download or a package install.
    var needsSetup: Bool { !colibriFound || !prerequisites.isReady }

    /// Packages can only be installed for the user when Homebrew is there to do it.
    var canInstallPackages: Bool { prerequisites.homebrew != nil }

    var destinationPath: String { installer.destination.path }

    func refresh(hints: [String]) async {
        let found = await Task.detached { (Prerequisites.check(), LauncherLocator.diagnose(hints: hints)) }.value
        prerequisites = found.0
        diagnosis = found.1
    }

    func loadRelease() async {
        do {
            release = try await installer.latestRelease()
            releaseError = nil
        } catch {
            releaseError = "Could not reach GitHub to see the latest Colibri release. \(error.localizedDescription)"
        }
    }

    func setUp(hints: [String]) async {
        guard !isWorking else { return }
        phase = .working("Checking this Mac…")
        await refresh(hints: hints)

        if !prerequisites.isReady {
            guard let brew = prerequisites.homebrew, let command = prerequisites.brewCommand else {
                phase = .failed(
                    "Install \(prerequisites.missingPackages.joined(separator: " and ")) first, then check again.")
                return
            }
            phase = .working(
                "Installing \(prerequisites.missingPackages.joined(separator: " and ")) with Homebrew. This can take a few minutes…"
            )
            do {
                let output = try await ProcessRunner.run(
                    executable: brew,
                    arguments: ["install"] + prerequisites.missingPackages,
                    environment: [
                        "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
                        "HOME": NSHomeDirectory(), "HOMEBREW_NO_ENV_HINTS": "1",
                    ],
                    timeout: .seconds(1800))
                guard output.succeeded else {
                    phase = .failed("`\(command)` failed. \(String(output.combined.suffix(400)))")
                    return
                }
            } catch {
                phase = .failed(error.localizedDescription)
                return
            }
            await refresh(hints: hints)
            guard prerequisites.isReady else {
                phase = .failed(
                    "Homebrew finished, but \(prerequisites.missingPackages.joined(separator: " and ")) still cannot be found."
                )
                return
            }
        }

        if !colibriFound {
            do {
                let release: ColibriRelease
                if let known = self.release { release = known } else { release = try await installer.latestRelease() }
                self.release = release
                try await installer.install(release) { step in
                    let text: String
                    switch step {
                    case .downloading: text = "Downloading Colibri \(release.version)…"
                    case .verifying: text = "Checking the download against its published checksum…"
                    case .unpacking: text = "Unpacking…"
                    case .finishing: text = "Putting Colibri in place…"
                    }
                    Task { @MainActor in self.setWorking(text) }
                }
            } catch {
                phase = .failed(error.localizedDescription)
                return
            }
            await refresh(hints: hints)
        }

        guard let launcher = diagnosis.launcher else {
            phase = .failed("Colibri was installed, but its launcher still cannot be run.")
            return
        }
        phase = .done(launcher.installedVersion.map { "Colibri \($0) is ready." } ?? "Colibri is ready.")
        onInstalled()
    }

    private func setWorking(_ text: String) {
        if isWorking { phase = .working(text) }
    }
}
