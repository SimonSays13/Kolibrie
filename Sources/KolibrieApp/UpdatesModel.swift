import ColibriKit
import Foundation
import Observation

/// What is known about the newest Colibri and Kolibrie releases.
@MainActor @Observable
final class UpdatesModel {
    enum Status: Equatable {
        case unknown
        case checking
        case upToDate(String)
        case available(String)
        case notPublished
        case failed(String)

        var isAvailable: Bool {
            if case .available = self { return true }
            return false
        }
    }

    enum Phase: Equatable {
        case idle
        case working(String)
        case failed(String)
        case done(String)

        var isWorking: Bool {
            if case .working = self { return true }
            return false
        }
    }

    private(set) var colibri: Status = .unknown
    private(set) var kolibrie: Status = .unknown
    private(set) var colibriRelease: ColibriRelease?
    private(set) var kolibrieRelease: ColibriRelease?
    private(set) var colibriPhase: Phase = .idle
    private(set) var kolibriePhase: Phase = .idle
    private(set) var isChecking = false

    var hasUpdates: Bool { colibri.isAvailable || kolibrie.isAvailable }

    /// Asks GitHub for the newest release of each. `installedColibri` is `nil` when Colibri is missing.
    func check(installedColibri: String?, installedKolibrie: String) async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }
        colibri = installedColibri == nil ? .unknown : .checking
        kolibrie = .checking
        async let colibriResult = Self.lookup(UpdateCheck.colibriRepository)
        async let kolibrieResult = Self.lookup(UpdateCheck.kolibrieRepository)
        let (colibriFound, kolibrieFound) = await (colibriResult, kolibrieResult)

        if let installedColibri {
            (colibri, colibriRelease) = Self.status(colibriFound, installed: installedColibri)
        }
        (kolibrie, kolibrieRelease) = Self.status(kolibrieFound, installed: installedKolibrie)
    }

    private static func lookup(_ repository: String) async -> Result<ColibriRelease?, Error> {
        do { return .success(try await UpdateCheck.latest(of: repository)) } catch { return .failure(error) }
    }

    private static func status(
        _ result: Result<ColibriRelease?, Error>, installed: String
    ) -> (Status, ColibriRelease?) {
        switch result {
        case .failure(let error):
            return (.failed(error.localizedDescription), nil)
        case .success(nil):
            return (.notPublished, nil)
        case .success(let release?):
            return UpdateCheck.isNewer(release, than: installed)
                ? (.available(release.version), release) : (.upToDate(installed), release)
        }
    }

    func setColibriPhase(_ phase: Phase) { colibriPhase = phase }
    func setKolibriePhase(_ phase: Phase) { kolibriePhase = phase }

    func markColibriUpdated(to version: String) {
        colibri = .upToDate(version)
        colibriPhase = .done("Colibri \(version) is installed.")
    }
}
