import Foundation

/// What deleting a model would remove, worked out before anything is touched.
public struct DeletionPlan: Sendable, Equatable {
    public var setupHome: URL
    /// The downloaded model files to delete, or `nil` when there are none or they are kept.
    public var modelDirectory: URL?
    /// Why the model files are not being deleted, when that is not obvious.
    public var filesNote: String?
    /// A reason nothing can be deleted at all.
    public var blocked: String?
}

public enum ModelDeletion {
    /// Decides what to remove. The setup folder always goes; the model files go only when they
    /// are where Colibri puts a model (a folder named after the model) and no other install
    /// uses them, so a mistaken path in `setup.json` can never remove something else.
    public static func plan(
        for model: InstalledModel, among all: [InstalledModel], supportRoot: URL = Discovery.defaultRoot
    ) -> DeletionPlan {
        let home = model.setupHome.standardizedFileURL
        var plan = DeletionPlan(setupHome: home)

        let name = home.lastPathComponent
        guard home.deletingLastPathComponent().path == supportRoot.standardizedFileURL.path,
            name == "colibri" || name.hasPrefix("colibri-")
        else {
            plan.blocked = "This is not a Colibri setup folder, so Kolibrie will not delete it."
            return plan
        }
        guard let directory = model.modelDirectory?.standardizedFileURL else {
            plan.filesNote = "No model folder is recorded for this install."
            return plan
        }
        guard DiskSpace.isVolumeMounted(for: directory) else {
            plan.blocked = "The drive that holds this model is not connected. Connect it to delete the files."
            return plan
        }
        guard FileManager.default.fileExists(atPath: directory.path) else {
            plan.filesNote = "The model folder is already gone."
            return plan
        }
        let modelID = model.config.model?.id
        if directory.pathComponents.count < 4 || directory.lastPathComponent != modelID {
            plan.filesNote =
                "The files at \(directory.path) are kept, because the folder is not named after the model."
            return plan
        }
        let sharedWithAnother = all.contains { other in
            guard other.id != model.id, let path = other.modelDirectory?.standardizedFileURL.path else { return false }
            return path == directory.path || path.hasPrefix(directory.path + "/")
                || directory.path.hasPrefix(path + "/")
        }
        if sharedWithAnother {
            plan.filesNote = "The files are kept, because another install uses the same folder."
            return plan
        }
        plan.modelDirectory = directory
        return plan
    }

    /// Total size of a folder in bytes.
    public static func size(of url: URL) -> Int64 {
        guard
            let walker = FileManager.default.enumerator(
                at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey])
        else { return 0 }
        var total: Int64 = 0
        for case let file as URL in walker {
            let values = try? file.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey])
            if values?.isRegularFile == true { total += Int64(values?.totalFileAllocatedSize ?? 0) }
        }
        return total
    }

    /// Removes the model files, then the setup folder. Files go first so that a failure
    /// leaves the install in place and the delete can be tried again.
    public static func delete(_ plan: DeletionPlan) throws {
        guard plan.blocked == nil else { throw ColiError.deletionBlocked(plan.blocked ?? "") }
        if let directory = plan.modelDirectory, FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
        if FileManager.default.fileExists(atPath: plan.setupHome.path) {
            try FileManager.default.removeItem(at: plan.setupHome)
        }
    }
}
