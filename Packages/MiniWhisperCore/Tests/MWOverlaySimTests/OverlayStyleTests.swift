import Testing

import MWOverlaySim

/// The six overlay styles and the `overlay_style` raw values `config.json` stores
/// (design §3 R1, §5.2).
@Suite struct OverlayStyleTests {
    @Test func sixCasesInDeclarationOrderWithPythonRawValues() {
        #expect(
            OverlayStyle.allCases.map(\.rawValue) == [
                "constellation", "silk_ribbon", "resonant_halo",
                "soft_meter", "liquid_pearl", "petal_iris",
            ]
        )
    }

    @Test func defaultIsSoftMeter() {
        #expect(OverlayStyle.default == .softMeter)
    }
}
