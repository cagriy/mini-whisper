import Foundation
import MWConfig
import Testing
@testable import MiniWhisper

@MainActor
@Suite struct VocabularyModelTests {
    private func makeStore() -> (ConfigStore, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mw-vocab-\(UUID().uuidString)", isDirectory: true)
        return (ConfigStore(directory: directory), directory)
    }

    @Test func addTrimsAndDedupes() async {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = VocabularyModel(terms: [], store: store)

        await model.add("  Mini Whisper \n")
        #expect(model.terms == ["Mini Whisper"])

        await model.add("Mini Whisper")
        #expect(model.terms == ["Mini Whisper"])

        await model.add("   ")
        #expect(model.terms == ["Mini Whisper"])

        await model.add("xcodegen")
        #expect(model.terms == ["Mini Whisper", "xcodegen"])
    }

    @Test func removeByIndex() async {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = VocabularyModel(terms: ["a", "b", "c"], store: store)

        await model.remove(at: 1)
        #expect(model.terms == ["a", "c"])

        await model.remove(at: 9)
        #expect(model.terms == ["a", "c"])
    }

    @Test func persistsToConfig() async {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = VocabularyModel(terms: [], store: store)

        await model.add("Speechmatics")
        #expect(await store.load().vocabulary == ["Speechmatics"])

        await model.add("Tahoe")
        await model.remove(at: 0)
        #expect(await store.load().vocabulary == ["Tahoe"])
    }
}
