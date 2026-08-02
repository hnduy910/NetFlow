import SwiftUI

enum AppLocalization {
    static func string(_ key: String, locale: Locale = .current) -> String {
        let identifier = locale.identifier.replacingOccurrences(of: "-", with: "_")
        var candidates = [identifier]
        if let language = identifier.split(separator: "_").first {
            candidates.append(String(language))
        }

        for candidate in candidates where !candidate.isEmpty {
            guard let path = Bundle.main.path(forResource: candidate, ofType: "lproj"),
                  let bundle = Bundle(path: path) else {
                continue
            }
            return bundle.localizedString(forKey: key, value: key, table: nil)
        }

        return Bundle.main.localizedString(forKey: key, value: key, table: nil)
    }
}

struct AppSettings: Codable, Hashable {
    var appLanguage: AppLanguage = .system
    var theme: AppTheme = .system
    var refreshSeconds = 2
}

enum AppLanguage: String, Codable, CaseIterable, Identifiable {
    case system, vietnamese, english
    var id: String { rawValue }
    var locale: Locale {
        switch self {
        case .system: return .current
        case .vietnamese: return Locale(identifier: "vi")
        case .english: return Locale(identifier: "en")
        }
    }
}

enum AppTheme: String, Codable, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var colorScheme: ColorScheme? {
        switch self { case .system: return nil; case .light: return .light; case .dark: return .dark }
    }
}
