import Foundation

/// Catalogue loaded from Resources/Licenses.json — edit the JSON, not Swift.
enum LicenseData {
    struct Entry: Identifiable, Decodable {
        let id: String
        let title: String
        let subtitle: String
        let urlString: String
        let linkTitle: String
        var url: URL? { URL(string: urlString) }
    }

    static let entries: [Entry] = {
        if let url = Bundle.main.url(forResource: "Licenses", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([Entry].self, from: data) {
            return decoded
        }
        #if SWIFT_PACKAGE
        if let url = Bundle.module.url(forResource: "Licenses", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([Entry].self, from: data) {
            return decoded
        }
        #endif
        return []
    }()
}
