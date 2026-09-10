import SwiftUI
import NavidromeClient

/// Apple-Music-style context menu for an artist. Single source of truth for
/// artist actions — currently the artist list row. The «…» surfaces (e.g. the
/// artist detail toolbar) should build from this component too so the offered
/// actions never drift apart.
struct ArtistContextMenuItems: View {
    @Environment(AppState.self) private var app
    let artist: Artist

    var body: some View {
        Button(app.isStarred(artist) ? "Убрать из избранного" : "В избранное") {
            app.toggleStar(artist)
        }
        Divider()
        Button("Поделиться…") {
            app.presentShare(ShareTarget(entityID: artist.id, title: artist.name, kind: .artist))
        }
    }
}
