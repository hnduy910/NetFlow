import SwiftUI

struct OverviewView: View {
    @EnvironmentObject var store: AppStore
    @ObservedObject private var context: NetworkContextService
    @State private var isRefreshing = false

    init(context: NetworkContextService) { self.context = context }

    private var used: UInt64 { store.planUsage() }
    private var remaining: UInt64 {
        store.plan.isUnlimited ? 0 : max(store.plan.effectiveCapacityBytes - min(used, store.plan.effectiveCapacityBytes), 0)
    }
    private var today: DailyUsageRecord? {
        store.dailyRecords.first { Calendar.current.isDateInToday($0.date) }
    }
    private var monthCellularBytes: UInt64 { usageTotal(\.cellularTotalBytes, in: monthInterval) }
    private var yearCellularBytes: UInt64 { usageTotal(\.cellularTotalBytes, in: yearInterval) }
    private var monthWiFiBytes: UInt64 { usageTotal(\.wifiTotalBytes, in: monthInterval) }
    private var yearWiFiBytes: UInt64 { usageTotal(\.wifiTotalBytes, in: yearInterval) }
    private var appLocale: Locale { store.settings.appLanguage.locale }

    var body: some View {
        ScrollView {
            VStack(spacing: AppChrome.spacing) {
                ViewThatFits(in: .horizontal) { tablet; phone }
            }
            .padding(AppChrome.pagePadding)
        }
        .netFlowPageBackground()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await refreshEverything()
        }
    }

    private func refreshEverything() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        await store.refresh()
        await store.refreshContext()
    }

    private var phone: some View {
        VStack(spacing: AppChrome.spacing) {
            header
            usage
            HStack(spacing: 12) { cellular; wifi }
            vpn
            speed
        }
    }

    private var tablet: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(spacing: AppChrome.spacing) { header; usage; speed }
                .frame(minWidth: 340, maxWidth: 430)
            VStack(spacing: AppChrome.spacing) {
                HStack(spacing: 12) { cellular; wifi }
                vpn
            }
            .frame(minWidth: 430, maxWidth: .infinity)
        }
    }

    private var header: some View {
        TimelineView(.periodic(from: .now, by: 1)) { value in
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "clock")
                        .foregroundStyle(.blue)
                    Text(Self.compactDateTimeFormatter.string(from: value.date))
                        .font(.headline.weight(.semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                    Spacer()
                    Button { Task { await refreshEverything() } } label: {
                        Image(systemName: isRefreshing ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                            .font(.headline)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)
                    .accessibilityLabel(Text("refresh"))
                }

                Label {
                    Text(context.weather.locationName)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.38)
                        .allowsTightening(true)
                } icon: {
                    Image(systemName: "location.fill")
                        .foregroundStyle(.red)
                }

                HStack(spacing: 12) {
                    Image(systemName: context.weather.symbolName)
                        .font(.title3)
                        .symbolRenderingMode(.multicolor)

                    Label(context.weather.temperatureCelsius.map { "\(Int($0.rounded()))°C" } ?? "—°C", systemImage: "thermometer.medium")
                        .font(.headline)
                        .foregroundStyle(.orange)

                    Label(rainProbabilityText, systemImage: "cloud.rain.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.blue)

                    if let windSpeed = context.weather.windSpeedKmh {
                        Label(String(format: "%.0f km/h", windSpeed), systemImage: "wind")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                    if let uvIndex = context.weather.uvIndex {
                        Label("UV \(String(format: "%.0f", uvIndex))", systemImage: "sun.max")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.62)
                .allowsTightening(true)
            }
            .netFlowCard(cornerRadius: 18)
        }
    }

    private static let compactDateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "vi_VN")
        formatter.dateFormat = "dd/MM/yyyy HH:mm:ss"
        return formatter
    }()

    private var rainProbabilityText: String {
        guard let value = context.weather.precipitationProbability else { return "—%" }
        return "\(value)%"
    }

    private var usage: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                usageMetric(
                    title: AppLocalization.string("used", locale: appLocale),
                    value: formattedUsage(used),
                    icon: "arrow.up.forward.circle.fill",
                    tint: .blue
                )

                Divider().frame(height: 62)

                usageMetric(
                    title: store.plan.isUnlimited
                        ? AppLocalization.string("unlimited", locale: appLocale)
                        : AppLocalization.string("remaining", locale: appLocale),
                    value: store.plan.isUnlimited ? "∞" : formattedUsage(remaining),
                    icon: "gauge.with.dots.needle.67percent",
                    tint: store.plan.isUnlimited ? .green : remainingTint
                )
            }

            Divider()

            HStack(spacing: 5) {
                Text("\(AppLocalization.string("data_plan", locale: appLocale)):")
                    .foregroundStyle(.secondary)
                Text(planSummary)
                    .fontWeight(.bold)
                    .foregroundStyle(.green)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .font(.headline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .netFlowCard(cornerRadius: 18)
    }

    private func usageMetric(title: String, value: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
            Text(value)
                .font(.system(.title2, design: .rounded, weight: .bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var remainingTint: Color {
        guard store.plan.effectiveCapacityBytes > 0 else { return .secondary }
        let fraction = Double(remaining) / Double(store.plan.effectiveCapacityBytes)
        if fraction <= 0.1 { return .red }
        if fraction <= 0.25 { return .orange }
        return .green
    }

    private var planSummary: String {
        if store.plan.isUnlimited { return AppLocalization.string("unlimited", locale: appLocale) }
        let cycle = AppLocalization.string(store.plan.cycleType.rawValue, locale: appLocale)
        return "\(cycle) - \(formattedPlanCapacity)"
    }

    private var selectedCapacityUnit: CapacityDisplayUnit {
        CapacityDisplayUnit(rawValue: store.plan.capacityDisplayUnitRaw ?? "GB") ?? .gb
    }

    private var formattedPlanCapacity: String {
        let preferred = selectedCapacityUnit
        let value = Double(store.plan.capacityBytes) / preferred.multiplier
        let number = value.formatted(.number.precision(.fractionLength(0...2)))
        return "\(number) \(preferred.rawValue)"
    }

    private func formattedUsage(_ bytes: UInt64) -> String {
        let preferred = selectedCapacityUnit
        let value = Double(bytes) / preferred.multiplier
        let decimals: Int
        switch preferred {
        case .mb: decimals = value < 100 ? 2 : 1
        case .gb: decimals = value < 10 ? 2 : 1
        case .tb: decimals = 2
        }
        return "\(value.formatted(.number.precision(.fractionLength(decimals)))) \(preferred.rawValue)"
    }

    private var monthInterval: DateInterval {
        let calendar = Calendar.current
        let now = Date()
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        let end = calendar.date(byAdding: .month, value: 1, to: start) ?? now
        return DateInterval(start: start, end: end)
    }

    private var yearInterval: DateInterval {
        let calendar = Calendar.current
        let now = Date()
        let start = calendar.date(from: calendar.dateComponents([.year], from: now)) ?? now
        let end = calendar.date(byAdding: .year, value: 1, to: start) ?? now
        return DateInterval(start: start, end: end)
    }

    private var currentMonthTitle: String {
        let month = Calendar.current.component(.month, from: Date())
        return "\(AppLocalization.string("month", locale: appLocale)) \(month)"
    }

    private var currentYearTitle: String {
        let year = Calendar.current.component(.year, from: Date())
        return "\(AppLocalization.string("year", locale: appLocale)) \(year)"
    }

    private func usageTotal(_ keyPath: KeyPath<DailyUsageRecord, UInt64>, in interval: DateInterval) -> UInt64 {
        store.dailyRecords
            .filter { interval.contains($0.date) }
            .reduce(UInt64(0)) { $0 + $1[keyPath: keyPath] }
    }

    private var cellular: some View {
        DetailCard(
            title: AppLocalization.string("cellular_data", locale: appLocale),
            icon: "antenna.radiowaves.left.and.right",
            primary: context.connection.isCellularActive
                ? AppLocalization.string("connected", locale: appLocale)
                : AppLocalization.string("not_active", locale: appLocale),
            rows: [
                (AppLocalization.string("local_ip", locale: appLocale), context.connection.cellularLocalIPv4 ?? "—"),
                ("IPv4", context.connection.isCellularActive ? (context.connection.publicIPv4 ?? "—") : "—"),
                (AppLocalization.string("today", locale: appLocale), ByteFormat.string(today?.cellularTotalBytes ?? 0)),
                (currentMonthTitle, ByteFormat.string(monthCellularBytes)),
                (currentYearTitle, ByteFormat.string(yearCellularBytes))
            ]
        )
    }

    private var wifi: some View {
        DetailCard(
            title: AppLocalization.string("wifi", locale: appLocale),
            icon: "wifi",
            primary: context.connection.isWiFiActive
                ? AppLocalization.string("connected", locale: appLocale)
                : AppLocalization.string("not_connected", locale: appLocale),
            rows: [
                (AppLocalization.string("local_ip", locale: appLocale), context.connection.wifiLocalIPv4 ?? "—"),
                ("IPv4", context.connection.isWiFiActive ? (context.connection.publicIPv4 ?? "—") : "—"),
                (AppLocalization.string("today", locale: appLocale), ByteFormat.string(today?.wifiTotalBytes ?? 0)),
                (currentMonthTitle, ByteFormat.string(monthWiFiBytes)),
                (currentYearTitle, ByteFormat.string(yearWiFiBytes))
            ]
        )
    }

    private var vpn: some View {
        let isVPNActive = context.connection.isVPNActive
        let vpnIP = context.connection.vpnPublicIP ?? context.connection.vpnLocalIP
        let vpnText: String? = {
            guard isVPNActive else { return nil }
            var parts: [String] = []
            if let vpnIP {
                parts.append(vpnIP)
            }
            if let country = context.connection.vpnCountryName {
                parts.append(country)
            }
            return parts.isEmpty ? AppLocalization.string("connected", locale: appLocale) : parts.joined(separator: " · ")
        }()

        return HStack(spacing: 14) {
            Image(systemName: isVPNActive ? "lock.shield.fill" : "lock.shield")
                .font(.title)
                .foregroundStyle(isVPNActive ? Color.green : Color.secondary)
            VStack(alignment: .leading, spacing: 5) {
                Text(AppLocalization.string("vpn", locale: appLocale)).font(.headline)
                Text(vpnText ?? AppLocalization.string("vpn_disconnected", locale: appLocale))
                    .font(.subheadline)
                    .foregroundStyle(isVPNActive ? Color.green : Color.secondary)
                    .textSelection(.enabled)
            }
            Spacer()
            Circle()
                .fill(isVPNActive ? Color.green : Color.secondary.opacity(0.3))
                .frame(width: 11, height: 11)
        }
        .netFlowCard(cornerRadius: 18)
    }

    private var speed: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("current_speed").font(.headline)
            HStack {
                Label(ByteFormat.rate(store.currentRate.cellularDown + store.currentRate.wifiDown), systemImage: "arrow.down.circle.fill")
                Spacer()
                Label(ByteFormat.rate(store.currentRate.cellularUp + store.currentRate.wifiUp), systemImage: "arrow.up.circle.fill")
            }
        }
        .netFlowCard(cornerRadius: 18)
    }

    private var lastUpdated: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock.arrow.circlepath")
            Text(AppLocalization.string("last_updated", locale: appLocale))
            Text((context.connection.lastUpdated ?? Date()).formatted(date: .omitted, time: .standard))
                .monospacedDigit()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .center)
    }

}

private struct DetailCard: View {
    let title: String
    let icon: String
    let primary: String
    let rows: [(String, String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .netFlowSectionTitle()
            Text(primary).font(.subheadline.weight(.semibold)).lineLimit(1)
            Divider()
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.0).font(.caption2).foregroundStyle(.secondary)
                    Text(row.1)
                        .font(.caption.weight(.medium))
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)
                        .textSelection(.enabled)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .netFlowCard(cornerRadius: 18)
    }
}
