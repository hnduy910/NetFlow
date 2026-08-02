import Foundation
import UIKit
import CoreLocation
import UserNotifications

@MainActor
final class SystemCapabilitiesService: ObservableObject {
    @Published private(set) var snapshot = SystemCapabilitySnapshot()

    func refresh(context: NetworkContextService) async {
        let notificationSettings = await UNUserNotificationCenter.current().notificationSettings()
        let backgroundState = UIApplication.shared.backgroundRefreshStatus
        let locationState = CLLocationManager().authorizationStatus

        let notifications: CapabilityState = {
            switch notificationSettings.authorizationStatus {
            case .authorized, .provisional, .ephemeral: return .available
            case .denied: return .unavailable
            case .notDetermined: return .limited
            @unknown default: return .unknown
            }
        }()

        let background: CapabilityState = {
            switch backgroundState {
            case .available: return .available
            case .denied, .restricted: return .unavailable
            @unknown default: return .unknown
            }
        }()

        let location: CapabilityState = {
            switch locationState {
            case .authorizedAlways, .authorizedWhenInUse: return .available
            case .notDetermined: return .limited
            case .denied, .restricted: return .unavailable
            @unknown default: return .unknown
            }
        }()

        let wifiName: CapabilityState = context.connection.isWiFiActive ? .available : .limited

        let publicIP: CapabilityState = context.connection.publicIP == nil ? .limited : .available
        let vpn: CapabilityState = context.connection.isVPNActive ? .available : .limited

        // Widget and Live Activity support requires embedded extension/entitlements at signing time.
        // This build reports the actual packaged capability instead of assuming it from installer names.
        let hasWidgetExtension = Bundle.main.builtInPlugInsURL.flatMap {
            try? FileManager.default.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil)
        }?.contains(where: { $0.pathExtension == "appex" && $0.lastPathComponent.localizedCaseInsensitiveContains("widget") }) == true

        var items = [
            CapabilityItem(id: "usage", titleKey: "cap_usage", detailKey: "cap_usage_detail", systemImage: "chart.xyaxis.line", state: .available),
            CapabilityItem(id: "reports", titleKey: "cap_reports", detailKey: "cap_reports_detail", systemImage: "doc.richtext", state: .available),
            CapabilityItem(id: "notifications", titleKey: "cap_notifications", detailKey: "cap_notifications_detail", systemImage: "bell.badge", state: notifications),
            CapabilityItem(id: "background", titleKey: "cap_background", detailKey: "cap_background_detail", systemImage: "clock.arrow.circlepath", state: background),
            CapabilityItem(id: "location", titleKey: "cap_location", detailKey: "cap_location_detail", systemImage: "location", state: location),
            CapabilityItem(id: "ssid", titleKey: "cap_ssid", detailKey: "cap_ssid_detail", systemImage: "wifi", state: wifiName),
            CapabilityItem(id: "public_ip", titleKey: "cap_public_ip", detailKey: "cap_public_ip_detail", systemImage: "network", state: publicIP),
            CapabilityItem(id: "vpn", titleKey: "cap_vpn", detailKey: "cap_vpn_detail", systemImage: "lock.shield", state: vpn),
            CapabilityItem(id: "widgets", titleKey: "cap_widgets", detailKey: "cap_widgets_detail", systemImage: "square.grid.2x2", state: hasWidgetExtension ? .available : .unavailable),
            CapabilityItem(id: "live_activities", titleKey: "cap_live_activities", detailKey: "cap_live_activities_detail", systemImage: "waveform.path.ecg.rectangle", state: .unavailable)
        ]

        // A capability-oriented label is more reliable than guessing LiveContainer/TrollStore from private paths.
        let enhancedCount = items.filter { $0.state == .available }.count
        let environmentTitle: String
        let environmentDetail: String
        if hasWidgetExtension && background == .available && notifications == .available {
            environmentTitle = "environment_full"
            environmentDetail = "environment_full_detail"
        } else if enhancedCount >= 6 {
            environmentTitle = "environment_standard"
            environmentDetail = "environment_standard_detail"
        } else {
            environmentTitle = "environment_limited"
            environmentDetail = "environment_limited_detail"
        }

        items.sort { $0.id < $1.id }
        snapshot = SystemCapabilitySnapshot(
            environmentTitleKey: environmentTitle,
            environmentDetailKey: environmentDetail,
            items: items,
            lastChecked: Date()
        )
    }
}
