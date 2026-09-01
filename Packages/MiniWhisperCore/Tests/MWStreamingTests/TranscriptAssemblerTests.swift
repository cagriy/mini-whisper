import Testing

import MWStreaming

/// Ported case for case from `../mini-whisper/tests/test_streaming_base.py`.
@Suite struct TranscriptAssemblerTests {
    @Test func partialReplacesPreviousPartial() {
        var assembler = TranscriptAssembler()
        assembler.addPartial("hel")
        assembler.addPartial("hello wor")
        #expect(assembler.text == "hello wor")
    }

    @Test func finalAppendsAndClearsPartial() {
        var assembler = TranscriptAssembler()
        assembler.addPartial("hello wor")
        assembler.addFinal("hello world.")
        #expect(assembler.text == "hello world.")
        assembler.addPartial("next bit")
        #expect(assembler.text == "hello world. next bit")
    }

    @Test func multipleFinalsJoined() {
        var assembler = TranscriptAssembler()
        assembler.addFinal("First segment.")
        assembler.addFinal("Second segment.")
        assembler.addPartial("third")
        #expect(assembler.text == "First segment. Second segment. third")
    }

    @Test func partialRestartKeepsEarlierSentence() {
        var assembler = TranscriptAssembler()
        assembler.addPartial("Hello there my friend.")
        assembler.addPartial("So")
        assembler.addPartial("So what happens next")
        #expect(assembler.text == "Hello there my friend. So what happens next")
    }

    @Test func partialRevisionDoesNotDuplicate() {
        var assembler = TranscriptAssembler()
        assembler.addPartial("I think")
        assembler.addPartial("I thought so")
        #expect(assembler.text == "I thought so")
    }

    @Test func partialBacktrackDoesNotDuplicate() {
        var assembler = TranscriptAssembler()
        assembler.addPartial("hello world")
        assembler.addPartial("hello")
        #expect(assembler.text == "hello")
    }

    @Test func emptyFinalKeepsLivePartial() {
        var assembler = TranscriptAssembler()
        assembler.addPartial("still speaking")
        assembler.addFinal("   ")
        #expect(assembler.text == "still speaking")
    }

    @Test func emptyCompound() {
        let assembler = TranscriptAssembler()
        #expect(assembler.text == "")
    }

    @Test func whitespaceSegmentsSkipped() {
        var assembler = TranscriptAssembler()
        assembler.addFinal("  Hello.  ")
        assembler.addFinal("   ")
        assembler.addPartial("  ")
        #expect(assembler.text == "Hello.")
    }

    @Test func restartHeuristicIsCaseInsensitive() {
        var assembler = TranscriptAssembler()
        assembler.addPartial("Hello there my friend.")
        // A case-sensitive prefix check would read this as a fresh segment.
        assembler.addPartial("hello")
        #expect(assembler.text == "hello")
    }
}

@Suite struct StreamResultTests {
    @Test func defaults() {
        let result = StreamResult()
        #expect(result.text == "")
        #expect(result.ok == false)
        #expect(result.usage == StreamUsage(inputTokens: 0, outputTokens: 0, seconds: 0))
    }

    @Test func usageNotShared() {
        var first = StreamResult()
        let second = StreamResult()
        first.usage.seconds = 5
        #expect(second.usage.seconds == 0)
    }
}
