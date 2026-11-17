import AppKit
import Foundation
import ServiceManagement

/// Whether Kolibrie opens itself automatically at login, via `SMAppService`. Kolibrie is its
/// own login item — no separate helper app — so this just wraps `SMAppService.mainApp`.
enum LoginItem {
    enum Status: Sendable, Equatable {
        /// Not registered to open at login.
        case disabled
        /// Registered and will open at login.
        case enabled
        /// Registered, but macOS needs the user to approve it in System Settings.
        case needsApproval

        var label: String {
            switch self {
            case .disabled: return "Off"
            case .enabled: return "On"
            case .needsApproval: return "Needs approval in System Settings"
            }
        }
    }

    /// The live status, read straight from `SMAppService` since the user can also change this
    /// from System Settings without going through Kolibrie.
    static var status: Status {
        switch SMAppService.mainApp.status {
        case .enabled: return .enabled
        case .requiresApproval: return .needsApproval
        case .notRegistered, .notFound: return .disabled
        @unknown default: return .disabled
        }
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    /// Opens System Settings' Login Items pane, for when macOS needs the user's approval.
    static func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")
        else { return }
        NSWorkspace.shared.open(url)
    }
}
