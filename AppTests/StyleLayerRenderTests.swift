import CoreGraphics
import MWOverlaySim
import Testing
@testable import MiniWhisper

/// The sibling of `ConstellationLayerRenderTests` for the five ported styles: the same
/// bitmap host and the same scripted dictation, driven by `StyleSimulation` (design §5.12).
private let newStyles: [OverlayStyle] = [
    .silkRibbon, .resonantHalo, .softMeter, .liquidPearl, .petalIris,
]

@Suite struct StyleLayerRenderTests {
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

    private func makeLayer(_ style: OverlayStyle) -> StyleLayer {
        let layer = StyleLayer(style: style)
        layer.frame = CGRect(x: 0, y: 0, width: Constants.windowSize, height: Constants.windowSize)
        return layer
    }

    private func pixels(_ context: CGContext) -> UnsafeRawBufferPointer {
        UnsafeRawBufferPointer(start: context.data, count: context.bytesPerRow * context.height)
    }

    /// Premultiplied ARGB over a black card, so a mark or a glyph is the only bright red.
    private func markedPixels(_ context: CGContext) -> Int {
        var marked = 0
        for (offset, byte) in pixels(context).enumerated() where offset % 4 == 1 && byte > 128 {
            marked += 1
        }
        return marked
    }

    /// Drives one scripted dictation through every mode at 60 fps.
    private func script(
        _ layer: StyleLayer,
        style: OverlayStyle,
        into context: CGContext,
        frames: Int
    ) -> Int {
        var simulation = StyleSimulation(style: style)
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

    /// Runs an error card for `seconds` and reports how much of the card is drawn on.
    private func errorMarks(_ message: String, seconds: Double) -> Int {
        let context = makeContext()
        let layer = makeLayer(.softMeter)
        var simulation = StyleSimulation(style: .softMeter)
        simulation.show()
        simulation.set(mode: .error(message))
        var frame = simulation.step(dt: 0, level: 0)
        for _ in 0..<Int(seconds * 60) { frame = simulation.step(dt: 1.0 / 60, level: 0) }
        layer.update(frame)
        layer.draw(in: context)
        return markedPixels(context)
    }

    @Test(arguments: newStyles) func rendersEveryNewStyleWithoutError(_ style: OverlayStyle) {
        let context = makeContext()

        #expect(script(makeLayer(style), style: style, into: context, frames: 600) == 600)
        #expect(pixels(context).contains { $0 != 0 })
        #expect(markedPixels(context) > 0)
    }

    @Test func frameBufferIsReusedAcrossDraws() {
        let context = makeContext()
        let layer = makeLayer(.petalIris)

        _ = script(layer, style: .petalIris, into: context, frames: 1)
        let points = layer.pointStorageIdentity
        #expect(points != nil)

        _ = script(layer, style: .petalIris, into: context, frames: 600)
        #expect(layer.pointStorageIdentity == points)
    }

    @Test func errorModeDrawsTheMessageOnceTheShakeIsSpent() {
        #expect(errorMarks("something went wrong", seconds: 0.1) > 0)
        #expect(errorMarks("", seconds: 0.5) == 0)
        #expect(errorMarks("something went wrong", seconds: 0.5) > 0)
    }
}
