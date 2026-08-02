import Foundation

enum CapabilityState: String, Codable, CaseIterable {
    case available
    case limited
    case unavailable
    case unknown
}

struct CapabilityItem: Identifiable, Equatable {
    let id: String
    let titleKey: String
    let detailKey: String
    let systemImage: String
    var state: CapabilityState
}

struct SystemCapabilitySnapshot: Equatable {
    var environmentTitleKey: String = "environment_checking"
    var environmentDetailKey: String = "environment_checking_detail"
    var items: [CapabilityItem] = []
    var lastChecked: Date = .distantPast
}
