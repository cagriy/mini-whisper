import Foundation
import Testing
@testable import MiniWhisper

private final class FakeSoundHandle: SoundHandle, @unchecked Sendable {
    enum Call: Equatable {
        case stop
        case volume(Float)
        case play
    }

    private let lock = NSLock()
    private var storage: [Call] = []

    var calls: [Call] { lock.withLock { storage } }

    func play() { append(.play) }
    func stop() { append(.stop) }
    func setVolume(_ volume: Float) { append(.volume(volume)) }

    private func append(_ call: Call) { lock.withLock { storage.append(call) } }
}

private final class FakeSoundLoader: SoundLoading, @unchecked Sendable {
    private let lock = NSLock()
    private var bundled: [String: FakeSoundHandle] = [:]
    private var system: [String: FakeSoundHandle] = [:]
    private var requests: [String] = []

    var requestedNames: [String] { lock.withLock { requests } }

    func handle(bundled name: String) -> FakeSoundHandle {
        lock.withLock {
            if let existing = bundled[name] { return existing }
            let handle = FakeSoundHandle()
            bundled[name] = handle
            return handle
        }
    }

    func handle(system name: String) -> FakeSoundHandle {
        lock.withLock {
            if let existing = system[name] { return existing }
            let handle = FakeSoundHandle()
            system[name] = handle
            return handle
        }
    }

    func bundledSound(named name: String) -> (any SoundHandle)? {
        lock.withLock { requests.append("bundled:\(name)") }
        return handle(bundled: name)
    }

    func systemSound(named name: String) -> (any SoundHandle)? {
        lock.withLock { requests.append("system:\(name)") }
        return handle(system: name)
    }
}

@Suite struct SoundPlayerTests {
    private func makePlayer(_ loader: FakeSoundLoader) -> SoundPlayer {
        SoundPlayer(loader: loader, dispatch: { $0() })
    }

    @Test func volumeClampedAndApplied() {
        let loader = FakeSoundLoader()
        let player = makePlayer(loader)

        player.setVolume(1.5)
        player.playOn()
        #expect(loader.handle(bundled: "on").calls == [.stop, .volume(1.0), .play])

        player.setVolume(-0.5)
        player.playOff()
        #expect(loader.handle(bundled: "off").calls == [.stop, .volume(0.0), .play])

        player.setVolume(0.4)
        player.playOff()
        #expect(loader.handle(bundled: "off").calls.suffix(3) == [.stop, .volume(0.4), .play])
    }

    @Test func tickUsesSystemSoundTink() {
        let loader = FakeSoundLoader()
        let player = makePlayer(loader)

        player.playTick()
        #expect(loader.handle(system: "Tink").calls == [.stop, .volume(1.0), .play])
        #expect(loader.requestedNames == ["bundled:on", "bundled:off", "system:Tink"])
    }

    @Test func playStopsBeforeReplay() {
        let loader = FakeSoundLoader()
        let player = makePlayer(loader)

        player.playOn()
        player.playOn()
        #expect(loader.handle(bundled: "on").calls == [
            .stop, .volume(1.0), .play,
            .stop, .volume(1.0), .play,
        ])
    }
}
