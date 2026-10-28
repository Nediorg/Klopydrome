import AppKit
import NavidromeClient
import SwiftUI

@MainActor
enum EllipsisMenuIcon {
    private static var cache: [Int: NSImage] = [:]

    static func transparentImage(size: CGFloat) -> NSImage {
        let key = Int(size)
        if let cached = cache[key] { return cached }
        let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in true }
        cache[key] = img
        return img
    }
}

struct RoundEllipsisMenu<MenuContent: View>: View {
    @ViewBuilder let content: MenuContent
    var size: CGFloat = 32

    @State private var hovering = false

    var body: some View {
        ZStack {
            Circle()
                .fill(hovering ? AMColor.surfaceTertiaryHover : AMColor.surfaceLight)
                .frame(width: size, height: size)

            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(hovering ? Color.primary : Color.secondary)

            Menu {
                content
            } label: {
                Image(nsImage: EllipsisMenuIcon.transparentImage(size: size))
                    .frame(width: size, height: size)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .offset(x: 2)
            .frame(width: size, height: size)
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .onHover { hovering = $0 }
        .help("More".localized)
        .accessibilityLabel("More".localized)
    }
}
