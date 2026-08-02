import Foundation

struct NetworkCounter: Codable, Hashable {
    var received: UInt64
    var sent: UInt64
    static let zero = NetworkCounter(received: 0, sent: 0)
    var total: UInt64 { received + sent }
}

struct NetworkSnapshot: Codable, Hashable {
    var wifi: NetworkCounter
    var cellular: NetworkCounter
    var timestamp: Date
    static let zero = NetworkSnapshot(wifi: .zero, cellular: .zero, timestamp: .distantPast)
}

struct NetworkDelta: Codable, Hashable {
    var wifiReceived: UInt64
    var wifiSent: UInt64
    var cellularReceived: UInt64
    var cellularSent: UInt64
    var isValid: Bool
    static let zero = NetworkDelta(wifiReceived: 0, wifiSent: 0, cellularReceived: 0, cellularSent: 0, isValid: false)
    var totalBytes: UInt64 { wifiReceived + wifiSent + cellularReceived + cellularSent }
}

struct NetworkRate: Hashable {
    var wifiDown: Double
    var wifiUp: Double
    var cellularDown: Double
    var cellularUp: Double
    static let zero = NetworkRate(wifiDown: 0, wifiUp: 0, cellularDown: 0, cellularUp: 0)
}

struct ConnectionStatus: Hashable {
    var wifiSSID: String?
    var wifiLocalIPv4: String?
    var cellularLocalIPv4: String?
    var publicIPv4: String?
    var publicIPv6: String?
    var publicIPInterface: String?
    var carrierName: String?
    var isVPNActive = false
    var vpnDisplayName: String?
    var vpnLocalIP: String?
    var vpnCountryName: String?
    var isWiFiActive = false
    var isCellularActive = false
    var lastUpdated: Date?

    // Compatibility for older views/services.
    var publicIP: String? { publicIPv4 ?? publicIPv6 }
}

struct WeatherStatus: Hashable {
    var temperatureCelsius: Double?
    var conditionCode: Int?
    var precipitationProbability: Int?
    var windSpeedKmh: Double?
    var uvIndex: Double?
    var locationName = "—"
    var lastUpdated: Date?

    var symbolName: String {
        guard let code = conditionCode else { return "cloud" }
        switch code {
        case 0: return "sun.max.fill"
        case 1...3: return "cloud.sun.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51...67, 80...82: return "cloud.rain.fill"
        case 71...77, 85, 86: return "cloud.snow.fill"
        case 95...99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }
}
