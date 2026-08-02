import Foundation

struct DailyUsageRecord: Codable, Identifiable, Hashable {
    var id = UUID()
    var date: Date
    var wifiReceived: UInt64
    var wifiSent: UInt64
    var cellularReceived: UInt64
    var cellularSent: UInt64
    var firstUpdated: Date
    var lastUpdated: Date
    var isEstimated = false

    init(date: Date, delta: NetworkDelta, firstUpdated: Date, lastUpdated: Date) {
        self.date = date
        wifiReceived = delta.wifiReceived
        wifiSent = delta.wifiSent
        cellularReceived = delta.cellularReceived
        cellularSent = delta.cellularSent
        self.firstUpdated = firstUpdated
        self.lastUpdated = lastUpdated
    }

    mutating func add(_ delta: NetworkDelta) {
        wifiReceived += delta.wifiReceived
        wifiSent += delta.wifiSent
        cellularReceived += delta.cellularReceived
        cellularSent += delta.cellularSent
    }

    var wifiTotalBytes: UInt64 { wifiReceived + wifiSent }
    var cellularTotalBytes: UInt64 { cellularReceived + cellularSent }
    var totalBytes: UInt64 { wifiTotalBytes + cellularTotalBytes }
}
