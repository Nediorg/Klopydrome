import Foundation

/// Looks up a user-visible runtime string in the app's localization table.
/// SwiftUI localizes string literals automatically, but computed `String` values
/// need an explicit lookup before they are passed to `Text`, menus or tooltips.
enum L10n {
    #if SWIFT_PACKAGE
    private static let bundle = Bundle.module
    #else
    private static let bundle = Bundle.main
    #endif

    static func text(_ key: String) -> String {
        NSLocalizedString(key, bundle: bundle, comment: "")
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: .current, arguments: arguments)
    }
}

extension String {
    var localized: String { L10n.text(self) }
}
