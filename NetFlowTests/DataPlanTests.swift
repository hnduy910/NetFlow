import XCTest
@testable import NetFlow

final class DataPlanTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    func testMonthlyResetDay31ClampsToShortMonthWithoutGap() {
        var plan = DataPlan()
        plan.cycleType = .monthly
        plan.monthlyResetDay = 31

        let april = plan.cycleInterval(containing: date(2026, 4, 30, 12))
        XCTAssertEqual(april.start, date(2026, 4, 30))
        XCTAssertEqual(april.end, date(2026, 5, 31))

        let mayBoundary = plan.cycleInterval(containing: date(2026, 5, 31))
        XCTAssertEqual(mayBoundary.start, date(2026, 5, 31))
        XCTAssertEqual(mayBoundary.end, date(2026, 6, 30))
    }

    func testYearlyResetDay29ClampsNonLeapYear() {
        var plan = DataPlan()
        plan.cycleType = .yearly
        plan.yearlyResetMonth = 2
        plan.yearlyResetDay = 29

        let interval = plan.cycleInterval(containing: date(2025, 3, 1))
        XCTAssertEqual(interval.start, date(2025, 2, 28))
        XCTAssertEqual(interval.end, date(2026, 2, 28))

        let leapInterval = plan.cycleInterval(containing: date(2024, 3, 1))
        XCTAssertEqual(leapInterval.start, date(2024, 2, 29))
        XCTAssertEqual(leapInterval.end, date(2025, 2, 28))
    }

    func testForecastUsesCurrentCycleAndIncludesManualUsage() throws {
        var plan = DataPlan()
        plan.cycleType = .daily
        plan.capacityBytes = 1_000
        plan.activeCycleStart = date(2026, 1, 10)
        plan.activeCycleEnd = date(2026, 1, 11)
        plan.manualUsedBytes = 100

        let record = DailyUsageRecord(
            date: date(2026, 1, 10),
            delta: NetworkDelta(
                wifiReceived: 0,
                wifiSent: 0,
                cellularReceived: 200,
                cellularSent: 0,
                isValid: true
            ),
            firstUpdated: date(2026, 1, 10, 8),
            lastUpdated: date(2026, 1, 10, 9)
        )

        let forecast = try XCTUnwrap(plan.forecast(records: [record], at: date(2026, 1, 10, 12)))
        XCTAssertEqual(forecast.usedBytes, 300)
        XCTAssertEqual(forecast.capacityBytes, 1_000)
        XCTAssertEqual(forecast.projectedBytes, 300)
        XCTAssertFalse(forecast.isProjectedToExceed)
    }

    func testClosedCycleRemainingDoesNotUseActiveCycleManualUsage() {
        var plan = DataPlan()
        plan.cycleType = .daily
        plan.capacityBytes = 1_000
        plan.activeCycleStart = date(2026, 1, 11)
        plan.activeCycleEnd = date(2026, 1, 12)
        plan.manualUsedBytes = 700

        let previousRecord = DailyUsageRecord(
            date: date(2026, 1, 10),
            delta: NetworkDelta(
                wifiReceived: 0,
                wifiSent: 0,
                cellularReceived: 200,
                cellularSent: 0,
                isValid: true
            ),
            firstUpdated: date(2026, 1, 10, 8),
            lastUpdated: date(2026, 1, 10, 9)
        )

        XCTAssertEqual(plan.remainingBytes(records: [previousRecord], at: date(2026, 1, 10, 23)), 800)
    }
}
