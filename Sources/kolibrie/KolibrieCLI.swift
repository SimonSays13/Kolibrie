import ColibriAPI
import ColibriKit
import Foundation

@main
struct KolibrieCLI {
    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let command = arguments.first ?? "list"
        let discovery = Discovery.installedModels()
        guard
            let launcher = LauncherLocator.locate(hints: discovery.models.compactMap { $0.config.launcher })
        else {
            fail(ColiError.launcherNotFound.localizedDescription)
        }
        let runtime = ModelRuntime(cli: ColiCLI(launcher: launcher))

        switch command {
        case "list":
            for problem in discovery.problems { print("warning: \(problem)") }
            await list(discovery.models, runtime: runtime)
        case "start", "stop":
            guard arguments.count > 1, let model = discovery.models.first(where: { $0.id == arguments[1] }) else {
                fail("usage: kolibrie \(command) <id>   (ids come from `kolibrie list`)")
            }
            do {
                if command == "start" { try await runtime.start(model) } else { try await runtime.stop(model) }
                let snapshot = await runtime.snapshot(of: model)
                print("\(model.id): \(snapshot.state.label)")
            } catch {
                fail(error.localizedDescription)
            }
        case "catalogue":
            await catalogue(runtime: runtime, includeUnfit: arguments.contains("--all"))
        case "install":
            await install(Array(arguments.dropFirst()), discovery: discovery, runtime: runtime)
        default:
            fail(
                "usage: kolibrie [list | start <id> | stop <id> | catalogue [--all] | install <model> [--dir <folder>]]"
            )
        }
    }

    static func list(_ models: [InstalledModel], runtime: ModelRuntime) async {
        print(pad("ID", 22) + pad("MODEL", 24) + pad("STATE", 22) + pad("PORT", 6) + pad("BACKEND", 8) + "HTTP")
        for model in models {
            let snapshot = await runtime.snapshot(of: model)
            let server = snapshot.report?.server
            var http = "-"
            if let port = model.port, let url = URL(string: "http://127.0.0.1:\(port)") {
                http = await ServerProbe(baseURL: url).health()?.isOK == true ? "ok" : "no answer"
            }
            var state = snapshot.state.label
            if let speed = server?.tokensPerSecond { state += String(format: " %.1f tok/s", speed) }
            print(
                pad(model.id, 22) + pad(model.displayName, 24) + pad(state, 22)
                    + pad(model.port.map(String.init) ?? "-", 6)
                    + pad(server?.backend ?? model.config.backend ?? "-", 8) + http)
        }
    }

    static func catalogue(runtime: ModelRuntime, includeUnfit: Bool) async {
        do {
            let entries = try await runtime.cli.catalogue(includeUnfit: includeUnfit)
            print(pad("MODEL", 28) + pad("DOWNLOAD", 11) + pad("RAM MIN", 9) + "FIT")
            for entry in entries {
                let size = entry.downloadGB.map { String(format: "%.1f GB", $0) } ?? "-"
                let ram = entry.ramMinGB.map { String(format: "%.0f GB", $0) } ?? "-"
                let fit = (entry.fits == false ? "no" : "yes") + (entry.recommended == true ? " (recommended)" : "")
                print(pad(entry.id, 28) + pad(size, 11) + pad(ram, 9) + fit)
            }
        } catch {
            fail(error.localizedDescription)
        }
    }

    static func install(_ arguments: [String], discovery: DiscoveryResult, runtime: ModelRuntime) async {
        guard let modelID = arguments.first, !modelID.hasPrefix("--") else {
            fail("usage: kolibrie install <model> [--dir <folder>]   (ids come from `kolibrie catalogue`)")
        }
        var directory: URL?
        if let index = arguments.firstIndex(of: "--dir"), arguments.indices.contains(index + 1) {
            directory = URL(fileURLWithPath: arguments[index + 1])
        }
        let port = PortPicker.nextFree(avoiding: Set(discovery.models.compactMap(\.port)))
        do {
            let log = try await runtime.cli.install(
                InstallRequest(modelID: modelID, port: port, modelsDirectory: directory))
            print("Install started on port \(port). Progress: kolibrie list. Log: \(log.path)")
        } catch {
            fail(error.localizedDescription)
        }
    }

    static func pad(_ text: String, _ width: Int) -> String {
        text.count >= width ? text + " " : text.padding(toLength: width, withPad: " ", startingAt: 0)
    }

    static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        exit(1)
    }
}
