import Foundation

/// Shared by the app and widgets. Domain values and user-authored text are not translated.
enum L10n {
    static let supportedLanguages = ["pt-BR", "en"]

    /// iOS includes the app-specific language preference in this ordered list.
    static func language(for preferences: [String] = Locale.preferredLanguages) -> String {
        for preference in preferences {
            switch Locale(identifier: preference).language.languageCode?.identifier {
            case "en": return "en"
            case "pt": return "pt-BR"
            default: continue
            }
        }
        return "pt-BR"
    }

    static var locale: Locale { Locale(identifier: language()) }

    static func resourceURL(
        named name: String,
        extension ext: String,
        preferredLanguages: [String] = Locale.preferredLanguages,
        bundle: Bundle = .main
    ) -> URL? {
        let language = language(for: preferredLanguages)
        if let path = bundle.path(forResource: language, ofType: "lproj"),
           let localizedBundle = Bundle(path: path),
           let url = localizedBundle.url(forResource: name, withExtension: ext) {
            return url
        }
        // Portuguese fixtures remain at the bundle root, preserving the original data.
        let url = bundle.bundleURL.appendingPathComponent(name).appendingPathExtension(ext)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static func text(
        _ key: String,
        preferredLanguages: [String] = Locale.preferredLanguages,
        bundle: Bundle = .main
    ) -> String {
        let language = language(for: preferredLanguages)
        guard let path = bundle.path(forResource: language, ofType: "lproj"),
              let localizedBundle = Bundle(path: path) else { return key }
        return localizedBundle.localizedString(forKey: key, value: key, table: "Localizable")
    }

    /// Positional placeholders let translations reorder values without touching user content.
    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        format(key, arguments: arguments)
    }

    static func format(
        _ key: String,
        arguments: [CVarArg],
        preferredLanguages: [String] = Locale.preferredLanguages,
        bundle: Bundle = .main
    ) -> String {
        String(
            format: text(key, preferredLanguages: preferredLanguages, bundle: bundle),
            locale: Locale(identifier: language(for: preferredLanguages)),
            arguments: arguments
        )
    }

    static func date(
        _ date: Date,
        template: String,
        calendar: Calendar = .current,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language(for: preferredLanguages))
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }

    static func decimal(_ value: Double) -> String {
        value.formatted(.number.locale(locale).precision(.fractionLength(1)))
    }
}
