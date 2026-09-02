import AppKit
import MWPipeline
import MWSupport
import os

/// One playable sound. `NSSound` is not `Sendable`, so the seam is deliberately
/// narrow: every call is made on the main thread by `SoundPlayer`.
protocol SoundHandle: AnyObject, Sendable {
    func play()
    func stop()
    func setVolume(_ volume: Float)
}

protocol SoundLoading: Sendable {
    /// `<name>.mp3` from the app bundle.
    func bundledSound(named name: String) -> (any SoundHandle)?
    /// A system sound, e.g. `Tink`.
    func systemSound(named name: String) -> (any SoundHandle)?
}

/// F34: the bundled `on`/`off` sounds plus the system `Tink` tick, all scaled by
/// `sound_volume`. Sounds are preloaded so the first press pays no I/O.
final class SoundPlayer: SoundPlaying, SoundPreviewing {
    private let on: (any SoundHandle)?
    private let off: (any SoundHandle)?
    private let tick: (any SoundHandle)?
    private let dispatch: @Sendable (@escaping @Sendable () -> Void) -> Void
    private let volume = OSAllocatedUnfairLock<Float>(initialState: 1)

    init(
        loader: any SoundLoading = NSSoundLoader(),
        dispatch: @escaping @Sendable (@escaping @Sendable () -> Void) -> Void = SoundPlayer.onMainThread
    ) {
        on = loader.bundledSound(named: "on")
        off = loader.bundledSound(named: "off")
        tick = loader.systemSound(named: "Tink")
        self.dispatch = dispatch
    }

    func setVolume(_ value: Float) {
        volume.withLock { $0 = min(max(value, 0), 1) }
    }

    func playOn() { play(on) }
    func playOff() { play(off) }
    func playTick() { play(tick) }

    private func play(_ sound: (any SoundHandle)?) {
        guard let sound else { return }
        let level = volume.withLock { $0 }
        dispatch {
            sound.stop()
            sound.setVolume(level)
            sound.play()
        }
    }

    static let onMainThread: @Sendable (@escaping @Sendable () -> Void) -> Void = { work in
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }
}

struct NSSoundLoader: SoundLoading {
    func bundledSound(named name: String) -> (any SoundHandle)? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "mp3"),
              let sound = NSSound(contentsOf: url, byReference: true)
        else {
            Log.ui.warning("Could not load sound: \(name).mp3")
            return nil
        }
        return NSSoundHandle(sound)
    }

    func systemSound(named name: String) -> (any SoundHandle)? {
        guard let sound = NSSound(named: name) else {
            Log.ui.warning("Could not load system sound: \(name)")
            return nil
        }
        return NSSoundHandle(sound)
    }
}

/// `NSSound` is main-thread-only; `SoundPlayer` guarantees that, so the
/// unchecked conformance is safe.
private final class NSSoundHandle: SoundHandle, @unchecked Sendable {
    private let sound: NSSound

    init(_ sound: NSSound) { self.sound = sound }

    func play() { _ = sound.play() }
    func stop() { _ = sound.stop() }
    func setVolume(_ volume: Float) { sound.volume = volume }
}
