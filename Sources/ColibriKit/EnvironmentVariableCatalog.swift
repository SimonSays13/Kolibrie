import Foundation

/// A documented Colibri environment variable the Advanced editor can suggest by name. Setting
/// any variable — listed here or not — always works; this catalogue, drawn from
/// `docs/ENVIRONMENT.md`, is what the "Add variable…" picker offers with a one-line reminder of
/// what it does, scoped to the knobs worth knowing about on an Apple-Silicon Mac.
public struct EnvironmentVariableInfo: Sendable, Equatable, Identifiable {
    public var id: String { name }
    public var name: String
    public var defaultValue: String
    public var summary: String
    public var group: String

    public init(name: String, defaultValue: String, summary: String, group: String) {
        self.name = name
        self.defaultValue = defaultValue
        self.summary = summary
        self.group = group
    }
}

public enum EnvironmentVariableCatalog {
    public static let variables: [EnvironmentVariableInfo] = [
        // Apple Silicon / Metal
        .init(
            name: "COLI_METAL_PREFILL", defaultValue: "0",
            summary: "Also run prompt-prefill attention on the Metal GPU, not just decode.",
            group: "Apple Silicon"),
        .init(
            name: "COLI_METAL_SPIN", defaultValue: "off",
            summary: "Keep the GPU spun up between requests for lower latency; costs power.",
            group: "Apple Silicon"),
        .init(
            name: "COLI_METAL_RESSET", defaultValue: "off",
            summary: "Use macOS 15's MTLResidencySet for resident buffers instead of per-dispatch calls.",
            group: "Apple Silicon"),
        .init(
            name: "MLOCK", defaultValue: "-1 (auto: on for macOS)",
            summary: "Wire the expert cache into physical RAM so macOS can't compress it.",
            group: "Apple Silicon"),
        .init(
            name: "COLI_SSD_FAST_GBS", defaultValue: "4.0",
            summary: "GB/s threshold above which the model's drive counts as \"fast\" for Metal cache sizing.",
            group: "Apple Silicon"),

        // Disk & I/O
        .init(
            name: "PIPE", defaultValue: "0",
            summary: "Overlap expert disk-loads with matmul using worker threads.", group: "Disk & I/O"),
        .init(
            name: "PIPE_WORKERS", defaultValue: "8", summary: "Number of loader threads when PIPE=1.",
            group: "Disk & I/O"),
        .init(
            name: "DIRECT", defaultValue: "0",
            summary: "Use unbuffered reads for expert data; measure it, it's drive-dependent.",
            group: "Disk & I/O"),
        .init(
            name: "COLI_MMAP", defaultValue: "0",
            summary: "Map routed experts read-only from disk instead of copying them into RAM.",
            group: "Disk & I/O"),
        .init(
            name: "TRUNK_RESIDENT_LAYERS", defaultValue: "unset (whole trunk resident)",
            summary: "Keep only the top N layers' dense weights resident; the rest map from disk.",
            group: "Disk & I/O"),
        .init(
            name: "COLI_MODEL_DIRS", defaultValue: "unset",
            summary: "Split a model's shards across two or more drives (semicolon/comma-separated).",
            group: "Disk & I/O"),
        .init(
            name: "COLI_MODEL_MIRROR", defaultValue: "unset",
            summary: "Mirror directories to read experts from in parallel with the primary drive.",
            group: "Disk & I/O"),

        // Expert cache
        .init(
            name: "CAP_RAISE", defaultValue: "1 (0 on fast Metal + macOS)",
            summary: "Let the expert-cache cap grow above top-k when RAM allows.", group: "Expert cache"),
        .init(
            name: "RSS_GUARD_GB", defaultValue: "the RAM budget",
            summary: "Resident-set ceiling that trims the cache if crossed.", group: "Expert cache"),
        .init(
            name: "PIN", defaultValue: "unset",
            summary: "Pin the hottest experts resident at startup; PIN=auto uses this model's usage history.",
            group: "Expert cache"),
        .init(
            name: "PIN_GB", defaultValue: "10.0", summary: "Size budget (GB) for the pinned hot store.",
            group: "Expert cache"),
        .init(
            name: "AUTOPIN", defaultValue: "1",
            summary: "Auto-pin from usage history once enough selections are recorded.", group: "Expert cache"),
        .init(
            name: "CACHE_ROUTE", defaultValue: "0",
            summary: "Cache-aware MoE routing that prefers already-resident experts.", group: "Expert cache"),

        // KV cache
        .init(
            name: "KVSAVE", defaultValue: "1",
            summary: "Persist the KV cache to disk so a conversation reopens warm.", group: "KV cache"),
        .init(
            name: "KV8", defaultValue: "0",
            summary: "Store the KV cache in fp8 instead of fp16/fp32: much less RAM, some precision cost.",
            group: "KV cache"),
        .init(
            name: "KV_TQ", defaultValue: "0",
            summary: "Sub-byte KV cache quantization (KV_TQ=4 recommended); saves more RAM than KV8.",
            group: "KV cache"),

        // Sampling
        .init(
            name: "SEED", defaultValue: "unset (random)",
            summary: "Fix the RNG seed for reproducible sampling.", group: "Sampling"),
        .init(
            name: "NUCLEUS", defaultValue: "0.90",
            summary: "Nucleus (top-p) mass kept when no --topp flag is given.", group: "Sampling"),
        .init(
            name: "MTP", defaultValue: "on", summary: "Multi-token speculative draft head. MTP=0 disables it.",
            group: "Sampling"),

        // Server
        .init(
            name: "COLI_DEBUG", defaultValue: "0",
            summary: "Tee the model's input/output to stderr (1=output, 2=prompt and output too).",
            group: "Server"),
        .init(
            name: "COLI_TOOL_SALVAGE", defaultValue: "0",
            summary: "Reconstruct malformed int4 tool calls instead of failing them.", group: "Server"),
        .init(
            name: "COLI_THINK", defaultValue: "0",
            summary: "Make reasoning the default when a client sends neither reasoning_effort nor enable_thinking.",
            group: "Server"),
        .init(
            name: "COLI_COMPACT", defaultValue: "0",
            summary: "Auto-summarize and continue a conversation that outgrows the context instead of erroring.",
            group: "Server"),
        .init(
            name: "COLI_CHAT_STATS", defaultValue: "full",
            summary: "What `coli chat` prints after each answer: full, compact, or off.", group: "Server"),
        .init(
            name: "COLI_IMAGE_ROOT", defaultValue: "unset (local paths denied)",
            summary: "Directory under which image_url.url may name a local path.", group: "Server"),

        // CPU & threading
        .init(
            name: "COLI_NO_OMP_TUNE", defaultValue: "off",
            summary: "Disable OpenMP hot-thread tuning — useful when Metal does the work and the CPU should idle.",
            group: "CPU & threading"),
        .init(
            name: "OMP_NUM_THREADS", defaultValue: "unset",
            summary: "Standard OpenMP thread count; setting it hands thread tuning entirely to you.",
            group: "CPU & threading"),
    ]

    public static var groups: [String] {
        var seen: [String] = []
        for variable in variables where !seen.contains(variable.group) { seen.append(variable.group) }
        return seen
    }
}
