import Foundation
import NavidromeClient

/// Non-optional, `Comparable` projections of `SubsonicShare` for table sorting.
extension SubsonicShare {
    var sortTitle: String {
        if let description, !description.isEmpty { return description }
        if let title = entry?.first?.title, !title.isEmpty { return title }
        return "Публичная ссылка".localized
    }

    var sortCreated: Date {
        created.flatMap(SubsonicDate.parse) ?? .distantPast
    }

    /// Shares without an expiry sort as the furthest-future date.
    var sortExpires: Date {
        guard let expires, !expires.isEmpty else { return .distantFuture }
        return SubsonicDate.parse(expires) ?? .distantFuture
    }

    var sortVisits: Int { visitCount ?? 0 }
}
