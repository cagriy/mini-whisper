import AVFAudio
import CoreAudio
import Foundation
import MWTestSupport
import Testing

import MWAudio

@Suite struct SystemAudioTapTests {
    private struct Boom: Error {}

    @available(macOS 14.2, *)
    @Test func aggregateDescriptionIsPrivateWithOneDriftCompensatedTap() throws {
        let description = SystemAudioTap.aggregateDescription(tapUID: "tap-uid", name: "Tap")

        #expect(description[kAudioAggregateDeviceIsPrivateKey] as? Int == 1)
        let taps = try #require(description[kAudioAggregateDeviceTapListKey] as? [[String: Any]])
        #expect(taps.count == 1)
        #expect(taps.first?[kAudioSubTapUIDKey] as? String == "tap-uid")
        #expect(taps.first?[kAudioSubTapDriftCompensationKey] as? Int == 1)
    }

    @Test func factoryReturnsNilWhenTheSystemIsTooOld() {
        #expect(CoreAudioTapFactory(isSupported: { false }).make(excluding: getpid()) == nil)
    }

    @available(macOS 14.2, *)
    @Test func factoryMakesATapOnASupportedSystem() {
        #expect(CoreAudioTapFactory(isSupported: { true }).make(excluding: getpid()) != nil)
    }

    @Test func fakeTapRecordsStartStopAndDeliversBuffers() async throws {
        let factory = FakeSystemAudioTapFactory()
        let tap = try #require(factory.make(excluding: 42) as? FakeSystemAudioTap)
        #expect(factory.excludedPIDs == [42])

        let received = Received()
        try tap.start { received.append($0.frameLength) }
        tap.push(PCMBufferFactory.make(samples: [0.1, 0.2, 0.3], sampleRate: 16000))
        tap.send(.defaultOutputChanged)
        tap.stop()
        tap.push(PCMBufferFactory.make(samples: [0.1], sampleRate: 16000))

        #expect(tap.startCount == 1)
        #expect(tap.stopCount == 1)
        #expect(received.frames == [3])
        var events = tap.events.makeAsyncIterator()
        guard case .defaultOutputChanged = await events.next() else {
            Issue.record("expected .defaultOutputChanged")
            return
        }
    }

    @Test func fakeTapStartThrowsTheConfiguredError() {
        let tap = FakeSystemAudioTap()
        tap.startError = Boom()

        #expect(throws: Boom.self) { try tap.start { _ in } }
        #expect(tap.startCount == 0)
    }

    @Test func fakeFactoryCanReturnNil() {
        let factory = FakeSystemAudioTapFactory(tap: nil)

        #expect(factory.make(excluding: 42) == nil)
        #expect(factory.excludedPIDs == [42])
    }
}

private final class Received: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [AVAudioFrameCount] = []

    func append(_ frames: AVAudioFrameCount) { lock.withLock { storage.append(frames) } }
    var frames: [AVAudioFrameCount] { lock.withLock { storage } }
}
