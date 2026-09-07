import MWOverlaySim
import Testing
@testable import MiniWhisper

/// The Overlay pane's six rows, in the accepted mockup's order (design §5.4).
@Suite @MainActor struct OverlayStyleCatalogTests {
    @Test func rowsInTheAcceptedOrder() {
        #expect(OverlayStyleCatalog.rows.map(\.style) == [
            .softMeter, .silkRibbon, .resonantHalo, .liquidPearl, .petalIris, .constellation,
        ])
    }

    @Test func everyRowHasATitleAndSummary() {
        for row in OverlayStyleCatalog.rows {
            #expect(!row.title.isEmpty)
            #expect(!row.summary.isEmpty)
        }
    }

    @Test func exactlyOneRowIsDefault() {
        #expect(OverlayStyleCatalog.rows.filter(\.isDefault).map(\.style) == [OverlayStyle.default])
    }

    @Test func everyOverlayStyleHasARow() {
        #expect(Set(OverlayStyleCatalog.rows.map(\.style)) == Set(OverlayStyle.allCases))
    }
}
