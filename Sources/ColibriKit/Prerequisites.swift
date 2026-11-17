import Foundation

/// What Colibri's prebuilt macOS engine needs from this Mac: a Python 3.10 or newer to run the
/// `coli` launcher, and Homebrew's OpenMP library, which the engine is linked against.
public struct Prerequisites: Sendable, Equatable {
    public var python: URL?
    public var hasOpenMP: Bool
    public var homebrew: URL?
    public var isAppleSilicon: Bool

    public init(python: URL?, hasOpenMP: Bool, homebrew: URL?, isAppleSilicon: Bool) {
        self.python = python
        self.hasOpenMP = hasOpenMP
        self.homebrew = homebrew
        self.isAppleSilicon = isAppleSilicon
    }

    static let openMPPath = "/opt/homebrew/opt/libomp/lib/libomp.dylib"
    static let homebrewPaths = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]

    public static func check() -> Prerequisites {
        let fileManager = FileManager.default
        #if arch(arm64)
            let arm = true
        #else
            let arm = false
        #endif
        return Prerequisites(
            python: LauncherLocator.pythonCandidates.first(where: LauncherLocator.isUsablePython)
                .map { URL(fileURLWithPath: $0) },
            hasOpenMP: fileManager.fileExists(atPath: openMPPath),
            homebrew: homebrewPaths.first(where: fileManager.isExecutableFile(atPath:)).map {
                URL(fileURLWithPath: $0)
            },
            isAppleSilicon: arm)
    }

    /// Homebrew formulae to install, in the order they are given to `brew install`.
    public var missingPackages: [String] {
        var packages: [String] = []
        if python == nil { packages.append("python") }
        if !hasOpenMP { packages.append("libomp") }
        return packages
    }

    public var isReady: Bool { missingPackages.isEmpty }

    /// The command to show someone who would rather run it themselves.
    public var brewCommand: String? {
        missingPackages.isEmpty ? nil : "brew install " + missingPackages.joined(separator: " ")
    }
}
