import CoreGraphics
import Testing
@testable import MiniWhisper

/// When a Timeline panel plays, and how its motion runs (design §5, "A panel plays").
@Suite struct PanelPlaybackTests {
    private enum Panel: Hashable { case totals, year, rhythm, talk }

    private typealias Playback = PanelPlayback<Panel>

    private let viewport = CGRect(x: 0, y: 0, width: 672, height: 600)

    private func panel(at y: CGFloat, height: CGFloat = 100) -> CGRect {
        CGRect(x: 0, y: y, width: 672, height: height)
    }

    @Test func aPanelPlaysOnceAFifthOfItsHeightIsInView() {
        #expect(Playback.shouldPlay(panel(at: 580), in: viewport))
        #expect(!Playback.shouldPlay(panel(at: 581), in: viewport))
        #expect(Playback.shouldPlay(panel(at: -80), in: viewport))
        #expect(!Playback.shouldPlay(panel(at: -81), in: viewport))

        var playback = Playback()
        let atNineteen = playback.update([.year: panel(at: 581)], in: viewport)
        #expect(!atNineteen)
        #expect(!playback.play(.year).played)

        let atTwenty = playback.update([.year: panel(at: 580)], in: viewport)
        #expect(atTwenty)
        #expect(playback.play(.year).played)
    }

    @Test func aPlayedPanelStaysPlayedAfterScrollingAway() {
        var playback = Playback()
        playback.update([.year: panel(at: 100)], in: viewport)

        let away = playback.update([.year: panel(at: -900)], in: viewport)
        let back = playback.update([.year: panel(at: 100)], in: viewport)

        #expect(!away)
        #expect(!back)
        #expect(playback.play(.year).played)
    }

    @Test func aNewPlayIDClearsThePlayedSet() {
        var playback = Playback()
        playback.replay(1)
        playback.update([.year: panel(at: 100)], in: viewport)

        playback.replay(1)
        #expect(playback.play(.year).played)

        playback.replay(2)
        #expect(!playback.play(.year).played)
        let again = playback.update([.year: panel(at: 100)], in: viewport)
        #expect(again)
    }

    @Test func reduceMotionCountsEveryPanelAsPlayed() {
        var playback = Playback(reduceMotion: true)
        playback.replay(1)
        #expect(playback.play(.talk) == .final)

        let changed = playback.update([.talk: panel(at: 2000)], in: viewport)
        #expect(!changed)
        #expect(playback.play(.talk) == .final)
    }

    @Test func panelsInViewAtOpeningStart80msApart() {
        var playback = Playback()
        playback.replay(1)
        playback.update(
            [.rhythm: panel(at: 420), .totals: panel(at: 0), .year: panel(at: 180), .talk: panel(at: 700)],
            in: viewport
        )

        #expect([Panel.totals, .year, .rhythm].map { playback.play($0) } == [
            TimelinePlay(played: true, delay: 0),
            TimelinePlay(played: true, delay: 0.08),
            TimelinePlay(played: true, delay: 0.16),
        ])
        #expect(!playback.play(.talk).played)

        playback.update([.talk: panel(at: 450)], in: viewport)
        #expect(playback.play(.talk) == TimelinePlay(played: true, delay: 0))
    }

    @Test func motionMatchesTheDesign() {
        let tracks = [TimelineMotion.count, TimelineMotion.verticalBars, TimelineMotion.horizontalBars, TimelineMotion.fade]

        #expect(tracks.map(\.duration) == [0.9, 0.6, 0.7, 0.45])
        #expect(tracks.map(\.stagger) == [0, 0.018, 0.045, 0.012])
        #expect(TimelineMotion.panelStagger == 0.08)
        #expect(TimelineMotion.playThreshold == 0.2)
    }

    @Test func anItemMovesAfterItsStaggerAndStopsAtItsDuration() {
        let bars = TimelineMotion.verticalBars

        #expect(bars.progress(at: 0.036, item: 2) == 0)
        #expect(bars.progress(at: 0.336, item: 2) > 0.5)
        #expect(bars.progress(at: 0.64, item: 2) == 1)
        #expect(bars.progress(at: 5, item: 2) == 1)
        #expect(abs(bars.length(items: 12) - 0.798) < 1e-9)
        #expect(bars.length(items: 0) == 0)
    }
}
