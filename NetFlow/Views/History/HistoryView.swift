import SwiftUI
import Charts

struct HistoryView: View {
    @EnvironmentObject var store: AppStore
    @State private var days = 30

    var records: [DailyUsageRecord] { Array(store.dailyRecords.prefix(days)).reversed() }
    private var appLocale: Locale { store.settings.appLanguage.locale }

    var body: some View {
        ScrollView {
            VStack(spacing: AppChrome.spacing) {
            Picker("range", selection: $days) {
                Text("days_7").tag(7); Text("days_30").tag(30); Text("days_365").tag(365)
            }
            .pickerStyle(.segmented)
            .netFlowCard(cornerRadius: 16)

            Chart(records) { r in
                BarMark(
                    x: .value(AppLocalization.string("chart_day", locale: appLocale), r.date, unit: .day),
                    y: .value(AppLocalization.string("cellular", locale: appLocale), r.cellularTotalBytes)
                )
                BarMark(
                    x: .value(AppLocalization.string("chart_day", locale: appLocale), r.date, unit: .day),
                    y: .value(AppLocalization.string("wifi", locale: appLocale), r.wifiTotalBytes)
                )
            }
            .frame(height: 220)
            .netFlowCard(cornerRadius: 18)

            VStack(alignment: .leading, spacing: 10) {
                Text("daily_details")
                    .netFlowSectionTitle()
                ForEach(store.dailyRecords.prefix(days)) { r in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack { Text(r.date, style: .date).font(.headline); Spacer(); Text(ByteFormat.string(r.totalBytes)).bold() }
                        Text("\(AppLocalization.string("cellular", locale: appLocale)) \(ByteFormat.string(r.cellularTotalBytes)) • \(AppLocalization.string("wifi", locale: appLocale)) \(ByteFormat.string(r.wifiTotalBytes))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .netFlowCard(cornerRadius: 14)
                }
            }
            }
            .padding(AppChrome.pagePadding)
        }
        .netFlowPageBackground()
        .navigationTitle(Text(verbatim: AppLocalization.string("history", locale: appLocale)))
    }
}
