import SwiftUI
import NavidromeClient

struct ArtistContextMenuItems: View {
    @Environment(AppState.self) private var app
    let artist: Artist

    var body: some View {
        Button((app.isStarred(artist) ? "Unstar" : "Star").localized) {
            app.toggleStar(artist)
        }
        Divider()
        Button("Share…".localized) {
            app.presentShare(ShareTarget(entityID: artist.id, title: artist.name, kind: .artist))
        }
    }
}
