import AppKit
import SwiftUI
import Testing
@testable import MiniWhisper

/// R24's sizes and closability. The windows are built, never shown.
@MainActor
@Suite struct SmallWindowsTests {
    @Test func aboutIs300By300AndClosesFromItsCloseButton() {
        let window = AboutWindowController().window

        #expect(window.frame.size == CGSize(width: 300, height: 300))
        #expect(window.styleMask.contains(.titled))
        #expect(window.styleMask.contains(.closable))
        #expect(!window.styleMask.contains(.resizable))
    }

    @Test func onboardingIs460By330AndCannotBeClosed() {
        let onboarding = OnboardingWindowController(onContinue: {})
        let window = onboarding.window

        #expect(window.frame.size == CGSize(width: 460, height: 330))
        #expect(window.styleMask.contains(.titled))
        #expect(!window.styleMask.contains(.closable))
        #expect(!window.styleMask.contains(.fullSizeContentView))
        #expect(!onboarding.windowShouldClose(window))
    }

    /// Correction is as tall as its content at each show; the hosting view reports no fitting size
    /// once it no longer sizes the window, so the order matters.
    @Test func hostingToFitTakesTheContentSizeAndKeepsTheTopEdge() {
        let window = NSWindow.small(title: "Fit", size: CGSize(width: 560, height: 600))
        let top = window.frame.maxY

        window.host(Color.clear.frame(width: 560, height: 432), fit: true)

        #expect(window.contentLayoutRect.size == CGSize(width: 560, height: 432))
        #expect(window.frame.maxY == top)
    }
}
