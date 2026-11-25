import SwiftUI
import Testing
@testable import MiniWhisper

@MainActor
@Suite struct SettingRowTests {
    @Test func aRowCarriesTheBadgeBesideItsTitle() {
        let row = SettingRow("Suggest names from the conversation", badge: "Experimental") { EmptyView() }
        #expect(row.badge == "Experimental")
    }

    @Test func aRowHasNoBadgeByDefault() {
        #expect(SettingRow("Sound") { EmptyView() }.badge == nil)
    }
}
