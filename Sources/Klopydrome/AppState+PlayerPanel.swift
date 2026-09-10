import SwiftUI

extension AppState {
    enum PlayerPanelTab: Equatable {
        case lyrics
        case queue

        var title: String {
            switch self {
            case .lyrics: "Текст"
            case .queue: "Очередь"
            }
        }
    }

    var visiblePlayerPanel: PlayerPanelTab? {
        guard queuePanelVisible else { return nil }
        return showLyrics ? .lyrics : .queue
    }

    func setPlayerPanel(_ tab: PlayerPanelTab, visible: Bool) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            if visible {
                showLyrics = tab == .lyrics
                queuePanelVisible = true
            } else if visiblePlayerPanel == tab {
                queuePanelVisible = false
            }
        }
    }

    func togglePlayerPanel(_ tab: PlayerPanelTab) {
        setPlayerPanel(tab, visible: visiblePlayerPanel != tab)
    }
}
