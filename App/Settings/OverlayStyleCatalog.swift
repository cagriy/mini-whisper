import MWOverlaySim

/// The Overlay pane's six rows: the accepted mockup's display order, with the
/// title and one-line summary each style is described by (design §5.4).
@MainActor
enum OverlayStyleCatalog {
    static let rows: [SettingsModel.OverlayStyleRow] = [
        row(.softMeter, "Soft meter", "Fifteen rounded strokes. Familiar audio feedback, softened and kept compact."),
        row(.silkRibbon, "Silk ribbon", "Three fine strands breathe as one. The smallest visual footprint of the set."),
        row(.resonantHalo, "Resonant halo", "A thin, imperfect circle. Voice becomes a change in contour, not a burst."),
        row(.liquidPearl, "Liquid pearl", "One luminous, fluid body. A soft centre of gravity instead of a field of marks."),
        row(.petalIris, "Petal iris", "Six tapered loops form an open centre. A mechanical rhythm with an organic outline."),
        row(.constellation, "Constellation", "A connected field of particles. Organic, spatial, and deliberately restless."),
    ]

    private static func row(
        _ style: OverlayStyle, _ title: String, _ summary: String
    ) -> SettingsModel.OverlayStyleRow {
        SettingsModel.OverlayStyleRow(
            style: style, title: title, summary: summary, isDefault: style == .default
        )
    }
}
