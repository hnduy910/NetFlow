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
