import UIKit

struct PDFReportOptions {
    var title: String
    var interval: DateInterval
    var includeWifi = true
    var includeCellular = true
    var locale: Locale = .current
}

struct PDFReportService {
    func makePDF(options: PDFReportOptions, plan: DataPlan, records: [DailyUsageRecord]) throws -> URL {
        let selected = records.filter { options.interval.contains($0.date) }.sorted { $0.date < $1.date }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("NetFlow_\(Int(Date().timeIntervalSince1970)).pdf")
        let page = CGRect(x: 0, y: 0, width: 595, height: 842)
        let renderer = UIGraphicsPDFRenderer(bounds: page)
        try renderer.writePDF(to: url) { context in
            var y: CGFloat = 44
            let localized: (String) -> String = { key in
                AppLocalization.string(key, locale: options.locale)
            }
            let shortDay = DateFormatter()
            shortDay.locale = options.locale
            shortDay.dateStyle = .medium

            func newPage() { context.beginPage(); y = 44 }
            func line(_ text: String, font: UIFont = .systemFont(ofSize: 10), height: CGFloat = 18) {
                if y + height > page.height - 40 { newPage() }
                text.draw(in: CGRect(x: 40, y: y, width: page.width - 80, height: height), withAttributes: [.font: font, .foregroundColor: UIColor.label])
                y += height
            }
            newPage()
            line(options.title, font: .boldSystemFont(ofSize: 20), height: 30)
            line(
                String(
                    format: localized("pdf_date_range"),
                    shortDay.string(from: options.interval.start),
                    shortDay.string(from: options.interval.end)
                ),
                font: .systemFont(ofSize: 11),
                height: 24
            )
            line(
                String(
                    format: localized("pdf_plan_cycle"),
                    plan.displayName(locale: options.locale),
                    localized(plan.cycleType.rawValue)
                ),
                height: 24
            )
            line(localized("pdf_daily_details"), font: .boldSystemFont(ofSize: 13), height: 28)
            line(localized("pdf_columns"), font: .boldSystemFont(ofSize: 9), height: 22)
            for r in selected {
                let cell = options.includeCellular ? "\(ByteFormat.string(r.cellularReceived)) / \(ByteFormat.string(r.cellularSent))" : "—"
                let wifi = options.includeWifi ? "\(ByteFormat.string(r.wifiReceived)) / \(ByteFormat.string(r.wifiSent))" : "—"
                let total = (options.includeCellular ? r.cellularTotalBytes : 0) + (options.includeWifi ? r.wifiTotalBytes : 0)
                let flag = r.isEstimated ? localized("pdf_estimated") : ""
                line("\(shortDay.string(from: r.date))\(flag)    \(cell)    \(wifi)    \(ByteFormat.string(total))", height: 20)
            }
            let totalCell = selected.reduce(0) { $0 + $1.cellularTotalBytes }
            let totalWifi = selected.reduce(0) { $0 + $1.wifiTotalBytes }
            y += 10
            line(localized("pdf_total"), font: .boldSystemFont(ofSize: 13), height: 25)
            if options.includeCellular {
                line(String(format: localized("pdf_cellular_data"), ByteFormat.string(totalCell)))
            }
            if options.includeWifi {
                line(String(format: localized("pdf_wifi"), ByteFormat.string(totalWifi)))
            }
            line(
                String(
                    format: localized("pdf_total_data"),
                    ByteFormat.string((options.includeCellular ? totalCell : 0) + (options.includeWifi ? totalWifi : 0))
                ),
                font: .boldSystemFont(ofSize: 11)
            )
        }
        return url
    }
}
