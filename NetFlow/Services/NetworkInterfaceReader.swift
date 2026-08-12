import Foundation
import Darwin
import Network
import CoreLocation
import CFNetwork

final class NetworkInterfaceReader {
    func read() -> NetworkSnapshot {
        var interfaceList: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaceList) == 0, let first = interfaceList else {
            return NetworkSnapshot(wifi: .zero, cellular: .zero, timestamp: Date())
        }
        defer { freeifaddrs(first) }

        var wifi = NetworkCounter.zero
        var cellular = NetworkCounter.zero
        var cursor: UnsafeMutablePointer<ifaddrs>? = first

        while let interface = cursor {
            let item = interface.pointee
            let name = String(cString: item.ifa_name)

            if let rawData = item.ifa_data {
                let data = rawData.assumingMemoryBound(to: if_data.self).pointee
                if name.hasPrefix("en") {
                    wifi.received &+= UInt64(data.ifi_ibytes)
                    wifi.sent &+= UInt64(data.ifi_obytes)
                } else if name.hasPrefix("pdp_ip") {
                    cellular.received &+= UInt64(data.ifi_ibytes)
                    cellular.sent &+= UInt64(data.ifi_obytes)
                }
            }

            cursor = item.ifa_next
        }

        return NetworkSnapshot(wifi: wifi, cellular: cellular, timestamp: Date())
    }
}

@MainActor
final class NetworkContextService: NSObject, ObservableObject {
    @Published private(set) var connection = ConnectionStatus()
    @Published private(set) var weather = WeatherStatus()

    // Compatibility properties used by older views/services.
    var pathUsesWiFi: Bool { connection.isWiFiActive }
    var wifiSSID: String? { connection.wifiSSID }
    var publicIPAddress: String? { connection.publicIP }
    var vpnConnected: Bool { connection.isVPNActive }

    private let pathMonitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "NetFlow.NetworkPath")
    private let locationManager = CLLocationManager()
    private var currentLocation: CLLocation?
    private var pathUsesOtherInterface = false
    private var networkDetailsTask: Task<Void, Never>?
    private var publicIPTask: Task<Void, Never>?
    private var cachedVPNCountryByIP: [String: String] = [:]
    private var activeNetworkSignature = ""
    private var activeVPNSignature = ""
    private var activeVPNTunnelSignature = ""
    private var activePublicIPInterface: String?
    private var lastResolvedPublicNetworkSignature: String?
    private var lastResolvedVPNSignature: String?
    private var inFlightPublicIPRequestKey: String?
    private var appLocale = Locale.current

    private enum CacheKey {
        static let publicIPv4 = "NetFlow.cachedPublicIPv4"
        static let publicIPv6 = "NetFlow.cachedPublicIPv6"
        static let networkSignature = "NetFlow.cachedPublicNetworkSignature"
    }

    override init() {
        super.init()

        connection.publicIPv4 = UserDefaults.standard.string(forKey: CacheKey.publicIPv4)
        connection.publicIPv6 = UserDefaults.standard.string(forKey: CacheKey.publicIPv6)
        lastResolvedPublicNetworkSignature = UserDefaults.standard.string(forKey: CacheKey.networkSignature)

        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = kCLDistanceFilterNone

        pathMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                self.connection.isWiFiActive = path.status == .satisfied && path.usesInterfaceType(.wifi)
                self.connection.isCellularActive = path.status == .satisfied && path.usesInterfaceType(.cellular)
                self.pathUsesOtherInterface = path.status == .satisfied && path.usesInterfaceType(.other)
                self.scheduleFastNetworkRefresh()
            }
        }
        pathMonitor.start(queue: monitorQueue)
    }

    deinit {
        networkDetailsTask?.cancel()
        publicIPTask?.cancel()
        pathMonitor.cancel()
    }

    func setLocale(_ locale: Locale) {
        appLocale = locale
    }

    func requestAccessAndRefresh() {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            locationManager.requestLocation()
        default:
            break
        }

        scheduleFastNetworkRefresh()
    }

    func refreshNetworkDetails() async {
        refreshLocalNetworkDetails()
        refreshPublicIPInBackground()

        if locationManager.authorizationStatus == .authorizedAlways ||
            locationManager.authorizationStatus == .authorizedWhenInUse {
            locationManager.requestLocation()
        }

        if let currentLocation {
            await updateWeather(for: currentLocation)
        } else if weather.temperatureCelsius == nil {
            await updateApproximateWeatherFromNetwork()
        }
    }

    private func scheduleFastNetworkRefresh() {
        networkDetailsTask?.cancel()
        networkDetailsTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.refreshNetworkDetails()
        }
    }

    private func refreshLocalNetworkDetails() {
        let interfaces = Self.interfaceAddresses()

        connection.wifiLocalIPv4 = interfaces.first(where: {
            $0.isActive && $0.family == AF_INET && $0.name.hasPrefix("en")
        })?.address

        connection.cellularLocalIPv4 = interfaces.first(where: {
            $0.isActive && $0.family == AF_INET && $0.name.hasPrefix("pdp_ip")
        })?.address

        if let vpnInterface = Self.detectActiveVPNInterface(
            from: interfaces,
            pathUsesOtherInterface: pathUsesOtherInterface
        ) {
            connection.isVPNActive = true
            connection.vpnLocalIP = vpnInterface.address
            connection.vpnDisplayName = AppLocalization.string("vpn_system_tunnel", locale: appLocale)
        } else {
            connection.isVPNActive = false
            connection.vpnLocalIP = nil
            connection.vpnDisplayName = nil
        }

        connection.wifiSSID = nil
        connection.carrierName = nil
        let networkSignature = [
            connection.isWiFiActive ? "wifi" : "",
            connection.isCellularActive ? "cellular" : "",
            connection.wifiLocalIPv4 ?? "",
            connection.cellularLocalIPv4 ?? ""
        ].joined(separator: "|")
        let vpnTunnelSignature = [
            connection.isVPNActive ? "vpn" : "",
            connection.vpnLocalIP ?? ""
        ].joined(separator: "|")
        let vpnSignature = [networkSignature, vpnTunnelSignature].joined(separator: "|")
        let vpnTunnelChanged = vpnTunnelSignature != activeVPNTunnelSignature

        activeNetworkSignature = networkSignature
        activeVPNSignature = vpnSignature
        activeVPNTunnelSignature = vpnTunnelSignature
        activePublicIPInterface = currentPublicIPInterface()
        connection.publicIPInterface = activePublicIPInterface

        if vpnTunnelChanged {
            connection.vpnPublicIPv4 = nil
            connection.vpnPublicIPv6 = nil
            connection.vpnCountryName = nil
            lastResolvedVPNSignature = nil
        }
        connection.lastUpdated = Date()
    }

    private func refreshPublicIPInBackground() {
        let networkSignature = activeNetworkSignature
        let vpnSignature = activeVPNSignature
        let hasActiveNetwork = connection.isWiFiActive || connection.isCellularActive
        let hasPublicIP = connection.publicIPv4 != nil || connection.publicIPv6 != nil
        let hasVPNIP = connection.vpnPublicIPv4 != nil || connection.vpnPublicIPv6 != nil
        let fetchUnderlyingIP = !connection.isVPNActive && hasActiveNetwork &&
            (lastResolvedPublicNetworkSignature != networkSignature || !hasPublicIP)
        let fetchVPNIP = connection.isVPNActive &&
            (lastResolvedVPNSignature != vpnSignature || !hasVPNIP || connection.vpnCountryName == nil)

        guard fetchUnderlyingIP || fetchVPNIP else { return }

        let requestKey = [
            networkSignature,
            vpnSignature,
            fetchUnderlyingIP ? "underlying" : "",
            fetchVPNIP ? "vpn" : ""
        ].joined(separator: "|")
        if inFlightPublicIPRequestKey == requestKey { return }
        publicIPTask?.cancel()
        inFlightPublicIPRequestKey = requestKey

        publicIPTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.inFlightPublicIPRequestKey == requestKey {
                    self.inFlightPublicIPRequestKey = nil
                    self.publicIPTask = nil
                }
            }

            let nonce = String(Int(Date().timeIntervalSince1970 * 1000))
            async let publicIPv4 = Self.fetchPublicIPAddress(
                endpoint: "https://api4.ipify.org?format=json&netflow_ts=\(nonce)"
            )
            async let publicIPv6 = Self.fetchPublicIPAddress(
                endpoint: "https://api6.ipify.org?format=json&netflow_ts=\(nonce)"
            )
            let resolvedIPv4 = await publicIPv4
            let resolvedIPv6 = await publicIPv6

            guard networkSignature == self.activeNetworkSignature,
                  vpnSignature == self.activeVPNSignature else { return }

            if fetchUnderlyingIP {
                if resolvedIPv4 != nil || resolvedIPv6 != nil {
                    self.connection.publicIPv4 = resolvedIPv4
                    self.connection.publicIPv6 = resolvedIPv6
                    self.lastResolvedPublicNetworkSignature = networkSignature
                    self.persistPublicIPCache(networkSignature: networkSignature)
                }
            }

            if fetchVPNIP {
                self.connection.vpnPublicIPv4 = resolvedIPv4
                self.connection.vpnPublicIPv6 = resolvedIPv6
                if let vpnPublicIP = self.connection.vpnPublicIP {
                    if let cachedCountry = self.cachedVPNCountryByIP[vpnPublicIP] {
                        self.connection.vpnCountryName = cachedCountry
                    } else if let country = await Self.fetchIPCountryName(for: vpnPublicIP) {
                        guard networkSignature == self.activeNetworkSignature,
                              vpnSignature == self.activeVPNSignature else { return }
                        self.cachedVPNCountryByIP[vpnPublicIP] = country
                        self.connection.vpnCountryName = country
                    } else {
                        self.connection.vpnCountryName = nil
                    }
                    self.lastResolvedVPNSignature = vpnSignature
                }
            }

            self.connection.publicIPInterface = self.activePublicIPInterface
            self.connection.lastUpdated = Date()
        }
    }

    private func persistPublicIPCache(networkSignature: String) {
        let defaults = UserDefaults.standard
        if let publicIPv4 = connection.publicIPv4 {
            defaults.set(publicIPv4, forKey: CacheKey.publicIPv4)
        } else {
            defaults.removeObject(forKey: CacheKey.publicIPv4)
        }
        if let publicIPv6 = connection.publicIPv6 {
            defaults.set(publicIPv6, forKey: CacheKey.publicIPv6)
        } else {
            defaults.removeObject(forKey: CacheKey.publicIPv6)
        }
        defaults.set(networkSignature, forKey: CacheKey.networkSignature)
    }

    private func currentPublicIPInterface() -> String? {
        if connection.isVPNActive { return "vpn" }
        if connection.isWiFiActive { return "wifi" }
        if connection.isCellularActive { return "cellular" }
        return nil
    }

    private func updateWeather(for location: CLLocation) async {
        let applePlace: String
        do {
            let placemarks = try await CLGeocoder().reverseGeocodeLocation(location)
            if let placemark = placemarks.first {
                applePlace = displayLocationName(from: placemark)
            } else {
                applePlace = AppLocalization.string("current_location", locale: appLocale)
            }
        } catch {
            applePlace = AppLocalization.string("current_location", locale: appLocale)
        }

        do {
            let values = try await Self.fetchOpenMeteo(for: location)
            weather.locationName = await Self.bestLocationName(for: location, applePlace: applePlace, locale: appLocale)
            weather.temperatureCelsius = values.temperature
            weather.conditionCode = values.code
            weather.precipitationProbability = values.rainProbability
            weather.windSpeedKmh = values.windSpeed
            weather.uvIndex = values.uvIndex
            weather.lastUpdated = Date()
        } catch {
            // Preserve the most recent valid weather value.
        }
    }

    private func updateApproximateWeatherFromNetwork() async {
        do {
            let approximate = try await Self.fetchApproximateNetworkLocation(locale: appLocale)
            let values = try await Self.fetchOpenMeteo(for: approximate.location)
            weather.locationName = (try? await Self.reverseGeocodeWithOSM(
                approximate.location,
                locale: appLocale
            )) ?? approximate.displayName
            weather.temperatureCelsius = values.temperature
            weather.conditionCode = values.code
            weather.precipitationProbability = values.rainProbability
            weather.windSpeedKmh = values.windSpeed
            weather.uvIndex = values.uvIndex
            weather.lastUpdated = Date()
        } catch {
            // Preserve the most recent valid weather value.
        }
    }

    private func displayLocationName(from placemark: CLPlacemark) -> String {
        let commune = [
            placemark.subLocality,
            placemark.locality
        ]
            .compactMap { Self.cleanedVietnameseAdministrativeName($0) }
            .first
        let province = [
            placemark.administrativeArea,
            placemark.locality
        ]
            .compactMap { Self.cleanedVietnameseAdministrativeName($0) }
            .first

        let parts = [commune, province].compactMap { $0 }.removingDuplicates()
        if !parts.isEmpty {
            return parts.joined(separator: ", ")
        }

        return Self.cleanedVietnameseAdministrativeName(placemark.locality)
            ?? Self.cleanedVietnameseAdministrativeName(placemark.subAdministrativeArea)
            ?? Self.cleanedVietnameseAdministrativeName(placemark.administrativeArea)
            ?? placemark.country
            ?? AppLocalization.string("current_location", locale: appLocale)
    }

    private static func cleanedVietnameseAdministrativeName(_ value: String?) -> String? {
        guard var result = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !result.isEmpty else {
            return nil
        }

        let prefixes = [
            "xã", "x.", "xa", "xa.",
            "phường", "p.", "phuong", "phuong.",
            "thị trấn", "tt.", "thi tran",
            "quận", "q.", "quan", "huyện", "h.", "huyen",
            "thị xã", "tx.", "thi xa", "district", "county",
            "ward", "commune", "town",
            "tỉnh", "t.", "tinh", "tp.", "tp",
            "thành phố", "thanh pho", "province of", "city of", "province", "city"
        ]

        var didStrip = true
        while didStrip {
            didStrip = false
            let lowercased = result.lowercased()

            for prefix in prefixes where shouldStripPrefix(prefix, from: lowercased) {
                result.removeFirst(prefix.count)
                result = result.trimmingCharacters(in: .whitespacesAndNewlines)
                didStrip = true
                break
            }
        }

        result = result.replacingOccurrences(
            of: "\\s+(tỉnh|tinh|thành phố|thanh pho|province|city)$",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )

        return result.isEmpty ? nil : result
    }

    private static func shouldStripPrefix(_ prefix: String, from value: String) -> Bool {
        guard value == prefix || value.hasPrefix(prefix) else { return false }
        guard value.count > prefix.count else { return true }

        let nextIndex = value.index(value.startIndex, offsetBy: prefix.count)
        let nextCharacter = value[nextIndex]
        return nextCharacter.isWhitespace || prefix.hasSuffix(".")
    }

    private static func fetchOpenMeteo(for location: CLLocation) async throws -> (
        temperature: Double,
        rainProbability: Int,
        windSpeed: Double?,
        uvIndex: Double?,
        code: Int
    ) {
        guard var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast") else {
            throw URLError(.badURL)
        }

        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(location.coordinate.latitude)),
            URLQueryItem(name: "longitude", value: String(location.coordinate.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code,wind_speed_10m"),
            URLQueryItem(name: "hourly", value: "precipitation_probability,uv_index"),
            URLQueryItem(name: "forecast_hours", value: "1"),
            URLQueryItem(name: "wind_speed_unit", value: "kmh"),
            URLQueryItem(name: "timezone", value: "auto")
        ]

        guard let url = components.url else { throw URLError(.badURL) }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            throw URLError(.badServerResponse)
        }

        let decoded = try JSONDecoder().decode(WeatherResponse.self, from: data)
        return (
            decoded.current.temperature_2m,
            decoded.precipitationProbabilityForCurrentHour ?? 0,
            decoded.current.wind_speed_10m,
            decoded.uvIndexForCurrentHour,
            decoded.current.weather_code
        )
    }

    private static func bestLocationName(for location: CLLocation, applePlace: String, locale: Locale) async -> String {
        do {
            return try await reverseGeocodeWithOSM(location, locale: locale)
        } catch {
            return applePlace
        }
    }

    private static func reverseGeocodeWithOSM(_ location: CLLocation, locale: Locale) async throws -> String {
        guard var components = URLComponents(string: "https://nominatim.openstreetmap.org/reverse") else {
            throw URLError(.badURL)
        }

        components.queryItems = [
            URLQueryItem(name: "format", value: "jsonv2"),
            URLQueryItem(name: "lat", value: String(location.coordinate.latitude)),
            URLQueryItem(name: "lon", value: String(location.coordinate.longitude)),
            URLQueryItem(name: "zoom", value: "18"),
            URLQueryItem(name: "addressdetails", value: "1"),
            URLQueryItem(
                name: "accept-language",
                value: locale.language.languageCode?.identifier == "vi" ? "vi" : "en"
            )
        ]

        guard let url = components.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.setValue("NetFlow/4.1.12 iOS weather-location", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            throw URLError(.badServerResponse)
        }

        let decoded = try JSONDecoder().decode(OSMReverseGeocodeResponse.self, from: data)
        guard let address = decoded.address else { throw URLError(.cannotParseResponse) }

        let province = normalizedProvince(address.province ?? address.state ?? address.region ?? address.city)
        let communeCandidates: [String?] = [
            address.village,
            address.town,
            address.municipality,
            address.suburb,
            address.quarter,
            address.hamlet,
            address.city
        ]
        let commune = normalizedCommune(
            communeCandidates.first { rawValue in
                guard let rawValue = cleanedLocationPart(rawValue) else { return false }
                if let province {
                    return placeKey(rawValue) != placeKey(province)
                }
                return true
            } ?? nil
        )

        let parts = [commune, province].compactMap { $0 }.filter { !$0.isEmpty }
        let uniqueParts = parts.reduce(into: [String]()) { result, part in
            guard !result.contains(where: { placeKey($0) == placeKey(part) }) else { return }
            result.append(part)
        }

        guard !uniqueParts.isEmpty else { throw URLError(.cannotParseResponse) }
        return uniqueParts.joined(separator: ", ")
    }

    private static func fetchApproximateNetworkLocation(locale: Locale) async throws -> (location: CLLocation, displayName: String) {
        let providers: [(String, (Data) throws -> (CLLocation, String))] = [
            ("https://ipwho.is/?fields=success,latitude,longitude,city,region,country", decodeIPWhoIsLocation),
            ("https://ipapi.co/json/", decodeIPAPILocation),
            ("https://ipinfo.io/json", decodeIPInfoLocation),
            ("https://geolocation-db.com/json/", decodeGeolocationDBLocation),
            ("https://api.ip.sb/geoip", decodeIPSBLocation)
        ]

        for provider in providers {
            do {
                guard let url = URL(string: provider.0) else { continue }
                let (data, response) = try await URLSession.shared.data(from: url)
                guard let httpResponse = response as? HTTPURLResponse,
                      200..<300 ~= httpResponse.statusCode else {
                    continue
                }
                let decoded = try provider.1(data)
                return (decoded.0, AppLocalization.string("location_approximate_network", locale: locale))
            } catch {
                continue
            }
        }

        if TimeZone.current.identifier == "Asia/Ho_Chi_Minh" {
            return (
                CLLocation(latitude: 10.7769, longitude: 106.7009),
                AppLocalization.string("location_approximate_vietnam", locale: locale)
            )
        }
        throw URLError(.cannotFindHost)
    }

    private static func decodeIPWhoIsLocation(_ data: Data) throws -> (CLLocation, String) {
        struct Response: Decodable {
            let success: Bool?
            let latitude: Double?
            let longitude: Double?
            let country: String?
        }

        let decoded = try JSONDecoder().decode(Response.self, from: data)
        guard decoded.success != false,
              let latitude = decoded.latitude,
              let longitude = decoded.longitude,
              isVietnamCountryName(decoded.country) else {
            throw URLError(.cannotParseResponse)
        }

        return (CLLocation(latitude: latitude, longitude: longitude), "Approximate network location")
    }

    private static func decodeIPAPILocation(_ data: Data) throws -> (CLLocation, String) {
        struct Response: Decodable {
            let latitude: Double?
            let longitude: Double?
            let country_name: String?
        }

        let decoded = try JSONDecoder().decode(Response.self, from: data)
        guard let latitude = decoded.latitude,
              let longitude = decoded.longitude,
              isVietnamCountryName(decoded.country_name) else {
            throw URLError(.cannotParseResponse)
        }

        return (CLLocation(latitude: latitude, longitude: longitude), "Approximate network location")
    }

    private static func decodeIPInfoLocation(_ data: Data) throws -> (CLLocation, String) {
        struct Response: Decodable {
            let loc: String?
            let country: String?
        }

        let decoded = try JSONDecoder().decode(Response.self, from: data)
        guard let loc = decoded.loc,
              isVietnamCountryName(decoded.country) else {
            throw URLError(.cannotParseResponse)
        }

        let coordinates = loc.split(separator: ",").compactMap { Double($0) }
        guard coordinates.count == 2 else { throw URLError(.cannotParseResponse) }
        return (CLLocation(latitude: coordinates[0], longitude: coordinates[1]), "Approximate network location")
    }

    private static func decodeGeolocationDBLocation(_ data: Data) throws -> (CLLocation, String) {
        struct Response: Decodable {
            let latitude: Double?
            let longitude: Double?
            let country_name: String?
        }

        let decoded = try JSONDecoder().decode(Response.self, from: data)
        guard let latitude = decoded.latitude,
              let longitude = decoded.longitude,
              isVietnamCountryName(decoded.country_name) else {
            throw URLError(.cannotParseResponse)
        }

        return (CLLocation(latitude: latitude, longitude: longitude), "Approximate network location")
    }

    private static func decodeIPSBLocation(_ data: Data) throws -> (CLLocation, String) {
        struct Response: Decodable {
            let latitude: Double?
            let longitude: Double?
            let country: String?
        }

        let decoded = try JSONDecoder().decode(Response.self, from: data)
        guard let latitude = decoded.latitude,
              let longitude = decoded.longitude,
              isVietnamCountryName(decoded.country) else {
            throw URLError(.cannotParseResponse)
        }

        return (CLLocation(latitude: latitude, longitude: longitude), "Approximate network location")
    }

    private static func cleanedLocationPart(_ rawValue: String?) -> String? {
        guard let value = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty,
              value != "-" else {
            return nil
        }

        return value
    }

    private static func isVietnamCountryName(_ rawValue: String?) -> Bool {
        guard let value = cleanedLocationPart(rawValue) else { return false }
        let normalized = value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "vi_VN"))
            .lowercased()

        return ["vn", "vnm", "viet nam", "vietnam"].contains(normalized)
    }

    private static func placeKey(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "vi_VN"))
            .lowercased()
            .replacingOccurrences(
                of: "^(x\\.|xa\\.?|xã|p\\.|phuong\\.?|phường|thị trấn|thi tran|quận|q\\.|quan|huyện|h\\.|huyen|thị xã|tx\\.|thi xa|district|county|ward|commune|town|tỉnh|tinh|t\\.|thành phố|thanh pho|tp\\.?|province|city)\\s*",
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: "\\s+(province|city|tinh|thanh pho)$",
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedCommune(_ rawValue: String?) -> String? {
        cleanedVietnameseAdministrativeName(rawValue)
    }

    private static func normalizedProvince(_ rawValue: String?) -> String? {
        guard var value = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }

        value = value.replacingOccurrences(of: "^Tỉnh\\s+", with: "", options: [.regularExpression, .caseInsensitive])
        value = value.replacingOccurrences(of: "^Tinh\\s+", with: "", options: [.regularExpression, .caseInsensitive])
        value = value.replacingOccurrences(of: "^T\\.\\s*", with: "", options: [.regularExpression, .caseInsensitive])
        value = value.replacingOccurrences(of: "^Thành phố\\s+", with: "", options: [.regularExpression, .caseInsensitive])
        value = value.replacingOccurrences(of: "^Thanh pho\\s+", with: "", options: [.regularExpression, .caseInsensitive])
        value = value.replacingOccurrences(of: "^TP\\.?\\s*", with: "", options: [.regularExpression, .caseInsensitive])
        value = value.replacingOccurrences(of: "^Province\\s+", with: "", options: [.regularExpression, .caseInsensitive])
        value = value.replacingOccurrences(of: "^City of\\s+", with: "", options: [.regularExpression, .caseInsensitive])
        value = value.replacingOccurrences(
            of: "\\s+(Tỉnh|Tinh|Thành phố|Thanh pho|City|Province)$",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )

        let normalizedLower = value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "vi_VN"))
            .lowercased()

        switch normalizedLower {
        case "ho chi minh", "ho chi minh city":
            return "Hồ Chí Minh"
        case "da nang", "da nang city":
            return "Đà Nẵng"
        case "can tho", "can tho city":
            return "Cần Thơ"
        case "hai phong", "hai phong city":
            return "Hải Phòng"
        case "hue", "hue city":
            return "Huế"
        case "ha noi", "hanoi", "hanoi city":
            return "Hà Nội"
        default:
            return value
        }
    }

    private static func fetchPublicIPAddress(endpoint: String) async -> String? {
        guard let url = URL(string: endpoint) else { return nil }

        do {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            configuration.urlCache = nil
            configuration.timeoutIntervalForRequest = 6
            configuration.timeoutIntervalForResource = 8
            let session = URLSession(configuration: configuration)
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
            request.setValue("no-cache", forHTTPHeaderField: "Pragma")
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else { return nil }

            return try JSONDecoder().decode(IPResponse.self, from: data).ip
        } catch {
            return nil
        }
    }

    private static func fetchIPCountryName(for ipAddress: String) async -> String? {
        let providers = [
            "https://ipapi.co/\(ipAddress)/country_name/",
            "https://ipwho.is/\(ipAddress)?fields=success,country",
            "https://api.ip.sb/geoip/\(ipAddress)"
        ]

        for provider in providers {
            if let country = await fetchCountryName(from: provider) {
                return country
            }
        }

        return nil
    }

    private static func fetchCountryName(from urlString: String) async -> String? {
        guard let url = URL(string: urlString) else { return nil }
        do {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            configuration.urlCache = nil
            configuration.timeoutIntervalForRequest = 6
            configuration.timeoutIntervalForResource = 8
            let session = URLSession(configuration: configuration)
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
            request.setValue("no-cache", forHTTPHeaderField: "Pragma")
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return nil
            }

            if let country = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !country.isEmpty,
               !country.hasPrefix("{"),
               !country.lowercased().contains("reserved") {
                return country
            }

            struct CountryResponse: Decodable {
                let success: Bool?
                let country: String?
                let country_name: String?
            }
            let decoded = try? JSONDecoder().decode(CountryResponse.self, from: data)
            guard decoded?.success != false,
                  let country = (decoded?.country_name ?? decoded?.country)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                  !country.isEmpty else {
                return nil
            }
            return country
        } catch {
            return nil
        }
    }

    private static func detectActiveVPNInterface(
        from interfaces: [InterfaceAddress],
        pathUsesOtherInterface: Bool
    ) -> InterfaceAddress? {
        let tunnelPrefixes = ["utun", "tun", "tap", "ipsec", "ppp"]
        let candidates = interfaces.filter { interface in
            interface.isActive &&
                tunnelPrefixes.contains(where: { interface.name.hasPrefix($0) }) &&
                interface.address != "127.0.0.1" &&
                interface.address != "::1" &&
                !interface.address.hasPrefix("fe80:")
        }

        guard !candidates.isEmpty else { return nil }

        // A tunnel is considered connected when it is part of the active scoped
        // network configuration. This avoids treating dormant utun interfaces as VPN.
        if let unmanagedSettings = CFNetworkCopySystemProxySettings() {
            let settings = unmanagedSettings.takeRetainedValue() as NSDictionary
            if let scoped = settings["__SCOPED__"] as? NSDictionary {
                let scopedNames = Set(scoped.allKeys.compactMap { $0 as? String })
                if let scopedTunnel = candidates.first(where: { scopedNames.contains($0.name) }) {
                    return scopedTunnel
                }
            }
        }

        // Some VPN implementations expose the active route as NWInterfaceType.other
        // without adding a scoped proxy entry. Use this only as a conservative fallback.
        return pathUsesOtherInterface ? candidates.first : nil
    }

    private struct InterfaceAddress {
        let name: String
        let family: Int32
        let address: String
        let isActive: Bool
    }

    private static func interfaceAddresses() -> [InterfaceAddress] {
        var interfaceList: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaceList) == 0, let first = interfaceList else {
            return []
        }
        defer { freeifaddrs(first) }

        var result: [InterfaceAddress] = []
        var cursor: UnsafeMutablePointer<ifaddrs>? = first

        while let interface = cursor {
            let item = interface.pointee

            if let socketAddress = item.ifa_addr {
                let family = Int32(socketAddress.pointee.sa_family)
                if family == AF_INET || family == AF_INET6 {
                    var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    let status = getnameinfo(
                        socketAddress,
                        socklen_t(socketAddress.pointee.sa_len),
                        &host,
                        socklen_t(host.count),
                        nil,
                        0,
                        NI_NUMERICHOST
                    )

                    if status == 0 {
                        let flags = Int32(item.ifa_flags)
                        let isLoopback = (flags & Int32(IFF_LOOPBACK)) != 0
                        let isActive = (flags & Int32(IFF_UP)) != 0 && !isLoopback

                        result.append(
                            InterfaceAddress(
                                name: String(cString: item.ifa_name),
                                family: family,
                                address: String(cString: host),
                                isActive: isActive
                            )
                        )
                    }
                }
            }

            cursor = item.ifa_next
        }

        return result
    }
}

extension NetworkContextService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in
            guard self != nil else { return }
            if manager.authorizationStatus == .authorizedAlways ||
                manager.authorizationStatus == .authorizedWhenInUse {
                manager.requestLocation()
            }
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        let validLocations = locations.filter { $0.horizontalAccuracy >= 0 }
        let recentLocations = validLocations.filter {
            let age = Date().timeIntervalSince($0.timestamp)
            return age >= 0 && age <= 120
        }
        let location = (recentLocations.isEmpty ? validLocations : recentLocations)
            .min {
                if $0.horizontalAccuracy == $1.horizontalAccuracy {
                    return $0.timestamp > $1.timestamp
                }
                return $0.horizontalAccuracy < $1.horizontalAccuracy
            } ?? locations.last
        guard let location else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.currentLocation = location
            await self.updateWeather(for: location)
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.weather.locationName = AppLocalization.string("location_unavailable", locale: self.appLocale)
        }
    }
}

private struct IPResponse: Decodable {
    let ip: String
}

private struct WeatherResponse: Decodable {
    struct Current: Decodable {
        let temperature_2m: Double
        let weather_code: Int
        let wind_speed_10m: Double?
        let time: String?
    }

    struct Hourly: Decodable {
        let time: [String]
        let precipitation_probability: [Int?]
        let uv_index: [Double?]?
    }

    let current: Current
    let hourly: Hourly?

    var precipitationProbabilityForCurrentHour: Int? {
        guard let hourly,
              let currentHour = current.time?.prefix(13),
              let index = hourly.time.firstIndex(where: { $0.prefix(13) == currentHour }),
              hourly.precipitation_probability.indices.contains(index) else {
            return hourly?.precipitation_probability.compactMap { $0 }.first
        }

        return hourly.precipitation_probability[index]
    }

    var uvIndexForCurrentHour: Double? {
        guard let hourly,
              let values = hourly.uv_index,
              let currentHour = current.time?.prefix(13),
              let index = hourly.time.firstIndex(where: { $0.prefix(13) == currentHour }),
              values.indices.contains(index) else {
            return hourly?.uv_index?.compactMap { $0 }.first
        }

        return values[index]
    }
}

private struct OSMReverseGeocodeResponse: Decodable {
    struct Address: Decodable {
        let hamlet: String?
        let quarter: String?
        let suburb: String?
        let village: String?
        let town: String?
        let city: String?
        let municipality: String?
        let state: String?
        let province: String?
        let region: String?
    }

    let address: Address?
}

private extension Array where Element: Hashable {
    func removingDuplicates() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
