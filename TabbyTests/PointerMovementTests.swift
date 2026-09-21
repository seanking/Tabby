import CoreGraphics
import Testing
@testable import Tabby

/// Covers `PointerGate`, which keeps a cursor that hasn't moved from taking
/// over the switcher's selection — the HUD opening under the pointer, or the
/// list scrolling/growing a row underneath it, must not count as hovering.
@Suite("Pointer gate")
struct PointerMovementTests {
    private let anchor = CGPoint(x: 400, y: 300)

    /// A gate seeded at `anchor`, as it is when the HUD appears.
    private func seededGate() -> PointerGate {
        var gate = PointerGate()
        gate.seed(at: anchor)
        return gate
    }

    // MARK: A resting pointer

    @Test func hudOpeningUnderARestingCursorIsNotAMove() {
        // Given the HUD has just opened under the pointer
        var gate = seededGate()

        // When the row beneath the cursor reports a hover at the same position
        let moved = gate.consume(anchor)

        // Then it doesn't count, and the anchor stays put
        #expect(moved == false)
        #expect(gate.anchor == anchor)
    }

    @Test func subPixelJitterIsNotAMove() {
        // Given
        var gate = seededGate()

        // When the pointer reports the jitter of a hand resting on the mouse
        let moved = gate.consume(CGPoint(x: 400.4, y: 300.3))

        // Then
        #expect(moved == false)
    }

    @Test func repeatedCallbacksFromAStillCursorNeverAccumulate() {
        // Given a still cursor that the list keeps reflowing underneath
        var gate = seededGate()

        // When each reflow fires another hover at the same screen position
        let results = (0..<5).map { _ in gate.consume(anchor) }

        // Then none of them is mistaken for the user pointing at a row
        #expect(results.allSatisfy { $0 == false })
    }

    // MARK: A moving pointer

    @Test func movingToAnotherRowCounts() {
        // Given
        var gate = seededGate()

        // When the pointer travels a row's height
        let moved = gate.consume(CGPoint(x: 400, y: 312))

        // Then
        #expect(moved == true)
    }

    @Test func smallNudgeInsideTheSameRowCounts() {
        // Given a deliberate nudge too small to leave the current row
        var gate = seededGate()

        // When
        let moved = gate.consume(CGPoint(x: 402, y: 300))

        // Then the user is pointing at that row on purpose
        #expect(moved == true)
    }

    @Test func diagonalMoveMeasuresActualDistance() {
        // Given a move whose x and y steps are each within tolerance but whose
        // combined distance is not
        var gate = seededGate()

        // When
        let moved = gate.consume(CGPoint(x: 400.8, y: 300.8))

        // Then the straight-line distance (~1.13) clears the tolerance
        #expect(moved == true)
    }

    @Test func acceptedMoveReanchorsThere() {
        // Given a gate that has accepted a move to a new row
        var gate = seededGate()
        let row = CGPoint(x: 400, y: 312)
        #expect(gate.consume(row) == true)

        // When the pointer then rests there while the list reflows under it
        let moved = gate.consume(row)

        // Then the reflow is ignored from the new anchor
        #expect(moved == false)
        #expect(gate.anchor == row)
    }

    // MARK: Session lifecycle

    @Test func unseededGateAcceptsTheFirstPosition() {
        // Given a gate that no HUD session has seeded
        var gate = PointerGate()

        // When
        let moved = gate.consume(anchor)

        // Then it can't tell, so it defers to the hover rather than blocking it
        #expect(moved == true)
        #expect(gate.anchor == anchor)
    }

    @Test func resetForgetsTheAnchor() {
        // Given a gate left over from a closed switcher session
        var gate = seededGate()

        // When the session ends
        gate.reset()

        // Then
        #expect(gate.anchor == nil)
    }

    @Test func reopeningUnderTheCursorIgnoresItAgain() {
        // Given a session where the pointer moved, then closed
        var gate = seededGate()
        #expect(gate.consume(CGPoint(x: 400, y: 312)) == true)
        gate.reset()

        // When the HUD reopens under a cursor now resting somewhere new
        let resting = CGPoint(x: 700, y: 500)
        gate.seed(at: resting)

        // Then that position is ignored just like the first session's
        #expect(gate.consume(resting) == false)
    }
}
