import ColibriKit
import SwiftUI

/// Every Colibri setting Kolibrie exposes for one model: the documented `coli` flags as typed
/// controls, plus an "Advanced" table of environment variables for anything else.
struct ConfigureModelView: View {
    let app: AppModel
    let modelID: String?
    @Environment(\.dismiss) private var dismiss

    @State private var settings = ColibriSettings()
    @State private var loaded = false
    @State private var newVariableName = ""
    @State private var newVariableValue = ""

    private var controller: ModelController? { app.controllers.first { $0.id == modelID } }

    var body: some View {
        if let controller {
            Form {
                Section("Resources") {
                    optionalIntField("RAM budget (GB)", value: $settings.ramGB, placeholder: "auto")
                    optionalIntField("Context length (tokens)", value: $settings.contextLength, placeholder: "auto")
                    optionalIntField("Expert-cache cap", value: $settings.cap, placeholder: "auto")
                    optionalIntField("VRAM budget (GB)", value: $settings.vramGB, placeholder: "auto")
                    Toggle("Apply the computed RAM/VRAM placement plan automatically", isOn: $settings.autoTier)
                }
                Section("Apple Silicon") {
                    Picker(
                        "Metal GPU backend",
                        selection: Binding(
                            get: { settings.useMetal.map { $0 ? "on" : "off" } ?? "default" },
                            set: { settings.useMetal = $0 == "default" ? nil : $0 == "on" }
                        )
                    ) {
                        Text("Colibri's default").tag("default")
                        Text("On").tag("on")
                        Text("Off").tag("off")
                    }
                    Text("Offloads matmuls to the GPU on Apple Silicon. See the Advanced section for related tuning.")
                        .font(.caption).foregroundStyle(.secondary)
                    metalStatusRow(controller)
                }
                Section("Sampling") {
                    optionalIntField(
                        "Max tokens to generate", value: $settings.maxGenerationTokens, placeholder: "auto")
                    optionalDoubleField("Temperature", value: $settings.temperature, placeholder: "model default")
                    optionalDoubleField("Top-p", value: $settings.topP, placeholder: "off")
                    optionalIntField("Top-k", value: $settings.topK, placeholder: "off")
                    optionalIntField("Re-pin every N tokens", value: $settings.repin, placeholder: "off")
                    Picker(
                        "Resource policy",
                        selection: Binding(
                            get: { settings.policy }, set: { settings.policy = $0 }
                        )
                    ) {
                        Text("Colibri's default").tag(ColibriPolicy?.none)
                        ForEach(ColibriPolicy.allCases, id: \.self) { policy in
                            Text(policy.displayName).tag(ColibriPolicy?.some(policy))
                        }
                    }
                    Picker(
                        "Reasoning",
                        selection: Binding(
                            get: {
                                settings.think.map { $0 ? "on" : "off" } ?? "default"
                            },
                            set: { settings.think = $0 == "default" ? nil : $0 == "on" }
                        )
                    ) {
                        Text("Model's default").tag("default")
                        Text("On").tag("on")
                        Text("Off").tag("off")
                    }
                    Picker(
                        "Reasoning effort",
                        selection: Binding(
                            get: { settings.reasoningEffort }, set: { settings.reasoningEffort = $0 }
                        )
                    ) {
                        Text("Model's default").tag(ReasoningEffort?.none)
                        ForEach(ReasoningEffort.allCases, id: \.self) { effort in
                            Text(effort.displayName).tag(ReasoningEffort?.some(effort))
                        }
                    }
                }
                Section("Server") {
                    optionalTextField("Model ID reported by the API", value: $settings.modelAPIID, placeholder: "auto")
                    optionalTextField("Require an API key", value: $settings.apiKey, placeholder: "none")
                    optionalIntField("Max queued requests", value: $settings.maxQueue, placeholder: "8")
                    optionalIntField(
                        "Queue timeout (seconds)", value: $settings.queueTimeoutSeconds, placeholder: "300")
                    optionalIntField("KV conversation slots", value: $settings.kvSlots, placeholder: "1")
                    stringListField("CORS origins", values: $settings.corsOrigins)
                    stringListField("Additional allowed hosts", values: $settings.allowedHosts)
                }
                Section("Advanced environment variables") {
                    advancedTable
                }
                if let message = controller.message {
                    Section {
                        Text(message).font(.caption).foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)
            .frame(width: 560, height: 640)
            .overlay(alignment: .bottom) { actionBar(controller) }
            .task {
                if !loaded {
                    settings = controller.currentSettings
                    loaded = true
                }
            }
        } else {
            Text("This model is no longer installed.").padding(20)
        }
    }

    // MARK: Apple Silicon status

    /// Two separate facts, never conflated: what Colibri's project documents this model's
    /// family as able to do on Metal (`metalSupport`, curated by hand \u{2014} `coli doctor` has no
    /// Metal awareness on macOS, see `MetalSupport.swift`), and whether this model's own server
    /// has actually engaged it, read live from its serve log (`metalEngagement`).
    @ViewBuilder private func metalStatusRow(_ controller: ModelController) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let detail = controller.metalSupport.detail {
                Label(detail, systemImage: "info.circle").foregroundStyle(.secondary)
            }
            switch controller.metalEngagement {
            case .confirmedActive(let detail):
                Label(detail, systemImage: "bolt.fill").foregroundStyle(.green)
            case .confirmedInactive(let detail):
                Label(detail, systemImage: "bolt.trianglebadge.exclamationmark").foregroundStyle(.orange)
            case .notObserved:
                Label(
                    "Not yet confirmed \u{2014} start the model, then reopen this window, to check its own log.",
                    systemImage: "bolt")
            case .notApplicable:
                Label("No Metal backend exists for this model's family yet.", systemImage: "bolt.slash")
            }
        }
        .font(.caption).foregroundStyle(.secondary)
    }

    // MARK: Advanced table

    @ViewBuilder private var advancedTable: some View {
        if settings.advancedEnvironment.isEmpty {
            Text("Nothing set. Pick a known variable or type one of your own below.")
                .font(.caption).foregroundStyle(.secondary)
        }
        ForEach(settings.advancedEnvironment.keys.sorted(), id: \.self) { key in
            HStack {
                Text(key).font(.system(.body, design: .monospaced)).lineLimit(1)
                TextField(
                    "value",
                    text: Binding(
                        get: { settings.advancedEnvironment[key] ?? "" },
                        set: { settings.advancedEnvironment[key] = $0 }
                    )
                )
                Button {
                    settings.advancedEnvironment.removeValue(forKey: key)
                } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.plain)
            }
        }
        HStack {
            Menu("Add known variable…") {
                ForEach(EnvironmentVariableCatalog.groups, id: \.self) { group in
                    Menu(group) {
                        ForEach(EnvironmentVariableCatalog.variables.filter { $0.group == group }) { variable in
                            Button(variable.name) {
                                if settings.advancedEnvironment[variable.name] == nil {
                                    settings.advancedEnvironment[variable.name] = ""
                                }
                            }
                            .help(variable.summary)
                        }
                    }
                }
            }
            Spacer()
        }
        HStack {
            TextField("VARIABLE_NAME", text: $newVariableName)
                .font(.system(.body, design: .monospaced))
            TextField("value", text: $newVariableValue)
            Button("Add") {
                let name = newVariableName.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return }
                settings.advancedEnvironment[name] = newVariableValue
                newVariableName = ""
                newVariableValue = ""
            }
            .disabled(newVariableName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    // MARK: Action bar

    @ViewBuilder private func actionBar(_ controller: ModelController) -> some View {
        HStack {
            Spacer()
            Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            if controller.isApplyingSettings {
                ProgressView().controlSize(.small)
            } else {
                Button("Save and Restart") {
                    Task {
                        if await controller.applySettings(settings) { dismiss() }
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
        .background(.bar)
    }

    // MARK: Field helpers

    private func optionalIntField(_ title: String, value: Binding<Int?>, placeholder: String) -> some View {
        TextField(
            title,
            text: Binding(
                get: { value.wrappedValue.map(String.init) ?? "" },
                set: { value.wrappedValue = $0.isEmpty ? nil : Int($0) }
            ), prompt: Text(placeholder)
        )
    }

    private func optionalDoubleField(_ title: String, value: Binding<Double?>, placeholder: String) -> some View {
        TextField(
            title,
            text: Binding(
                get: { value.wrappedValue.map { String($0) } ?? "" },
                set: { value.wrappedValue = $0.isEmpty ? nil : Double($0) }
            ), prompt: Text(placeholder)
        )
    }

    private func optionalTextField(_ title: String, value: Binding<String?>, placeholder: String) -> some View {
        TextField(
            title,
            text: Binding(
                get: { value.wrappedValue ?? "" },
                set: { value.wrappedValue = $0.isEmpty ? nil : $0 }
            ), prompt: Text(placeholder)
        )
    }

    private func stringListField(_ title: String, values: Binding<[String]>) -> some View {
        TextField(
            title,
            text: Binding(
                get: { values.wrappedValue.joined(separator: ", ") },
                set: {
                    values.wrappedValue = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                }
            ), prompt: Text("comma-separated")
        )
    }
}
