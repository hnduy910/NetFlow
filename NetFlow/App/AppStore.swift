import Foundation
import SwiftUI
import UserNotifications

@MainActor
final class AppStore: ObservableObject {
    @Published var settings: AppSettings
    @Published var plan: DataPlan
    @Published var dailyRecords: [DailyUsageRecord]
    @Published var liveSnapshot = NetworkSnapshot.zero
    @Published var currentRate = NetworkRate.zero
    @Published var alerts: [UsageAlertEvent]

    let networkContext = NetworkContextService()
    let capabilities = SystemCapabilitiesService()

    private let persistence = PersistenceService()
    private let tracker = UsageTracker()
    private let notificationService = NotificationService()
    private var timerTask: Task<Void, Never>?
    private var hasStarted = false

    init() {
        let loaded = persistence.load()
        settings = loaded.settings
        plan = loaded.plan
        dailyRecords = loaded.records
        alerts = loaded.alerts
        networkContext.setLocale(settings.appLanguage.locale)
        if normalizePlanCycle(now: Date()) {
            save()
        }
    }

    func start() async {
        guard !hasStarted else {
            await refreshAfterBecomingActive()
            return
        }
        hasStarted = true

        networkContext.requestAccessAndRefresh()
        _ = await notificationService.requestAuthorization()
        await refreshContext()
        await refresh()
        restartSamplingTimer()
    }

    func refreshAfterBecomingActive() async {
        await refreshContext()
        await refresh()
        restartSamplingTimer()
    }

    func pauseSampling() {
        timerTask?.cancel()
        timerTask = nil
        save()
    }

    private func restartSamplingTimer() {
        timerTask?.cancel()
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let seconds = max(self.settings.refreshSeconds, 1)
                try? await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
                guard !Task.isCancelled else { return }
                await self.refresh()
            }
        }
    }

    func refresh() async {
        let previousSnapshot = liveSnapshot
        let result = tracker.sample(previous: liveSnapshot)
        liveSnapshot = result.snapshot
        currentRate = result.rate
        merge(delta: result.delta, from: previousSnapshot.timestamp, to: result.snapshot.timestamp)
        normalizePlanCycle(now: result.snapshot.timestamp)
        checkAlerts()
        save()
    }

    func refreshContext() async {
        networkContext.setLocale(settings.appLanguage.locale)
        await networkContext.refreshNetworkDetails()
        await capabilities.refresh(context: networkContext)
    }

    func merge(delta: NetworkDelta, from start: Date, to end: Date) {
        guard delta.isValid, delta.totalBytes > 0 else { return }

        guard start != .distantPast, end > start else {
            merge(delta: delta, sampledAt: end, lastUpdated: end)
            return
        }

        let calendar = Calendar.current
        let totalDuration = end.timeIntervalSince(start)
        var cursor = start
        var remaining = delta

        // Keep a sample that crosses midnight out of the new day's counter.
        while cursor < end {
            let dayStart = calendar.startOfDay(for: cursor)
            let nextDay = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? end
            let segmentEnd = min(end, nextDay)
            let isLastSegment = segmentEnd >= end
            let segment: NetworkDelta

            if isLastSegment {
                segment = remaining
            } else {
                let fraction = min(max(segmentEnd.timeIntervalSince(cursor) / totalDuration, 0), 1)
                segment = NetworkDelta(
                    wifiReceived: portion(remaining.wifiReceived, fraction: fraction),
                    wifiSent: portion(remaining.wifiSent, fraction: fraction),
                    cellularReceived: portion(remaining.cellularReceived, fraction: fraction),
                    cellularSent: portion(remaining.cellularSent, fraction: fraction),
                    isValid: true
                )
                remaining = NetworkDelta(
                    wifiReceived: remaining.wifiReceived - segment.wifiReceived,
                    wifiSent: remaining.wifiSent - segment.wifiSent,
                    cellularReceived: remaining.cellularReceived - segment.cellularReceived,
                    cellularSent: remaining.cellularSent - segment.cellularSent,
                    isValid: true
                )
            }

            merge(delta: segment, sampledAt: cursor, lastUpdated: segmentEnd)
            cursor = segmentEnd
        }
    }

    private func merge(delta: NetworkDelta, sampledAt: Date, lastUpdated: Date) {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: sampledAt)

        if let index = dailyRecords.firstIndex(where: { calendar.isDate($0.date, inSameDayAs: day) }) {
            dailyRecords[index].add(delta)
            dailyRecords[index].lastUpdated = max(dailyRecords[index].lastUpdated, lastUpdated)
        } else {
            dailyRecords.append(
                DailyUsageRecord(
                    date: day,
                    delta: delta,
                    firstUpdated: sampledAt,
                    lastUpdated: lastUpdated
                )
            )
            dailyRecords.sort { $0.date > $1.date }
        }
    }

    @discardableResult
    func normalizePlanCycle(now: Date) -> Bool {
        let current = plan.cycleInterval(containing: now)
        guard plan.activeCycleStart != current.start else { return false }

        let previousCycleDate = current.start.addingTimeInterval(-1)
        let previousRemaining = plan.rolloverEnabled
            ? plan.remainingBytes(records: dailyRecords, at: previousCycleDate)
            : 0

        plan.activeCycleStart = current.start
        plan.activeCycleEnd = current.end
        plan.carriedBytes = previousRemaining
        plan.manualUsedBytes = 0
        plan.triggeredAlertIDs.removeAll()
        return true
    }

    func planUsage(at date: Date = Date()) -> UInt64 {
        let interval = plan.cycleInterval(containing: date)
        let measured = dailyRecords
            .filter { interval.contains($0.date) }
            .reduce(UInt64(0)) { $0 + $1.cellularTotalBytes }
        return measured &+ plan.manualUsedBytes
    }

    func isPlanExceeded(at date: Date = Date()) -> Bool {
        guard !plan.isUnlimited else { return false }

        let interval = plan.cycleInterval(containing: date)
        let calendar = Calendar.current
        let endOfDay = calendar.date(
            byAdding: .day,
            value: 1,
            to: calendar.startOfDay(for: date)
        ) ?? date
        let measuredThroughDate = dailyRecords
            .filter { interval.contains($0.date) && $0.date < endOfDay }
            .reduce(UInt64(0)) { $0 &+ $1.cellularTotalBytes }
        let manualUsage = interval.start == plan.activeCycleStart ? plan.manualUsedBytes : 0
        let capacity = interval.start == plan.activeCycleStart
            ? plan.effectiveCapacityBytes
            : plan.capacityBytes

        return measuredThroughDate &+ manualUsage > capacity
    }

    func checkAlerts() {
        guard !plan.isUnlimited else { return }
        let used = planUsage()
        let capacity = plan.effectiveCapacityBytes
        guard capacity > 0 else { return }

        for threshold in plan.alertThresholds where threshold.enabled {
            let reached: Bool
            switch threshold.kind {
            case .percentUsed:
                reached = Double(used) / Double(capacity) * 100 >= threshold.value
            case .remainingBytes:
                reached = Double(capacity > used ? capacity - used : 0) <= threshold.value
            }

            let key = "\(plan.activeCycleStart.timeIntervalSince1970)-\(threshold.id.uuidString)"
            guard reached, !plan.triggeredAlertIDs.contains(key) else { continue }

            plan.triggeredAlertIDs.insert(key)
            let remaining = capacity > used ? capacity - used : 0
            let event = UsageAlertEvent(date: Date(), threshold: threshold, remainingBytes: remaining)
            alerts.insert(event, at: 0)
            notificationService.postUsageAlert(
                event: event,
                planName: plan.displayName(locale: settings.appLanguage.locale),
                locale: settings.appLanguage.locale
            )
        }
    }

    func save() {
        persistence.save(settings: settings, plan: plan, records: dailyRecords, alerts: alerts)
    }

    func resetAll() {
        dailyRecords = []
        alerts = []
        liveSnapshot = .zero
        currentRate = .zero
        plan.manualUsedBytes = 0
        plan.triggeredAlertIDs.removeAll()
        tracker.resetBaseline()
        save()
    }

    private func portion(_ value: UInt64, fraction: Double) -> UInt64 {
        guard value > 0, fraction > 0 else { return 0 }
        let scaled = (Double(value) * fraction).rounded()
        return scaled >= Double(UInt64.max) ? value : UInt64(scaled)
    }
}

private final class NotificationService {
    func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
        } catch {
            return false
        }
    }

    func postUsageAlert(event: UsageAlertEvent, planName: String, locale: Locale) {
        let content = UNMutableNotificationContent()
        content.title = AppLocalization.string("notification_usage_title", locale: locale)
        content.body = String(
            format: AppLocalization.string("notification_usage_body", locale: locale),
            planName,
            ByteFormat.string(event.remainingBytes)
        )
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: event.id.uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
