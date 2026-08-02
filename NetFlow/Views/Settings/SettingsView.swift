import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: AppStore
    @State private var exportURL: URL?
    @State private var showShare = false

    var body: some View {
        ScrollView {
            VStack(spacing: AppChrome.spacing) {
                cardSection("language") {
                    Picker("language", selection: $store.settings.appLanguage) {
                        Text("system").tag(AppLanguage.system)
                        Text("vietnamese").tag(AppLanguage.vietnamese)
                        Text("english").tag(AppLanguage.english)
                    }
                    .pickerStyle(.menu)
                }

                cardSection("appearance") {
                    Picker("appearance", selection: $store.settings.theme) {
                        Text("system").tag(AppTheme.system)
                        Text("light").tag(AppTheme.light)
                        Text("dark").tag(AppTheme.dark)
                    }
                    .pickerStyle(.menu)
                }

                cardSection("report") {
                    Button("export_month_pdf") { exportPDF(months: 1) }
                    Button("export_year_pdf") { exportPDF(months: 12) }
                }

                cardSection("data") {
                    Button("reset_all", role: .destructive) { store.resetAll() }
                }

                Text("privacy_local_only")
                    .font(.footnote)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .netFlowCard(cornerRadius: 18)

                cardSection("about") {
                    LabeledContent("version", value: appVersionText)
                    LabeledContent("author", value: "Hoàng Ngọc Duy")
                }
            }
            .padding(AppChrome.pagePadding)
        }
        .netFlowPageBackground()
        .navigationTitle("settings")
        .onChange(of: store.settings) { _ in store.save() }
        .onChange(of: store.settings.appLanguage) { _ in
            Task { await store.refreshContext() }
        }
        .sheet(isPresented: $showShare) { if let exportURL { ShareSheet(items: [exportURL]) } }
    }

    private func cardSection<Content: View>(
        _ title: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .netFlowSectionTitle()
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .netFlowCard(cornerRadius: 18)
    }

    private var appVersionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let displayVersion = version?.isEmpty == false
            ? version!
            : AppLocalization.string("unknown", locale: store.settings.appLanguage.locale)
        guard let buildDate = Bundle.main.object(forInfoDictionaryKey: "NetFlowBuildDate") as? String,
              !buildDate.isEmpty else {
            return displayVersion
        }

        return "\(displayVersion) (\(buildDate))"
    }

    private func exportPDF(months: Int) {
        let end = Date()
        let start = Calendar.current.date(byAdding: .month, value: -months, to: end) ?? end
        let locale = store.settings.appLanguage.locale
        let options = PDFReportOptions(
            title: AppLocalization.string("network_report", locale: locale),
            interval: DateInterval(start: start, end: end),
            locale: locale
        )
        exportURL = try? PDFReportService().makePDF(options: options, plan: store.plan, records: store.dailyRecords)
        showShare = exportURL != nil
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    var items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
