import AVFAudio
import CoreAudio
import Foundation
import MWSupport

public enum SystemAudioTapError: Error, Equatable, CustomStringConvertible {
    case coreAudio(String, OSStatus)
    case unsupportedFormat

    public var description: String {
        switch self {
        case .coreAudio(let call, let status): "\(call) failed (OSStatus \(status))"
        case .unsupportedFormat: "system audio format not supported"
        }
    }
}

/// A Core Audio process tap of every process but one, read through a private aggregate
/// device and resampled to 16 kHz mono float (design §5.3). Rebuilt when the default
/// output device changes.
@available(macOS 14.2, *)
public final class SystemAudioTap: SystemAudioTapping, @unchecked Sendable {
    private static let name = "Mini Whisper system audio"

    public let events: AsyncStream<SystemAudioTapEvent>
    private let continuation: AsyncStream<SystemAudioTapEvent>.Continuation
    private let pid: pid_t
    // Separate queues: a teardown on the control queue waits for the IOProc, which runs on
    // the IO queue.
    private let controlQueue = DispatchQueue(label: "com.ips.mini-whisper.system-audio.control")
    private let ioQueue = DispatchQueue(label: "com.ips.mini-whisper.system-audio.io", qos: .userInteractive)

    // Confined to `controlQueue` (or `deinit`).
    private var handler: (@Sendable (AVAudioPCMBuffer) -> Void)?
    private var outputListener: AudioObjectPropertyListenerBlock?
    private var tapID: AudioObjectID?
    private var aggregateID: AudioObjectID?
    private var procID: AudioDeviceIOProcID?

    public init(excluding pid: pid_t) {
        self.pid = pid
        (events, continuation) = AsyncStream.makeStream()
    }

    deinit {
        tearDown()
        continuation.finish()
    }

    public static func aggregateDescription(tapUID: String, name: String) -> [String: Any] {
        [
            kAudioAggregateDeviceNameKey: name,
            kAudioAggregateDeviceUIDKey: "com.ips.mini-whisper.system-audio.\(tapUID)",
            kAudioAggregateDeviceIsPrivateKey: 1,
            kAudioAggregateDeviceTapListKey: [
                [kAudioSubTapUIDKey: tapUID, kAudioSubTapDriftCompensationKey: 1],
            ],
        ]
    }

    public func start(_ handler: @escaping @Sendable (AVAudioPCMBuffer) -> Void) throws {
        try controlQueue.sync {
            tearDown()
            do {
                try buildDevice(handler)
                try addOutputListener()
            } catch {
                tearDown()
                Log.meeting.warning("system audio tap failed: \(error)")
                throw error
            }
            self.handler = handler
        }
        Log.meeting.info("system audio tap started")
    }

    public func stop() {
        controlQueue.sync { tearDown() }
        Log.meeting.info("system audio tap stopped")
    }

    // MARK: - Device

    private func buildDevice(_ handler: @escaping @Sendable (AVAudioPCMBuffer) -> Void) throws {
        let description = CATapDescription(monoGlobalTapButExcludeProcesses: try excludedProcesses())
        description.name = Self.name
        description.isPrivate = true
        description.muteBehavior = .unmuted

        var tap = AudioObjectID(kAudioObjectUnknown)
        try check(AudioHardwareCreateProcessTap(description, &tap), "create process tap")
        tapID = tap

        var formatAddress = Self.address(kAudioTapPropertyFormat)
        var format = AudioStreamBasicDescription()
        var formatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        try check(AudioObjectGetPropertyData(tap, &formatAddress, 0, nil, &formatSize, &format), "read tap format")
        guard let inputFormat = AVAudioFormat(streamDescription: &format),
              let outputFormat = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1),
              let resampler = Resampler(from: inputFormat, to: outputFormat)
        else { throw SystemAudioTapError.unsupportedFormat }

        let aggregate = Self.aggregateDescription(tapUID: description.uuid.uuidString, name: Self.name)
        var device = AudioObjectID(kAudioObjectUnknown)
        try check(AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &device), "create aggregate device")
        aggregateID = device

        var proc: AudioDeviceIOProcID?
        try check(
            AudioDeviceCreateIOProcIDWithBlock(&proc, device, ioQueue) { _, input, _, _, _ in
                if let buffer = resampler.convert(input) { handler(buffer) }
            },
            "create IOProc"
        )
        procID = proc
        try check(AudioDeviceStart(device, proc), "start aggregate device")
    }

    /// Our own process object, so the tap leaves out this app's sounds. A process that has
    /// not yet touched Core Audio has none, and then there is nothing to leave out.
    private func excludedProcesses() throws -> [AudioObjectID] {
        var address = Self.address(kAudioHardwarePropertyTranslatePIDToProcessObject)
        var pid = pid
        var object = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        try check(
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject), &address,
                UInt32(MemoryLayout<pid_t>.size), &pid, &size, &object
            ),
            "translate PID"
        )
        return object == kAudioObjectUnknown ? [] : [object]
    }

    private func tearDown() {
        removeOutputListener()
        handler = nil
        tearDownDevice()
    }

    private func tearDownDevice() {
        if let aggregateID, let procID {
            AudioDeviceStop(aggregateID, procID)
            AudioDeviceDestroyIOProcID(aggregateID, procID)
        }
        if let aggregateID { AudioHardwareDestroyAggregateDevice(aggregateID) }
        if let tapID { AudioHardwareDestroyProcessTap(tapID) }
        procID = nil
        aggregateID = nil
        tapID = nil
    }

    // MARK: - Default output

    private func addOutputListener() throws {
        var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.defaultOutputChanged() }
        try check(
            AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, controlQueue, listener),
            "add default output listener"
        )
        outputListener = listener
    }

    private func removeOutputListener() {
        guard let outputListener else { return }
        var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
        AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, controlQueue, outputListener)
        self.outputListener = nil
    }

    /// Runs on `controlQueue`.
    private func defaultOutputChanged() {
        guard let handler else { return }
        tearDownDevice()
        do {
            try buildDevice(handler)
            Log.meeting.info("system audio tap rebuilt after default output change")
            continuation.yield(.defaultOutputChanged)
        } catch {
            tearDown()
            Log.meeting.warning("system audio tap rebuild failed: \(error)")
            continuation.yield(.stopped(error))
        }
    }

    // MARK: - Helpers

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private func check(_ status: OSStatus, _ call: String) throws {
        guard status == noErr else { throw SystemAudioTapError.coreAudio(call, status) }
    }
}

/// Stateful tap-format → 16 kHz mono float conversion, used only on the IO queue.
private final class Resampler: @unchecked Sendable {
    private let converter: AVAudioConverter
    private let inputFormat: AVAudioFormat

    init?(from inputFormat: AVAudioFormat, to outputFormat: AVAudioFormat) {
        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else { return nil }
        self.converter = converter
        self.inputFormat = inputFormat
    }

    func convert(_ list: UnsafePointer<AudioBufferList>) -> AVAudioPCMBuffer? {
        guard let input = AVAudioPCMBuffer(pcmFormat: inputFormat, bufferListNoCopy: list, deallocator: nil),
              input.frameLength > 0
        else { return nil }
        let ratio = converter.outputFormat.sampleRate / inputFormat.sampleRate
        let capacity = AVAudioFrameCount((Double(input.frameLength) * ratio).rounded(.up)) + 1
        guard let output = AVAudioPCMBuffer(pcmFormat: converter.outputFormat, frameCapacity: capacity) else { return nil }

        var supplied = false
        let status = converter.convert(to: output, error: nil) { _, inputStatus in
            // `.noDataNow`, not `.endOfStream`, keeps the resampler's history for the next cycle.
            if supplied {
                inputStatus.pointee = .noDataNow
                return nil
            }
            supplied = true
            inputStatus.pointee = .haveData
            return input
        }
        guard status != .error, output.frameLength > 0 else { return nil }
        return output
    }
}
