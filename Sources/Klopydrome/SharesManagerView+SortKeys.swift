import Foundation
import NavidromeClient

extension SubsonicShare {
    var sortTitle: String {
        if let description, !description.isEmpty { return description }
        if let title = entry?.first?.title, !title.isEmpty { return title }
        return "Public Link".localized
    }

    var sortCreated: Date {
        created.flatMap(SubsonicDate.parse) ?? .distantPast
    }

    var sortExpires: Date {
        guard let expires, !expires.isEmpty else { return .distantFuture }
        return SubsonicDate.parse(expires) ?? .distantFuture
    }

    var sortVisits: Int { visitCount ?? 0 }
}
