// Checks the voice model on this Mac: embeds each clip, prints the cosine table, and exits 1
// unless every pair of clips of one voice scores above 0.7 and every pair of different voices
// below it.
//
// usage: voice_model_check <wespeaker_v2.mlmodelc> <clip.wav> <clip.wav>...
//
// A clip's voice is its file name before the last "-": daniel-1.wav and daniel-2.wav are one
// voice. Clips are 16 kHz mono, looped to the model's 10 s window, embedded the way
// CoreMLVoiceEmbedder does it: the window in all three rows, all-ones masks, output row 0.
//
// Plain top-level Swift, so the oldest hosted macOS runner's toolchain compiles it (CI job
// `voice-model`).

import AVFoundation
import CoreML
import Foundation

let threshold = 0.7
let windowSamples = 160_000
let rows = 3
let frames = 589
let dimension = 256

func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(code)
}

func samples(_ url: URL) throws -> [Float] {
    let file = try AVAudioFile(forReading: url)
    let format = file.processingFormat
    guard format.sampleRate == 16_000, format.channelCount == 1 else {
        fail("\(url.lastPathComponent) is not 16 kHz mono")
    }
    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)) else {
        fail("cannot read \(url.lastPathComponent)")
    }
    try file.read(into: buffer)
    guard buffer.frameLength > 0, let channel = buffer.floatChannelData?[0] else {
        fail("\(url.lastPathComponent) holds no audio")
    }
    return Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
}

func embed(_ clip: [Float], with model: MLModel) throws -> [Double] {
    let waveform = try MLMultiArray(shape: [NSNumber(value: rows), NSNumber(value: windowSamples)], dataType: .float32)
    let mask = try MLMultiArray(shape: [NSNumber(value: rows), NSNumber(value: frames)], dataType: .float32)
    let w = waveform.dataPointer.bindMemory(to: Float.self, capacity: rows * windowSamples)
    let m = mask.dataPointer.bindMemory(to: Float.self, capacity: rows * frames)
    for row in 0..<rows {
        for i in 0..<windowSamples { w[row * windowSamples + i] = clip[i % clip.count] }
        for i in 0..<frames { m[row * frames + i] = 1 }
    }
    let input = try MLDictionaryFeatureProvider(dictionary: ["waveform": waveform, "mask": mask])
    guard let embedding = try model.prediction(from: input).featureValue(for: "embedding")?.multiArrayValue,
        embedding.shape == [NSNumber(value: rows), NSNumber(value: dimension)]
    else {
        fail("the model returned no [3, 256] embedding")
    }
    return (0..<dimension).map { embedding[[0, NSNumber(value: $0)]].doubleValue }
}

func cosine(_ a: [Double], _ b: [Double]) -> Double {
    var dot = 0.0
    var aa = 0.0
    var bb = 0.0
    for i in a.indices {
        dot += a[i] * b[i]
        aa += a[i] * a[i]
        bb += b[i] * b[i]
    }
    return dot / (aa.squareRoot() * bb.squareRoot())
}

func padded(_ text: String) -> String {
    text.padding(toLength: 12, withPad: " ", startingAt: 0)
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count >= 3 else {
    fail("usage: voice_model_check <model.mlmodelc> <clip.wav> <clip.wav>...", code: 2)
}
let clips = arguments.dropFirst().map { URL(fileURLWithPath: $0) }
let names = clips.map { $0.deletingPathExtension().lastPathComponent }
let voices = names.map { name -> String in
    guard let dash = name.lastIndex(of: "-") else { return name }
    return String(name[..<dash])
}

do {
    let started = Date()
    let model = try MLModel(contentsOf: URL(fileURLWithPath: arguments[0]))
    print(String(format: "model loaded in %.2f s", Date().timeIntervalSince(started)))

    let vectors = try clips.map { try embed(samples($0), with: model) }

    print("\n" + padded("") + names.map(padded).joined())
    for i in names.indices {
        print(padded(names[i]) + names.indices.map { padded(String(format: "%.3f", cosine(vectors[i], vectors[$0]))) }.joined())
    }

    var sameVoicePairs = 0
    var crossVoicePairs = 0
    var failures: [String] = []
    for i in names.indices {
        for j in names.indices where j > i {
            let score = cosine(vectors[i], vectors[j])
            if voices[i] == voices[j] {
                sameVoicePairs += 1
                if !(score > threshold) { failures.append(String(format: "%@ · %@ %.3f, same voice, not above %.2f", names[i], names[j], score, threshold)) }
            } else {
                crossVoicePairs += 1
                if !(score < threshold) { failures.append(String(format: "%@ · %@ %.3f, different voices, not below %.2f", names[i], names[j], score, threshold)) }
            }
        }
    }
    guard sameVoicePairs > 0, crossVoicePairs > 0 else {
        fail("the clips need at least two of one voice and two voices", code: 2)
    }
    guard failures.isEmpty else {
        fail("\n" + failures.joined(separator: "\n"))
    }
    print(String(format: "\npass: %d same-voice pairs above %.2f, %d cross-voice pairs below", sameVoicePairs, threshold, crossVoicePairs))
} catch {
    fail("\(error)")
}
