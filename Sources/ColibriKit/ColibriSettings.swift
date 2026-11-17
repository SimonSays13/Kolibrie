import Foundation

/// A resource/tuning policy Colibri can run under (`--policy` / `COLI_POLICY`).
public enum ColibriPolicy: String, Sendable, CaseIterable {
    case quality, balanced
    case experimentalFast = "experimental-fast"

    public var displayName: String {
        switch self {
        case .quality: return "Quality"
        case .balanced: return "Balanced"
        case .experimentalFast: return "Experimental (fast)"
        }
    }
}

/// How hard a model reasons before answering (`--effort`), for the families that take it.
public enum ReasoningEffort: String, Sendable, CaseIterable {
    case minimal, low, medium, high, xhigh

    public var displayName: String { rawValue == "xhigh" ? "Extra high" : rawValue.capitalized }
}

/// Every setting Kolibrie exposes for a model: the documented `coli` flags (`docs/SETTINGS.md`)
/// as typed fields, plus `COLI_METAL` as a dedicated Apple-Silicon toggle. Anything else Colibri
/// reads — there are hundreds of environment-only knobs, see `docs/ENVIRONMENT.md` — is reachable
/// through `advancedEnvironment`, by name; `EnvironmentVariableCatalog` lists the ones worth
/// knowing about, but any name is accepted.
public struct ColibriSettings: Sendable, Equatable {
    // Resources
    public var ramGB: Int?
    public var contextLength: Int?
    public var cap: Int?
    public var vramGB: Int?
    public var autoTier: Bool

    // Sampling
    public var maxGenerationTokens: Int?
    public var temperature: Double?
    public var topP: Double?
    public var topK: Int?
    public var repin: Int?
    public var policy: ColibriPolicy?
    public var think: Bool?
    public var reasoningEffort: ReasoningEffort?

    // Server
    public var modelAPIID: String?
    public var apiKey: String?
    public var corsOrigins: [String]
    public var allowedHosts: [String]
    public var maxQueue: Int?
    public var queueTimeoutSeconds: Int?
    public var kvSlots: Int?

    // Apple Silicon
    public var useMetal: Bool?

    /// Anything else, by Colibri's own variable name — e.g. `PIPE`, `DIRECT`, `COLI_MMAP`.
    public var advancedEnvironment: [String: String]

    public init(
        ramGB: Int? = nil,
        contextLength: Int? = nil,
        cap: Int? = nil,
        vramGB: Int? = nil,
        autoTier: Bool = false,
        maxGenerationTokens: Int? = nil,
        temperature: Double? = nil,
        topP: Double? = nil,
        topK: Int? = nil,
        repin: Int? = nil,
        policy: ColibriPolicy? = nil,
        think: Bool? = nil,
        reasoningEffort: ReasoningEffort? = nil,
        modelAPIID: String? = nil,
        apiKey: String? = nil,
        corsOrigins: [String] = [],
        allowedHosts: [String] = [],
        maxQueue: Int? = nil,
        queueTimeoutSeconds: Int? = nil,
        kvSlots: Int? = nil,
        useMetal: Bool? = nil,
        advancedEnvironment: [String: String] = [:]
    ) {
        self.ramGB = ramGB
        self.contextLength = contextLength
        self.cap = cap
        self.vramGB = vramGB
        self.autoTier = autoTier
        self.maxGenerationTokens = maxGenerationTokens
        self.temperature = temperature
        self.topP = topP
        self.topK = topK
        self.repin = repin
        self.policy = policy
        self.think = think
        self.reasoningEffort = reasoningEffort
        self.modelAPIID = modelAPIID
        self.apiKey = apiKey
        self.corsOrigins = corsOrigins
        self.allowedHosts = allowedHosts
        self.maxQueue = maxQueue
        self.queueTimeoutSeconds = queueTimeoutSeconds
        self.kvSlots = kvSlots
        self.useMetal = useMetal
        self.advancedEnvironment = advancedEnvironment
    }

    /// The `coli setup` flags these settings translate to. A field left unset produces no flag,
    /// so Colibri's own default applies.
    public var flagArguments: [String] {
        var args: [String] = []
        func add(_ flag: String, _ value: Int?) {
            if let value { args += [flag, String(value)] }
        }
        func add(_ flag: String, _ value: Double?) {
            if let value { args += [flag, String(value)] }
        }
        func add(_ flag: String, _ value: String?) {
            if let value, !value.isEmpty { args += [flag, value] }
        }

        add("--ram", ramGB)
        add("--ctx", contextLength)
        add("--cap", cap)
        add("--vram", vramGB)
        if autoTier { args.append("--auto-tier") }
        add("--ngen", maxGenerationTokens)
        add("--temp", temperature)
        add("--topp", topP)
        add("--topk", topK)
        add("--repin", repin)
        if let policy { args += ["--policy", policy.rawValue] }
        if let think { args.append(think ? "--think" : "--no-think") }
        if let reasoningEffort { args += ["--effort", reasoningEffort.rawValue] }
        add("--model-id", modelAPIID)
        add("--api-key", apiKey)
        for origin in corsOrigins { args += ["--cors-origin", origin] }
        for host in allowedHosts { args += ["--allowed-host", host] }
        add("--max-queue", maxQueue)
        add("--queue-timeout", queueTimeoutSeconds)
        add("--kv-slots", kvSlots)
        return args
    }

    /// Environment variables these settings add: the fields with no flag of their own, plus
    /// `advancedEnvironment`.
    public var environmentOverrides: [String: String] {
        var env = advancedEnvironment
        if let useMetal { env["COLI_METAL"] = useMetal ? "1" : "0" }
        return env
    }

    /// Rebuilds settings from a model's saved `setup.json`: the `args` Colibri was last started
    /// with, and the `env` block alongside them. Used to show the configuration window's current
    /// state before anything is changed.
    public static func parse(args: [String]?, env: [String: String]?) -> ColibriSettings {
        var settings = ColibriSettings()
        var pairs: [String: [String]] = [:]
        var flags: Set<String> = []
        if let args {
            var index = 0
            while index < args.count {
                let token = args[index]
                guard token.hasPrefix("--") else {
                    index += 1
                    continue
                }
                if index + 1 < args.count, !args[index + 1].hasPrefix("--") {
                    pairs[token, default: []].append(args[index + 1])
                    index += 2
                } else {
                    flags.insert(token)
                    index += 1
                }
            }
        }

        settings.ramGB = pairs["--ram"]?.first.flatMap(Int.init)
        settings.contextLength = pairs["--ctx"]?.first.flatMap(Int.init)
        settings.cap = pairs["--cap"]?.first.flatMap(Int.init)
        settings.vramGB = pairs["--vram"]?.first.flatMap(Int.init)
        settings.autoTier = flags.contains("--auto-tier")
        settings.maxGenerationTokens = pairs["--ngen"]?.first.flatMap(Int.init)
        settings.temperature = pairs["--temp"]?.first.flatMap(Double.init)
        settings.topP = pairs["--topp"]?.first.flatMap(Double.init)
        settings.topK = pairs["--topk"]?.first.flatMap(Int.init)
        settings.repin = pairs["--repin"]?.first.flatMap(Int.init)
        settings.policy = pairs["--policy"]?.first.flatMap(ColibriPolicy.init(rawValue:))
        if flags.contains("--think") { settings.think = true }
        if flags.contains("--no-think") { settings.think = false }
        settings.reasoningEffort = pairs["--effort"]?.first.flatMap(ReasoningEffort.init(rawValue:))
        settings.modelAPIID = pairs["--model-id"]?.first
        settings.apiKey = pairs["--api-key"]?.first
        settings.corsOrigins = pairs["--cors-origin"] ?? []
        settings.allowedHosts = pairs["--allowed-host"] ?? []
        settings.maxQueue = pairs["--max-queue"]?.first.flatMap(Int.init)
        settings.queueTimeoutSeconds = pairs["--queue-timeout"]?.first.flatMap(Int.init)
        settings.kvSlots = pairs["--kv-slots"]?.first.flatMap(Int.init)

        var remainingEnv = env ?? [:]
        if let metal = remainingEnv.removeValue(forKey: "COLI_METAL") {
            settings.useMetal = metal == "1"
        }
        settings.advancedEnvironment = remainingEnv
        return settings
    }
}
