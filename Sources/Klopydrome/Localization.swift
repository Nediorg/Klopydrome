import Foundation

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
