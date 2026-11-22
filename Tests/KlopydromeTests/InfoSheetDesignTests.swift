import AppKit
import SwiftUI
import XCTest
@testable import Klopydrome
import NavidromeClient

final class InfoSheetDesignTests: XCTestCase {

    func testAlbumInfoTabsSingleDiscNoContributors() {
        let detail = AlbumDetail(id: "a1", name: "Simple Album")
        let songs = [
            SubsonicSong(id: "s1", title: "Track 1", discNumber: 1),
            SubsonicSong(id: "s2", title: "Track 2", discNumber: 1)
        ]

        let tabs = AlbumInfoSheet.availableTabs(for: detail, songs: songs)
        XCTAssertEqual(tabs, [.details])
    }

    func testAlbumInfoTabsMultiDiscAndContributors() {
        let detail = AlbumDetail(id: "a2", name: "Deluxe Compilation")
        let songs = [
            SubsonicSong(id: "s1", title: "Track 1", discNumber: 1, displayComposer: "Composer One"),
            SubsonicSong(id: "s2", title: "Track 2", discNumber: 2)
        ]

        let tabs = AlbumInfoSheet.availableTabs(for: detail, songs: songs)
        XCTAssertEqual(tabs, [.details, .discs, .contributors])
    }

    func testAlbumInfoGroupDiscsSortsDiscNumbers() {
        let songs = [
            SubsonicSong(id: "s3", title: "Disc 2 Track 1", discNumber: 2),
            SubsonicSong(id: "s1", title: "Disc 1 Track 1", discNumber: 1),
            SubsonicSong(id: "s2", title: "Disc 1 Track 2", discNumber: 1)
        ]

        let grouped = AlbumInfoSheet.groupDiscs(songs)
        XCTAssertEqual(grouped.count, 2)
        XCTAssertEqual(grouped[0].disc, 1)
        XCTAssertEqual(grouped[0].songs.count, 2)
        XCTAssertEqual(grouped[1].disc, 2)
        XCTAssertEqual(grouped[1].songs.count, 1)
    }

    func testArtistInfoCalculations() {
        let artist = Artist(id: "art1", name: "Artist One")
        let detail = ArtistDetail(id: "art1", name: "Artist One")
        let albums = [
            SubsonicAlbum(id: "alb1", title: "Album 1", artist: "Artist One", songCount: 12, duration: 2400, playCount: 50, year: 1999, genre: "J-Pop"),
            SubsonicAlbum(id: "alb2", title: "Album 2", artist: "Artist One", songCount: 14, duration: 3000, playCount: 75, year: 2003, genre: "Rock")
        ]
        let songs = [
            SubsonicSong(id: "s1", title: "Song 1", genre: "Alternative")
        ]
        let artistInfo = ArtistInfoPayload(
            biography: "<p>Artist biography text.<a href=\"https://example.com/bio\">Read more on Last.fm</a></p>",
            musicBrainzId: "mbz-456",
            lastFmUrl: "https://example.com/music/artist-one"
        )

        let sheet = ArtistInfoSheet(
            artist: artist,
            detail: detail,
            roleLabel: "Main Artist",
            albums: albums,
            allSongs: songs,
            artistInfo: artistInfo
        )

        XCTAssertEqual(sheet.yearsRange, "1999 — 2003")
        XCTAssertEqual(sheet.allGenres, ["Alternative", "J-Pop", "Rock"])
        XCTAssertEqual(sheet.totalDurationSeconds, 5400)
        XCTAssertEqual(sheet.totalSongCount, 26)
        XCTAssertEqual(sheet.totalPlays, 125)

        let cleanedBio = ArtistInfoSheet.cleanBiographyText(
            artistInfo.biography ?? "",
            lastFmUrl: artistInfo.lastFmUrl
        )
        XCTAssertEqual(cleanedBio, "Artist biography text.[Read more on Last.fm](https://example.com/music/artist-one)")
    }

    @MainActor
    func testSelectableHeaderTextFitsTightBoundsAndSafeZones() {
        let font = SelectableHeaderText.font(for: .title2)
        for proposedWidth in [nil, CGFloat.infinity, 0, 400] as [CGFloat?] {
            let size = SelectableHeaderText.measuredContentSize(
                text: "Sample Artist",
                font: font,
                lineLimit: nil,
                proposedWidth: proposedWidth
            )
            XCTAssertGreaterThan(size.width, 30)
            XCTAssertLessThan(size.width, 300)
            XCTAssertGreaterThan(size.height, 10)
            XCTAssertLessThan(size.height, 60)
        }

        let host = NSHostingView(
            rootView: SelectableHeaderText(
                text: "Sample Artist",
                font: font,
                color: .controlAccentColor,
                onClick: {}
            )
        )
        let fitting = host.fittingSize
        XCTAssertGreaterThan(fitting.width, 30)
        XCTAssertLessThan(fitting.width, 300)
        XCTAssertGreaterThan(fitting.height, 10)
        XCTAssertLessThan(fitting.height, 60)
    }
}
