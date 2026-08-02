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
    var effectiveCapacityBytes: UInt64 { isUnlimited ? UInt64.max : capacityBytes + carriedBytes }

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
            var comps = cal.dateComponents([.year, .month], from: date)
            let maxDay = cal.range(of: .day, in: .month, for: date)?.count ?? 28
            comps.day = min(monthlyResetDay, maxDay)
            var start = cal.date(from: comps) ?? startOfDay
            if date < start {
                start = cal.date(byAdding: .month, value: -1, to: start)!
            }
            return DateInterval(start: start, end: cal.date(byAdding: .month, value: 1, to: start)!)
        case .yearly:
            var comps = cal.dateComponents([.year], from: date)
            comps.month = yearlyResetMonth
            comps.day = yearlyResetDay
            var start = cal.date(from: comps) ?? startOfDay
            if date < start { start = cal.date(byAdding: .year, value: -1, to: start)! }
            return DateInterval(start: start, end: cal.date(byAdding: .year, value: 1, to: start)!)
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
        let used = records.filter { interval.contains($0.date) }.reduce(0) { $0 + $1.cellularTotalBytes } + manualUsedBytes
        return effectiveCapacityBytes > used ? effectiveCapacityBytes - used : 0
    }
}
