import AppKit
import NavidromeClient
import SwiftUI

// MARK: - Background view that suppresses the window toolbar's "Icon and Text"
// menu and shows the NowPlaying menu on right-click. Used as a background
// of the principal toolbar item so the hit is on this view, not on the
// underlying NSToolbarView.

struct ToolbarLCDRightClickBackground: NSViewRepresentable {
    let song: SubsonicSong?
    var path: Binding<NavigationPath>
    @Environment(AppState.self) private var app

    func makeNSView(context: Context) -> NSView {
        let view = BackgroundView()
        view.app = app
        view.song = song
        view.path = path
        view.updateMenu()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? BackgroundView else { return }
        view.app = app
        view.song = song
        view.path = path
        view.updateMenu()
    }

    final class BackgroundView: NSView {
        var app: AppState?
        var song: SubsonicSong?
        var path: Binding<NavigationPath>?

        func updateMenu() {
            guard let song, let app else {
                menu = nil
                return
            }
            let helper = Helper(app: app, song: song, path: path)
            let menu = buildMenu(for: song, helper: helper)
            objc_setAssociatedObject(
                menu,
                &AssociatedKeys.helper,
                helper,
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
            self.menu = menu
        }

        private func buildMenu(for song: SubsonicSong, helper: Helper) -> NSMenu {
            let menu = NSMenu()
            let station = NSMenuItem(
                title: "Создать станцию",
                action: #selector(Helper.createStation),
                keyEquivalent: ""
            )
            station.target = helper
            station.image = NSImage(
                systemSymbolName: "dot.radiowaves.left.and.right",
                accessibilityDescription: nil
            )
            menu.addItem(station)

            let details = NSMenuItem(
                title: "Сведения",
                action: #selector(Helper.showDetails),
                keyEquivalent: ""
            )
            details.target = helper
            details.image = NSImage(
                systemSymbolName: "info.circle",
                accessibilityDescription: nil
            )
            menu.addItem(details)

            if song.albumId != nil {
                let album = NSMenuItem(
                    title: "Показать альбом в медиатеке",
                    action: #selector(Helper.showAlbum),
                    keyEquivalent: ""
                )
                album.target = helper
                album.image = NSImage(
                    systemSymbolName: "square.stack",
                    accessibilityDescription: nil
                )
                menu.addItem(album)
            }
            menu.addItem(.separator())
            let copy = NSMenuItem(
                title: "Скопировать",
                action: #selector(Helper.copyTitle),
                keyEquivalent: ""
            )
            copy.target = helper
            copy.image = NSImage(
                systemSymbolName: "doc.on.doc",
                accessibilityDescription: nil
            )
            menu.addItem(copy)
            return menu
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            // Only handle right-click so left-click falls through to the
            // underlying PlayerLCDView's GoTo onTapGesture.
            guard let event = NSApp.currentEvent, event.type == .rightMouseDown else {
                return nil
            }
            return super.hitTest(point)
        }

        override func rightMouseDown(with event: NSEvent) {
            if let menu {
                NSMenu.popUpContextMenu(menu, with: event, for: self)
            } else {
                super.rightMouseDown(with: event)
            }
        }

        override func menu(for event: NSEvent) -> NSMenu? { menu }
    }

    private enum AssociatedKeys { static var helper = 0 }
}

@MainActor
private final class Helper: NSObject {
    let app: AppState
    let song: SubsonicSong
    var path: Binding<NavigationPath>?

    init(app: AppState, song: SubsonicSong, path: Binding<NavigationPath>?) {
        self.app = app
        self.song = song
        self.path = path
    }

    @objc func createStation() { app.playStation(from: song) }

    @objc func showDetails() {
        if let binding = path {
            var value = binding.wrappedValue
            value.append(song)
            binding.wrappedValue = value
        } else {
            app.openSongDetails(song)
        }
    }

    @objc func showAlbum() {
        guard let identifier = song.albumId else { return }
        let album = SubsonicAlbum.nowPlayingSummary(
            from: song,
            albumID: identifier
        )
        app.openAlbumInLibrary(album)
    }

    @objc func copyTitle() {
        let parts = [song.displayTitle, song.artist, song.album].compactMap { $0 }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(
            parts.joined(separator: " — "),
            forType: .string
        )
    }
}
