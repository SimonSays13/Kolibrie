import Testing

@testable import ColibriKit

@Suite("Metal support catalogue and log-based engagement")
struct MetalSupportTests {
    @Test func onlyTheThreeDocumentedFamiliesAreMetalCapable() {
        #expect(MetalSupportCatalog.isMetalCapable(familyID: "glm"))
        #expect(MetalSupportCatalog.isMetalCapable(familyID: "inkling"))
        #expect(MetalSupportCatalog.isMetalCapable(familyID: "kimi"))
        #expect(!MetalSupportCatalog.isMetalCapable(familyID: "qwen38"))
        #expect(!MetalSupportCatalog.isMetalCapable(familyID: "deepseek_v41"))
        #expect(!MetalSupportCatalog.isMetalCapable(familyID: nil))
    }

    @Test func kimiIsPartialNotFull() {
        #expect(MetalSupportCatalog.support(for: "kimi").isCapable)
        if case .partial = MetalSupportCatalog.support(for: "kimi") {
        } else {
            Issue.record("Kimi K3's MoE experts still run on the CPU; this should be .partial.")
        }
    }

    @Test func glmAndInklingAreFull() {
        if case .full = MetalSupportCatalog.support(for: "glm") {} else { Issue.record("expected .full") }
        if case .full = MetalSupportCatalog.support(for: "inkling") {} else { Issue.record("expected .full") }
    }

    @Test func unsupportedFamilyIsNeverApplicable() {
        #expect(MetalLogSignal.engagement(familyID: "qwen38", log: "[METAL] mode: anything") == .notApplicable)
        #expect(MetalLogSignal.engagement(familyID: nil, log: "") == .notApplicable)
    }

    @Test func glmMarkersAreRecognized() {
        if case .confirmedActive = MetalLogSignal.engagement(
            familyID: "glm", log: "[METAL] mode: batched routed experts")
        {
        } else {
            Issue.record("expected confirmedActive")
        }
        if case .confirmedInactive = MetalLogSignal.engagement(
            familyID: "glm", log: "[METAL] backend requested but not available")
        {
        } else {
            Issue.record("expected confirmedInactive")
        }
        #expect(MetalLogSignal.engagement(familyID: "glm", log: "ordinary log line") == .notObserved)
    }

    @Test func inklingMarkersAreRecognized() {
        if case .confirmedActive = MetalLogSignal.engagement(
            familyID: "inkling", log: "[metal] ready — batched expert MoE on the Apple GPU")
        {
        } else {
            Issue.record("expected confirmedActive")
        }
        if case .confirmedInactive = MetalLogSignal.engagement(
            familyID: "inkling", log: "[metal] init failed, running on CPU")
        {
        } else {
            Issue.record("expected confirmedInactive")
        }
    }

    @Test func kimiMarkersAreRecognized() {
        if case .confirmedActive = MetalLogSignal.engagement(
            familyID: "kimi", log: "[K3-METAL] init OK (fused KDA token GPU)")
        {
        } else {
            Issue.record("expected confirmedActive")
        }
        if case .confirmedInactive = MetalLogSignal.engagement(familyID: "kimi", log: "[K3-METAL] FAILED — CPU only") {
        } else {
            Issue.record("expected confirmedInactive for FAILED")
        }
        if case .confirmedInactive = MetalLogSignal.engagement(
            familyID: "kimi", log: "[K3-METAL] KV_SLOTS=4: Metal keeps one conversation's KDA state; CPU only")
        {
        } else {
            Issue.record("expected confirmedInactive for KV_SLOTS>1")
        }
        #expect(MetalLogSignal.engagement(familyID: "kimi", log: "no metal mention at all") == .notObserved)
    }
}
