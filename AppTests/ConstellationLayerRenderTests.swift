import CoreGraphics
import MWOverlaySim
import Testing
@testable import MiniWhisper

@Suite struct ConstellationLayerRenderTests {
    private func makeContext() -> CGContext {
        let size = Int(Constants.windowSize)
        return CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: size * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
        )!
    }

    /// Drives one scripted dictation through every mode at 60 fps.
    private func script(_ layer: ConstellationLayer, into context: CGContext, frames: Int) -> Int {
        var simulation = ConstellationSimulation(rng: SeededRandom(seed: 7))
        simulation.show()
        var drawn = 0
        for step in 0..<frames {
            switch step {
            case frames / 5: simulation.set(mode: .recording)
            case frames * 3 / 5: simulation.set(mode: .processing)
            case frames * 9 / 10: simulation.set(mode: .result)
            default: break
            }
            let level = (frames / 5..<frames * 3 / 5).contains(step) ? 0.03 : 0.0
            layer.update(simulation.step(dt: 1.0 / 60, level: level))
            layer.draw(in: context)
            drawn += 1
        }
        return drawn
    }

    @Test func renders600ScriptedFramesWithoutError() {
        let context = makeContext()
        let layer = ConstellationLayer()
        layer.frame = CGRect(x: 0, y: 0, width: Constants.windowSize, height: Constants.windowSize)

        #expect(script(layer, into: context, frames: 600) == 600)

        let bytes = UnsafeRawBufferPointer(
            start: context.data,
            count: context.bytesPerRow * context.height
        )
        #expect(bytes.contains { $0 != 0 })
    }

    @Test func frameBufferIsReusedAcrossDraws() {
        let context = makeContext()
        let layer = ConstellationLayer()
        layer.frame = CGRect(x: 0, y: 0, width: Constants.windowSize, height: Constants.windowSize)

        _ = script(layer, into: context, frames: 1)
        let dots = layer.dotStorageIdentity
        let links = layer.linkStorageIdentity
        #expect(dots != nil)
        #expect(links != nil)

        _ = script(layer, into: context, frames: 600)
        #expect(layer.dotStorageIdentity == dots)
        #expect(layer.linkStorageIdentity == links)
    }
}
