import CoreGraphics
import Testing
@testable import Tabby

/// Covers `SkyLight`, the private WindowServer calls that bring a single window
/// forward without pulling the rest of its app's windows along.
@Suite("SkyLight")
struct SkyLightTests {
    private let windowID: CGWindowID = 0x1234_5678

    // MARK: Symbol availability

    @Test func privateSymbolsResolveOnThisMacOS() {
        // Given the running macOS

        // When the private symbols are looked up
        let available = SkyLight.isAvailable

        // Then they're all present; if this fails, Apple removed or renamed one
        // and activation has silently fallen back to the public API
        #expect(available == true)
    }

    @Test func missingProcessIsNotBroughtToFront() {
        // Given a pid no process can have

        // When
        let brought = SkyLight.bringToFront(pid: pid_t.max, windowID: windowID)

        // Then it reports failure so activation falls back
        #expect(brought == false)
    }

    // MARK: Key-window event record

    @Test func recordIsTheExpectedSize() {
        // Given / When
        let record = SkyLight.keyWindowEventRecord(kind: 0x01, windowID: windowID)

        // Then
        #expect(record.count == 0xF8)
    }

    @Test func recordCarriesItsHeaderAndKind() {
        // Given / When
        let first = SkyLight.keyWindowEventRecord(kind: 0x01, windowID: windowID)
        let second = SkyLight.keyWindowEventRecord(kind: 0x02, windowID: windowID)

        // Then both share the header and differ only in their kind byte
        for record in [first, second] {
            #expect(record[0x04] == 0xF8)
            #expect(record[0x3A] == 0x10)
        }
        #expect(first[0x08] == 0x01)
        #expect(second[0x08] == 0x02)
    }

    @Test func recordFillsTheMarkerRangeWithOnes() {
        // Given / When
        let record = SkyLight.keyWindowEventRecord(kind: 0x01, windowID: windowID)

        // Then
        #expect(record[0x20..<0x30].allSatisfy { $0 == 0xFF })
    }

    @Test func recordStoresTheWindowIDLittleEndian() {
        // Given / When
        let record = SkyLight.keyWindowEventRecord(kind: 0x01, windowID: windowID)

        // Then
        #expect(Array(record[0x3C..<0x40]) == [0x78, 0x56, 0x34, 0x12])
    }

    @Test func recordLeavesEveryOtherByteZero() {
        // Given the offsets the layout sets explicitly
        let setOffsets = Set([0x04, 0x08, 0x3A]).union(0x20..<0x30).union(0x3C..<0x40)

        // When
        let record = SkyLight.keyWindowEventRecord(kind: 0x01, windowID: windowID)

        // Then nothing else is stray data the WindowServer could misread
        let others = record.indices.filter { !setOffsets.contains($0) }
        #expect(others.allSatisfy { record[$0] == 0 })
    }
}
