import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case portuguese = "pt-BR"
    case english = "en"

    static let defaultsKey = "settings.language"
    var id: Self { self }

    var titleKey: String {
        switch self {
        case .system: "Seguir sistema"
        case .portuguese: "Português (Brasil)"
        case .english: "English"
        }
    }

    var locale: Locale { self == .system ? .current : Locale(identifier: rawValue) }

    static func resolve(_ identifier: String?) -> Self {
        guard let identifier, identifier != system.rawValue else { return .system }
        switch Locale(identifier: identifier).language.languageCode?.identifier {
        case "en": return .english
        case "pt": return .portuguese
        default: return .system
        }
    }

}

enum AppLocalization {
    static func string(_ key: String.LocalizationValue) -> String {
        var identifier = UserDefaults.standard.string(forKey: AppLanguage.defaultsKey)
        #if DEBUG
        let values = ProcessInfo.processInfo.environment
        if values["TASKS_REGRESSION_TEST_HOST"] == "1", let locale = values["TASKS_REGRESSION_LOCALE"] {
            identifier = locale
        }
        #endif
        let language = AppLanguage.resolve(identifier)
        let bundle: Bundle
        if language != .system,
           let path = Bundle.main.path(forResource: language.rawValue, ofType: "lproj"),
           let localizedBundle = Bundle(path: path) {
            bundle = localizedBundle
        } else {
            bundle = .main
        }
        return String(localized: key, bundle: bundle)
    }
}
