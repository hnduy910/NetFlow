import XCTest
@testable import NetFlow

@MainActor
final class AppStoreTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    func testMergeSplitsTrafficAcrossLocalMidnightAndPreservesTotal() {
        let store = AppStore()
        store.dailyRecords = []

        store.merge(
            delta: NetworkDelta(
                wifiReceived: 100,
                wifiSent: 20,
                cellularReceived: 300,
                cellularSent: 80,
                isValid: true
            ),
            from: date(2026, 1, 10, 23),
            to: date(2026, 1, 11, 1)
        )

        XCTAssertEqual(store.dailyRecords.count, 2)
        XCTAssertEqual(store.dailyRecords.reduce(UInt64(0)) { $0 &+ $1.totalBytes }, 500)
        XCTAssertEqual(store.dailyRecords.first(where: { $0.date == date(2026, 1, 10) })?.totalBytes, 250)
        XCTAssertEqual(store.dailyRecords.first(where: { $0.date == date(2026, 1, 11) })?.totalBytes, 250)
    }

    func testPlanUsageIgnoresManualUsageForAClosedCycle() {
        let store = AppStore()
        store.plan.cycleType = .daily
        store.plan.capacityBytes = 1_000
        store.plan.activeCycleStart = date(2026, 1, 11)
        store.plan.activeCycleEnd = date(2026, 1, 12)
        store.plan.manualUsedBytes = 300

        XCTAssertEqual(store.planUsage(at: date(2026, 1, 10, 12)), 0)
        XCTAssertEqual(store.planUsage(at: date(2026, 1, 11, 12)), 300)
    }
}
