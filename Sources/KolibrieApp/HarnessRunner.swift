import ColibriKit
import Foundation

/// Writes whatever config a harness needs for one launch, then opens a Terminal window running
/// it. Kolibrie never overwrites a harness's whole configuration file — where a harness reads
/// its own file too (such as Pi's `models.json`), Kolibrie merges just its own provider block
/// into whatever is already there.
enum HarnessRunner {
    @discardableResult
    static func launch(_ harness: Harness, endpoint: HarnessEndpoint) throws -> HarnessLaunchPlan {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser

        var existing: [URL: String] = [:]
        let piModelsPath = home.appendingPathComponent(".pi/agent/models.json")
        if harness == .pi, let data = try? Data(contentsOf: piModelsPath) {
            existing[piModelsPath] = String(decoding: data, as: UTF8.self)
        }

        let plan = try HarnessLauncher.plan(for: harness, endpoint: endpoint, home: home, existingFiles: existing)

        for file in plan.filesToWrite {
            try fileManager.createDirectory(
                at: file.url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try file.contents.write(to: file.url, atomically: true, encoding: .utf8)
        }

        try openInTerminal(plan)
        return plan
    }

    private static func openInTerminal(_ plan: HarnessLaunchPlan) throws {
        var lines = ["#!/bin/zsh", "clear"]
        for (key, value) in plan.environment.sorted(by: { $0.key < $1.key }) {
            lines.append("export \(key)=\(shellQuote(value))")
        }
        for warning in plan.warnings {
            lines.append("echo \(shellQuote("note: " + warning))")
        }
        let commandLine = plan.command.map(shellQuote).joined(separator: " ")
        lines.append("echo \(shellQuote("Launching: " + plan.command.joined(separator: " ")))")
        lines.append(commandLine)

        let script = lines.joined(separator: "\n") + "\n"
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("kolibrie-launch-\(UUID().uuidString).command")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", "Terminal", scriptURL.path]
        try process.run()
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
