import Foundation

struct PersistencePayload: Codable {
    var settings: AppSettings
    var plan: DataPlan
    var records: [DailyUsageRecord]
    var alerts: [UsageAlertEvent]
}

struct PersistenceService {
    private var url: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("netflow-data.json")
    }

    func load() -> PersistencePayload {
        guard let data = try? Data(contentsOf: url) else {
            return PersistencePayload(settings: AppSettings(), plan: DataPlan(), records: [], alerts: [])
        }

        // Current releases store dates as ISO-8601 strings. Keep the default decoder
        // as a migration fallback for older installs that used Foundation's date format.
        if let payload = try? JSONDecoder.netFlow.decode(PersistencePayload.self, from: data) {
            return payload
        }
        if let payload = try? JSONDecoder().decode(PersistencePayload.self, from: data) {
            return payload
        }

        return PersistencePayload(settings: AppSettings(), plan: DataPlan(), records: [], alerts: [])
    }

    func save(settings: AppSettings, plan: DataPlan, records: [DailyUsageRecord], alerts: [UsageAlertEvent]) {
        let payload = PersistencePayload(settings: settings, plan: plan, records: records, alerts: alerts)
        guard let data = try? JSONEncoder.pretty.encode(payload) else { return }
        try? data.write(to: url, options: .atomic)
    }

    func makeBackup(settings: AppSettings, plan: DataPlan, records: [DailyUsageRecord], alerts: [UsageAlertEvent]) throws -> URL {
        let payload = PersistencePayload(settings: settings, plan: plan, records: records, alerts: alerts)
        let data = try JSONEncoder.pretty.encode(payload)
        let stamp = Self.fileStamp.string(from: Date())
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("NetFlow_Backup_\(stamp).json")
        try data.write(to: destination, options: .atomic)
        return destination
    }

    func loadBackup(from sourceURL: URL) throws -> PersistencePayload {
        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer { if accessed { sourceURL.stopAccessingSecurityScopedResource() } }

        let data = try Data(contentsOf: sourceURL)
        if let payload = try? JSONDecoder.netFlow.decode(PersistencePayload.self, from: data) {
            return payload
        }
        return try JSONDecoder().decode(PersistencePayload.self, from: data)
    }

    func makeCSV(records: [DailyUsageRecord], interval: DateInterval) throws -> URL {
        let selected = records
            .filter { interval.contains($0.date) }
            .sorted { $0.date < $1.date }

        var rows = [
            "date,wifi_received_bytes,wifi_sent_bytes,wifi_total_bytes,cellular_received_bytes,cellular_sent_bytes,cellular_total_bytes,total_bytes,estimated"
        ]
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.calendar = Calendar(identifier: .gregorian)
        dateFormatter.dateFormat = "yyyy-MM-dd"

        rows.append(contentsOf: selected.map { record in
            [
                dateFormatter.string(from: record.date),
                String(record.wifiReceived),
                String(record.wifiSent),
                String(record.wifiTotalBytes),
                String(record.cellularReceived),
                String(record.cellularSent),
                String(record.cellularTotalBytes),
                String(record.totalBytes),
                record.isEstimated ? "true" : "false"
            ].joined(separator: ",")
        })

        let stamp = Self.fileStamp.string(from: Date())
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("NetFlow_Usage_\(stamp).csv")
        try (rows.joined(separator: "\n") + "\n").write(
            to: destination,
            atomically: true,
            encoding: .utf8
        )
        return destination
    }

    private static let fileStamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
}

extension JSONEncoder {
    static var pretty: JSONEncoder {
        let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]; e.dateEncodingStrategy = .iso8601; return e
    }
}

extension JSONDecoder {
    static var netFlow: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
