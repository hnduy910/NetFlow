import XCTest
@testable import NetFlow

final class UsageTrackerTests: XCTestCase {
    private final class StubReader: NetworkSnapshotReading {
        var snapshots: [NetworkSnapshot]

        init(_ snapshots: [NetworkSnapshot]) {
            self.snapshots = snapshots
        }

        func read() -> NetworkSnapshot {
            snapshots.removeFirst()
        }
    }

    private func snapshot(_ timestamp: TimeInterval, wifi: UInt64, cellular: UInt64) -> NetworkSnapshot {
        NetworkSnapshot(
            wifi: NetworkCounter(received: wifi, sent: 10),
            cellular: NetworkCounter(received: cellular, sent: 20),
            timestamp: Date(timeIntervalSince1970: timestamp)
        )
    }

    func testFirstSampleUsesZeroDeltaAndSecondSampleCalculatesRate() {
        let reader = StubReader([
            snapshot(100, wifi: 100, cellular: 300),
            snapshot(110, wifi: 160, cellular: 500)
        ])
        let tracker = UsageTracker(reader: reader)

        let first = tracker.sample(previous: .zero)
        XCTAssertFalse(first.delta.isValid)
        XCTAssertEqual(first.delta.totalBytes, 0)

        let second = tracker.sample(previous: first.snapshot)
        XCTAssertTrue(second.delta.isValid)
        XCTAssertEqual(second.delta.wifiReceived, 60)
        XCTAssertEqual(second.delta.cellularReceived, 200)
        XCTAssertEqual(second.rate.cellularDown, 20, accuracy: 0.001)
    }

    func testCounterResetInvalidatesSample() {
        let reader = StubReader([
            snapshot(100, wifi: 100, cellular: 300),
            snapshot(110, wifi: 90, cellular: 350)
        ])
        let tracker = UsageTracker(reader: reader)

        _ = tracker.sample(previous: .zero)
        let result = tracker.sample(previous: snapshot(100, wifi: 100, cellular: 300))

        XCTAssertFalse(result.delta.isValid)
        XCTAssertEqual(result.rate, .zero)
    }
}
