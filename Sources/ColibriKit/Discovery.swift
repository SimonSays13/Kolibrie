import Foundation

/// One Colibri setup home: the folder that holds a model's `setup.json` and logs.
public struct InstalledModel: Sendable, Equatable, Identifiable {
    public let setupHome: URL
    public let config: SetupConfig

    public init(setupHome: URL, config: SetupConfig) {
        self.setupHome = setupHome
        self.config = config
    }

    /// The setup home's folder name, which is unique and stable.
    public var id: String { setupHome.lastPathComponent }

    public var displayName: String {
        config.model?.name ?? config.model?.id ?? setupHome.lastPathComponent
    }

    public var port: Int? { config.port }

    public var modelDirectory: URL? {
        config.modelDir.map { URL(fileURLWithPath: $0) }
    }

    public var serveLogURL: URL {
        setupHome.appendingPathComponent("logs").appendingPathComponent("serve.log")
    }
}

public struct DiscoveryResult: Sendable, Equatable {
    public var models: [InstalledModel]
    public var problems: [String]
}

/// Finds Colibri installs by listing `colibri` and `colibri-*` folders in Application Support.
public enum Discovery {
    public static var defaultRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    public static func loadConfig(setupHome: URL) throws -> SetupConfig {
        let data = try Data(contentsOf: setupHome.appendingPathComponent("setup.json"))
        return try JSONDecoder().decode(SetupConfig.self, from: data)
    }

    public static func installedModels(in root: URL = defaultRoot) -> DiscoveryResult {
        let fileManager = FileManager.default
        guard
            let entries = try? fileManager.contentsOfDirectory(
                at: root, includingPropertiesForKeys: [.isDirectoryKey])
        else {
            return DiscoveryResult(models: [], problems: ["Cannot read \(root.path)"])
        }
        var models: [InstalledModel] = []
        var problems: [String] = []
        for url in entries {
            let name = url.lastPathComponent
            guard name == "colibri" || name.hasPrefix("colibri-") else { continue }
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            guard fileManager.fileExists(atPath: url.appendingPathComponent("setup.json").path) else { continue }
            do {
                models.append(InstalledModel(setupHome: url, config: try loadConfig(setupHome: url)))
            } catch {
                problems.append("\(name): \(error.localizedDescription)")
            }
        }
        models.sort { ($0.port ?? .max, $0.id) < ($1.port ?? .max, $1.id) }
        return DiscoveryResult(models: models, problems: problems)
    }
}
