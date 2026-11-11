import Testing

import MWTestCall

@Suite struct WordAlignerTests {
    private func align(_ reference: String, _ hypothesis: String) -> WordAligner.Alignment {
        WordAligner().align(
            reference: reference.split(separator: " ").map(String.init),
            hypothesis: hypothesis.split(separator: " ").map(String.init)
        )
    }

    private func counts(_ alignment: WordAligner.Alignment) -> [Int] {
        [alignment.substitutions, alignment.deletions, alignment.insertions]
    }

    @Test func bothSidesEmpty() {
        let alignment = align("", "")

        #expect(alignment.ops.isEmpty)
        #expect(counts(alignment) == [0, 0, 0])
    }

    @Test func emptyHypothesisIsAllDeletions() {
        let alignment = align("the plan holds", "")

        #expect(alignment.ops == [.delete(reference: 0), .delete(reference: 1), .delete(reference: 2)])
        #expect(counts(alignment) == [0, 3, 0])
    }

    @Test func emptyReferenceIsAllInsertions() {
        let alignment = align("", "uh huh")

        #expect(alignment.ops == [.insert(hypothesis: 0), .insert(hypothesis: 1)])
        #expect(counts(alignment) == [0, 0, 2])
    }

    @Test func allMatch() {
        let alignment = align("the plan holds", "the plan holds")

        #expect(alignment.ops == [
            .match(reference: 0, hypothesis: 0), .match(reference: 1, hypothesis: 1),
            .match(reference: 2, hypothesis: 2),
        ])
        #expect(counts(alignment) == [0, 0, 0])
    }

    @Test func singleSubstitution() {
        let alignment = align("the plan holds", "the plane holds")

        #expect(alignment.ops == [
            .match(reference: 0, hypothesis: 0), .substitute(reference: 1, hypothesis: 1),
            .match(reference: 2, hypothesis: 2),
        ])
        #expect(counts(alignment) == [1, 0, 0])
    }

    @Test func singleDeletion() {
        let alignment = align("the plan holds", "the holds")

        #expect(alignment.ops == [
            .match(reference: 0, hypothesis: 0), .delete(reference: 1), .match(reference: 2, hypothesis: 1),
        ])
        #expect(counts(alignment) == [0, 1, 0])
    }

    @Test func singleInsertion() {
        let alignment = align("the plan holds", "the plan still holds")

        #expect(alignment.ops == [
            .match(reference: 0, hypothesis: 0), .match(reference: 1, hypothesis: 1),
            .insert(hypothesis: 2), .match(reference: 2, hypothesis: 3),
        ])
        #expect(counts(alignment) == [0, 0, 1])
    }

    @Test func splitCompoundIsOneSubstitutionAndOneInsertion() {
        let alignment = align("webhook", "web hook")

        #expect(alignment.ops == [.substitute(reference: 0, hypothesis: 0), .insert(hypothesis: 1)])
        #expect(counts(alignment) == [1, 0, 1])
    }

    @Test(arguments: [
        ("a b", "c", [WordAligner.Alignment.Op.substitute(reference: 0, hypothesis: 0), .delete(reference: 1)]),
        ("x y", "y x", [.substitute(reference: 0, hypothesis: 0), .substitute(reference: 1, hypothesis: 1)]),
        ("a b c", "a x y c", [
            .match(reference: 0, hypothesis: 0), .substitute(reference: 1, hypothesis: 1),
            .insert(hypothesis: 2), .match(reference: 2, hypothesis: 3),
        ]),
    ])
    func tieBreakingIsStable(_ reference: String, _ hypothesis: String, _ expected: [WordAligner.Alignment.Op]) {
        for _ in 0..<5 {
            #expect(align(reference, hypothesis).ops == expected)
        }
    }

    @Test func countsAreTheEditDistance() {
        let alignment = align("then the remaining risk is the kubernetes upgrade", "then remaining risk is the cooper netties upgrade")

        #expect(counts(alignment) == [1, 1, 1])
    }
}
