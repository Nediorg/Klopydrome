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
        if visible {
            showLyrics = tab == .lyrics
            if !queuePanelVisible {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                    queuePanelVisible = true
                }
            }
        } else if visiblePlayerPanel == tab {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                queuePanelVisible = false
            }
        }
    }

    func togglePlayerPanel(_ tab: PlayerPanelTab) {
        setPlayerPanel(tab, visible: visiblePlayerPanel != tab)
    }
}
