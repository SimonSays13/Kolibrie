import ColibriKit
import SwiftUI

struct MenuContentView: View {
    let app: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("swiftColibri").font(.headline).padding(.horizontal, 14).padding(.vertical, 10)
            Divider()
            if app.launcherMissing {
                notice(
                    "Colibri's launcher was not found. Install Colibri, or set SWIFTCOLIBRI_COLI to the path of its coli script."
                )
            } else if app.controllers.isEmpty {
                notice("No Colibri installs found in ~/Library/Application Support.")
            }
            ForEach(app.controllers) { controller in
                ModelRow(controller: controller)
                Divider()
            }
            ForEach(app.problems, id: \.self) { notice($0) }
            HStack {
                Button("Refresh") {
                    Task {
                        app.rescan()
                        await app.refreshAll()
                    }
                }
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14).padding(.vertical, 8)
        }
        .frame(width: 360)
    }

    private func notice(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct ModelRow: View {
    let controller: ModelController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Circle().fill(color).frame(width: 9, height: 9)
                VStack(alignment: .leading, spacing: 2) {
                    Text(controller.installed.displayName).fontWeight(.medium)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                actionButton
                moreMenu
            }
            if case .notInstalled(let progress?) = controller.state {
                ProgressView(value: progress.fraction)
            }
            if case .unavailable(let reason)? = controller.state {
                Text(reason).font(.caption).foregroundStyle(.orange)
            }
            if case .failed(let reason)? = controller.state {
                Text(reason).font(.caption).foregroundStyle(.red).lineLimit(3)
            }
            if let message = controller.message {
                Text(message).font(.caption).foregroundStyle(.red).lineLimit(4)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
    }

    private var subtitle: String {
        var parts = [controller.state?.label ?? "Checking"]
        if let port = controller.installed.port { parts.append("port \(port)") }
        if let backend = controller.server?.backend ?? controller.installed.config.backend {
            parts.append(backend.uppercased())
        }
        if let speed = controller.server?.tokensPerSecond { parts.append(String(format: "%.1f tok/s", speed)) }
        if case .notInstalled(let progress?)? = controller.state, let eta = progress.etaSeconds, progress.isRunning {
            parts.append("\(Int((eta / 60).rounded(.up))) min left")
        }
        return parts.joined(separator: " · ")
    }

    private var color: Color {
        switch controller.state {
        case .ready?: return .green
        case .starting?, .stopping?: return .yellow
        case .failed?: return .red
        case .unavailable?: return .orange
        case .notInstalled?: return .blue
        default: return .gray
        }
    }

    @ViewBuilder private var actionButton: some View {
        switch controller.state {
        case .stopped?:
            Button("Start") { Task { await controller.start() } }
        case .ready?:
            Button("Stop") { Task { await controller.stop() } }
        case .starting?, .stopping?:
            ProgressView().controlSize(.small)
        default:
            EmptyView()
        }
    }

    private var moreMenu: some View {
        Menu {
            Button("Open dashboard") { controller.openDashboard() }.disabled(!controller.canOpenDashboard)
            Button("Copy OpenAI base URL") { controller.copyOpenAIURL() }
            Button("Copy Anthropic base URL") { controller.copyAnthropicURL() }
            Button("Copy model ID") { controller.copyModelID() }.disabled(!controller.hasModelID)
            Divider()
            Button("Show server log") {
                openWindow(id: "logs", value: controller.id)
                NSApplication.shared.activate()
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

struct LogsView: View {
    let app: AppModel
    let modelID: String?
    @State private var text = ""

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(text)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                Color.clear.frame(height: 1).id("end")
            }
            .onChange(of: text) { proxy.scrollTo("end", anchor: .bottom) }
        }
        .navigationTitle(title)
        .task {
            while !Task.isCancelled {
                load()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private var controller: ModelController? { app.controllers.first { $0.id == modelID } }
    private var title: String { "Server log: \(controller?.installed.displayName ?? modelID ?? "")" }

    private func load() {
        guard let controller else {
            text = "This model is no longer installed."
            return
        }
        text = LogTail.read(url: controller.installed.serveLogURL)
    }
}

enum LogTail {
    static func read(url: URL, maxBytes: Int = 64_000, maxLines: Int = 300) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "No log yet at \(url.path)" }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: size > UInt64(maxBytes) ? size - UInt64(maxBytes) : 0)
        let data = (try? handle.readToEnd()) ?? Data()
        let lines = String(decoding: data, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: false)
        return lines.suffix(maxLines).joined(separator: "\n")
    }
}
