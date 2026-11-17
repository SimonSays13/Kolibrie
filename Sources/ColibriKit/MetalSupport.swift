import Foundation

/// How much of a Colibri engine's compute can run on Apple's Metal GPU, as Colibri's own
/// project documents it (README.md, docs/metal.md, CHANGELOG.md) — never as `coli doctor`
/// reports it. Doctor's `accelerator.gpu` check (see `Doctor.swift`) has no Metal awareness at
/// all: its own source (`c/doctor.py`) only branches on CUDA/Vulkan linkage, so it reports
/// "GPU detected but the engine is CPU-only" for every Apple Silicon build, Metal-capable or
/// not. This catalogue is the only place that knows which families can use Metal at all; it has
/// to be kept in step by hand when Colibri ships a new Metal family or finishes an existing one.
public enum MetalFamilySupport: Sendable, Equatable {
    /// Every matmul that matters, including the routed-expert MoE, can run on the GPU.
    case full(String)
    /// Attention and projections can run on the GPU; the routed-expert MoE still runs on the
    /// CPU, which is most of the cost for a sparse model.
    case partial(String)
    /// No Metal code path exists for this family; it always runs on the CPU.
    case unsupported

    public var isCapable: Bool {
        switch self {
        case .full, .partial: return true
        case .unsupported: return false
        }
    }

    public var detail: String? {
        switch self {
        case .full(let text), .partial(let text): return text
        case .unsupported: return nil
        }
    }
}

/// Curated against Colibri 2.1.0 (this repo's vendored copy, reviewed 2026-11-17).
/// `README.md`/`docs/metal.md` list the three engines the macOS Metal release archive actually
/// builds (`colibri`, `inkling`, `kimi_k3` — family ids `glm`, `inkling`, `kimi`);
/// `CHANGELOG.md`'s `#1462` and `#790`->`#1113` entries say how much of each engine's own compute
/// actually moves to the GPU. Kimi K3's routed-expert MoE is tracked upstream but not done as of
/// this build (`docs/kimi_metal_gap_analysis.md`), hence `.partial` rather than `.full`.
public enum MetalSupportCatalog {
    public static func support(for familyID: String?) -> MetalFamilySupport {
        switch familyID {
        case "glm":
            return .full(
                "Routed-expert MoE, attention and prefill all run on Metal (GLM-5.3-Flash, Colibri #1462).")
        case "inkling":
            return .full(
                "Batched expert MoE runs on Metal; shipped in Colibri's macOS Metal release archive.")
        case "kimi":
            return .partial(
                "Attention and projections run on Metal (Colibri #790->#1113); the routed-expert "
                    + "MoE - most of this model's cost - still runs on the CPU.")
        default:
            return .unsupported
        }
    }

    public static func isMetalCapable(familyID: String?) -> Bool {
        support(for: familyID).isCapable
    }
}

/// Whether a model's own server process has actually engaged Metal, read from its own stderr
/// lines rather than from `coli doctor` (which, per `MetalSupportCatalog`'s doc comment, can't
/// see Metal at all). Each Metal-capable engine prints its own distinct marker when it attempts,
/// succeeds at, fails, or skips Metal init; these are read directly from `colibri.c`,
/// `inkling.c` and `kimi_k3.c`, not guessed.
public enum MetalEngagement: Sendable, Equatable {
    case confirmedActive(String)
    case confirmedInactive(String)
    /// The family can use Metal, but nothing in the current log says whether it did - most
    /// likely this model hasn't been started since Metal was configured for it.
    case notObserved
    /// This family has no Metal code path at all (see `MetalFamilySupport.unsupported`).
    case notApplicable
}

public enum MetalLogSignal {
    /// `log` is the model's own serve log (or as much of its tail as was read).
    public static func engagement(familyID: String?, log: String) -> MetalEngagement {
        guard MetalSupportCatalog.isMetalCapable(familyID: familyID) else { return .notApplicable }
        switch familyID {
        case "glm":
            if log.contains("[METAL] mode:") {
                return .confirmedActive("Metal routed-expert MoE is active.")
            }
            if log.contains("[METAL] backend requested but not available") {
                return .confirmedInactive("Metal was requested but failed to initialize.")
            }
        case "inkling":
            if log.contains("[metal] ready") {
                return .confirmedActive("Metal routed-expert MoE is active.")
            }
            if log.contains("[metal] init failed") {
                return .confirmedInactive("Metal was requested but failed to initialize.")
            }
        case "kimi":
            if log.contains("[K3-METAL] init OK") {
                return .confirmedActive(
                    "Metal attention and projections are active (MoE experts still run on the CPU).")
            }
            if log.contains("[K3-METAL] FAILED") {
                return .confirmedInactive("Metal was requested but failed to initialize.")
            }
            if log.contains("[K3-METAL] KV_SLOTS=") {
                return .confirmedInactive(
                    "Metal was skipped: more than one KV conversation slot is configured.")
            }
        default:
            break
        }
        return .notObserved
    }
}
