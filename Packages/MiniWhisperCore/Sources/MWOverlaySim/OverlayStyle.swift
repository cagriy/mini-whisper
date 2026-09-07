/// Which animation the recording card draws. Stored in `config.json` under `overlay_style`
/// (design §5.2); an absent or unrecognised value resolves to `default`.
public enum OverlayStyle: String, Codable, CaseIterable, Sendable {
    case constellation
    case silkRibbon = "silk_ribbon"
    case resonantHalo = "resonant_halo"
    case softMeter = "soft_meter"
    case liquidPearl = "liquid_pearl"
    case petalIris = "petal_iris"

    public static let `default` = OverlayStyle.softMeter
}
