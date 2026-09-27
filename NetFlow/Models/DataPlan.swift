import Foundation

enum PlanCycleType: String, Codable, CaseIterable, Identifiable {
    case daily, monthly, yearly, custom, unlimited
    var id: String { rawValue }
}

struct AlertThreshold: Codable, Identifiable, Hashable {
    enum Kind: String, Codable { case percentUsed, remainingBytes }
    var id = UUID()
    var kind: Kind
    var value: Double
    var enabled = true
}

struct UsageAlertEvent: Codable, Identifiable, Hashable {
    var id = UUID()
    var date: Date
    var threshold: AlertThreshold
    var remainingBytes: UInt64
}

struct UsageForecast: Hashable {
    var usedBytes: UInt64
    var averageDailyBytes: UInt64
    var projectedBytes: UInt64
    var capacityBytes: UInt64
    var cycleEnd: Date

    var isProjectedToExceed: Bool { projectedBytes > capacityBytes }
    var projectedRemainingBytes: UInt64 {
        capacityBytes > projectedBytes ? capacityBytes - projectedBytes : 0
    }
}

struct DataPlan: Codable, Hashable {
    static let defaultName = "Data Plan"
    private static let legacyDefaultName = "Gói dữ liệu"

    var name = DataPlan.defaultName
    var cycleType: PlanCycleType = .monthly
    var capacityBytes: UInt64 = 30 * 1_000_000_000
    var capacityDisplayUnitRaw: String? = "GB"
    var customDays = 7
    var monthlyResetDay = 1
    var yearlyResetMonth = 1
    var yearlyResetDay = 1
    var cycleAnchor = Calendar.current.startOfDay(for: Date())
    var rolloverEnabled = false
    var carriedBytes: UInt64 = 0
    var manualUsedBytes: UInt64 = 0
    var activeCycleStart = Calendar.current.startOfDay(for: Date())
    var activeCycleEnd = Calendar.current.date(byAdding: .month, value: 1, to: Calendar.current.startOfDay(for: Date())) ?? Date()
    var alertThresholds: [AlertThreshold] = [
        AlertThreshold(kind: .percentUsed, value: 80),
        AlertThreshold(kind: .percentUsed, value: 95),
        AlertThreshold(kind: .remainingBytes, value: 500_000_000)
    ]
    var triggeredAlertIDs: Set<String> = []

    var isUnlimited: Bool { cycleType == .unlimited }
    var effectiveCapacityBytes: UInt64 {
        guard !isUnlimited else { return UInt64.max }
        let (capacity, overflow) = capacityBytes.addingReportingOverflow(carriedBytes)
        return overflow ? UInt64.max : capacity
    }

    func displayName(locale: Locale) -> String {
        (name == Self.defaultName || name == Self.legacyDefaultName)
            ? AppLocalization.string("default_plan_name", locale: locale)
            : name
    }

    func cycleInterval(containing date: Date) -> DateInterval {
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: date)
        switch cycleType {
        case .daily:
            return DateInterval(start: startOfDay, end: cal.date(byAdding: .day, value: 1, to: startOfDay)!)
        case .monthly:
            let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: date)) ?? startOfDay
            let currentBoundary = monthlyBoundary(containingMonth: monthStart, calendar: cal) ?? monthStart
            let start: Date
            if date < currentBoundary {
                let previousMonth = cal.date(byAdding: .month, value: -1, to: monthStart) ?? monthStart
                start = monthlyBoundary(containingMonth: previousMonth, calendar: cal) ?? previousMonth
            } else {
                start = currentBoundary
            }
            let startMonth = cal.date(from: cal.dateComponents([.year, .month], from: start)) ?? start
            let nextMonth = cal.date(byAdding: .month, value: 1, to: startMonth) ?? startMonth
            let end = monthlyBoundary(containingMonth: nextMonth, calendar: cal)
                ?? cal.date(byAdding: .month, value: 1, to: startMonth)!
            return DateInterval(start: start, end: end)
        case .yearly:
            let yearStart = cal.date(from: cal.dateComponents([.year], from: date)) ?? startOfDay
            let currentBoundary = yearlyBoundary(containingYear: yearStart, calendar: cal) ?? yearStart
            let start: Date
            if date < currentBoundary {
                let previousYear = cal.date(byAdding: .year, value: -1, to: yearStart) ?? yearStart
                start = yearlyBoundary(containingYear: previousYear, calendar: cal) ?? previousYear
            } else {
                start = currentBoundary
            }
            let startYear = cal.date(from: cal.dateComponents([.year], from: start)) ?? start
            let nextYear = cal.date(byAdding: .year, value: 1, to: startYear) ?? startYear
            let end = yearlyBoundary(containingYear: nextYear, calendar: cal)
                ?? cal.date(byAdding: .year, value: 1, to: startYear)!
            return DateInterval(start: start, end: end)
        case .custom:
            let days = max(customDays, 1)
            let elapsed = cal.dateComponents([.day], from: cal.startOfDay(for: cycleAnchor), to: startOfDay).day ?? 0
            let index = Int(floor(Double(elapsed) / Double(days)))
            let start = cal.date(byAdding: .day, value: index * days, to: cal.startOfDay(for: cycleAnchor))!
            return DateInterval(start: start, end: cal.date(byAdding: .day, value: days, to: start)!)
        case .unlimited:
            let start = cal.date(from: cal.dateComponents([.year, .month], from: date))!
            return DateInterval(start: start, end: cal.date(byAdding: .month, value: 1, to: start)!)
        }
    }

    func remainingBytes(records: [DailyUsageRecord], at date: Date = Date()) -> UInt64 {
        guard !isUnlimited else { return UInt64.max }
        let interval = cycleInterval(containing: date)
        let measured = records
            .filter { interval.contains($0.date) }
            .reduce(UInt64(0)) { $0 &+ $1.cellularTotalBytes }
        let manual = interval.start == activeCycleStart ? manualUsedBytes : 0
        let used = measured &+ manual
        let capacity = interval.start == activeCycleStart ? effectiveCapacityBytes : capacityBytes
        return capacity > used ? capacity - used : 0
    }

    func forecast(records: [DailyUsageRecord], at date: Date = Date()) -> UsageForecast? {
        guard !isUnlimited else { return nil }

        let interval = cycleInterval(containing: date)
        let boundedNow = min(max(date, interval.start), interval.end)
        let measured = records
            .filter { interval.contains($0.date) && $0.date <= boundedNow }
            .reduce(UInt64(0)) { $0 &+ $1.cellularTotalBytes }
        let manual = interval.start == activeCycleStart ? manualUsedBytes : 0
        let used = measured &+ manual

        // Use at least one day as the observation window so a few minutes of
        // early-cycle traffic do not produce an unrealistically large forecast.
        let day: TimeInterval = 86_400
        let elapsed = max(boundedNow.timeIntervalSince(interval.start), day)
        let duration = max(interval.end.timeIntervalSince(interval.start), elapsed)
        let projectedDouble = Double(used) * duration / elapsed
        let averageDouble = Double(used) / max(elapsed / day, 1)

        let projected = projectedDouble >= Double(UInt64.max)
            ? UInt64.max
            : UInt64(max(projectedDouble, 0).rounded())
        let average = averageDouble >= Double(UInt64.max)
            ? UInt64.max
            : UInt64(max(averageDouble, 0).rounded())

        return UsageForecast(
            usedBytes: used,
            averageDailyBytes: average,
            projectedBytes: projected,
            capacityBytes: interval.start == activeCycleStart ? effectiveCapacityBytes : capacityBytes,
            cycleEnd: interval.end
        )
    }

    private func monthlyBoundary(containingMonth month: Date, calendar cal: Calendar) -> Date? {
        let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: month)) ?? month
        let monthComponents = cal.dateComponents([.year, .month], from: monthStart)
        let monthEnd = cal.date(byAdding: DateComponents(month: 1, day: -1), to: monthStart)
        let lastDay = monthEnd.map { cal.component(.day, from: $0) } ?? 28
        var components = monthComponents
        components.day = min(max(monthlyResetDay, 1), lastDay)
        return cal.date(from: components)
    }

    private func yearlyBoundary(containingYear year: Date, calendar cal: Calendar) -> Date? {
        let yearComponents = cal.dateComponents([.year], from: year)
        var components = yearComponents
        components.month = min(max(yearlyResetMonth, 1), 12)
        let monthStart = cal.date(from: components)
        let monthEnd = monthStart.flatMap { cal.date(byAdding: DateComponents(month: 1, day: -1), to: $0) }
        let lastDay = monthEnd.map { cal.component(.day, from: $0) } ?? 28
        components.day = min(max(yearlyResetDay, 1), lastDay)
        return cal.date(from: components)
    }
}
