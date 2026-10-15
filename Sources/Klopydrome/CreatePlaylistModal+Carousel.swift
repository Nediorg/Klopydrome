import SwiftUI
import AppKit
import NavidromeClient

// MARK: - Carousel Extension

extension CreatePlaylistModal {
    var coverCarousel: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 12) {
                ZStack {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            ForEach(0..<pageCount, id: \.self) { index in
                                coverTile(index, isActive: index == selectedIndex, proxy: proxy)
                                    .id(index)
                            }
                        }
                        .padding(.horizontal, (modalWidth - coverSize) / 2)
                    }
                    .frame(width: modalWidth, height: coverSize)

                    HStack {
                        CarouselChevronButton(direction: .left) {
                            let newIndex = max(0, selectedIndex - 1)
                            selectCover(newIndex, proxy: proxy)
                        }
                        Spacer()
                        CarouselChevronButton(direction: .right) {
                            let newIndex = min(pageCount - 1, selectedIndex + 1)
                            selectCover(newIndex, proxy: proxy)
                        }
                    }
                    .padding(.horizontal, 10)
                    .opacity(isCarouselHovered ? 1 : 0)
                    .animation(.easeInOut(duration: 0.15), value: isCarouselHovered)
                    .allowsHitTesting(isCarouselHovered)
                }
                .frame(width: modalWidth, height: coverSize)
                .clipped()
                .onHover { isCarouselHovered = $0 }
                .onAppear {
                    proxy.scrollTo(selectedIndex, anchor: .center)
                }

                pageIndicator(proxy: proxy)
            }
        }
    }

    func selectCover(_ index: Int, proxy: ScrollViewProxy) {
        withAnimation(.snappy(duration: 0.25)) {
            selectedCover = index
            proxy.scrollTo(index, anchor: .center)
        }
    }

    func coverTile(_ index: Int, isActive: Bool, proxy: ScrollViewProxy) -> some View {
        let hasNoArtwork = (existing?.coverArt == nil || existing?.coverArt?.isEmpty == true)
        let isSlot0Empty = (index == 0 && customImage == nil && hasNoArtwork)
        let isHovered = (hoveredCoverIndex == index)
        let showPlus = isActive && (isHovered || isSlot0Empty)

        return ZStack {
            AMColor.surface

            swatchContent(swatches[index])
        }
        .frame(width: coverSize, height: coverSize)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isActive ? AMColor.accent : Color.clear, lineWidth: 2)
        }
        .overlay {
            if showPlus {
                coverPlusButton
                    .transition(.opacity)
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                if isHovering {
                    hoveredCoverIndex = index
                } else if hoveredCoverIndex == index {
                    hoveredCoverIndex = nil
                }
            }
        }
        .onTapGesture {
            if !isActive {
                selectCover(index, proxy: proxy)
            }
        }
    }

    private var coverPlusButton: some View {
        Button {
            showCoverSourceMenu()
        } label: {
            Image(systemName: "plus.circle.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(Color.white, AMColor.accent)
                .font(.system(size: 28))
                .frame(width: 28, height: 28)
                .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 1.5)
        }
        .buttonStyle(NoDimButtonStyle())
        .frame(width: 28, height: 28)
    }

    private func showCoverSourceMenu() {
        let target = CoverMenuTarget(
            onFile: { showFilePicker = true },
            onPhotos: { showPhotosPicker = true }
        )
        let menu = NSMenu()

        let fileItem = NSMenuItem(
            title: "Выбрать файл…".localized,
            action: #selector(CoverMenuTarget.chooseFile),
            keyEquivalent: ""
        )
        fileItem.target = target
        fileItem.image = NSImage(systemSymbolName: "macwindow", accessibilityDescription: nil)
        menu.addItem(fileItem)

        let photosItem = NSMenuItem(
            title: "Выбрать из медиатеки Фото…".localized,
            action: #selector(CoverMenuTarget.choosePhotos),
            keyEquivalent: ""
        )
        photosItem.target = target
        photosItem.image = NSImage(systemSymbolName: "photo.on.rectangle", accessibilityDescription: nil)
        menu.addItem(photosItem)

        guard let window = NSApp.keyWindow,
              let view = window.contentView else { return }
        let mouseLocation = NSEvent.mouseLocation
        let locationInWindow = window.convertPoint(fromScreen: mouseLocation)
        let event = NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: locationInWindow,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        ) ?? NSApp.currentEvent
        guard let event else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }

    @ViewBuilder
    func swatchContent(_ swatch: Swatch) -> some View {
        let size = coverSize
        switch swatch {
        case .photo(let existingArt):
            if let customImage {
                Image(nsImage: customImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipped()
                    .transition(.opacity)
            } else if let existingArt, !existingArt.isEmpty {
                CoverArtView(coverArt: existingArt, size: size, cornerRadius: 12)
                    .transition(.opacity)
            } else {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.08))
                    .transition(.opacity)
            }
        case .preset(let preset):
            preset.view(size: size, title: name)
        }
    }

    func pageIndicator(proxy: ScrollViewProxy) -> some View {
        HStack(spacing: 6) {
            Button {
                selectCover(0, proxy: proxy)
            } label: {
                Image(systemName: "photo")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(selectedIndex == 0 ? Color.white : Color.secondary.opacity(0.45))
            }
            .buttonStyle(.plain)

            ForEach(1..<pageCount, id: \.self) { index in
                Button {
                    selectCover(index, proxy: proxy)
                } label: {
                    Circle()
                        .fill(index == selectedIndex ? Color.white : Color.secondary.opacity(0.35))
                        .frame(width: 6, height: 6)
                }
                .buttonStyle(.plain)
            }
        }
        .animation(.snappy(duration: 0.2), value: selectedIndex)
    }
}

// MARK: - Custom Chevron Shape & Button

/// Custom tall chevron shape matching Apple Music macOS carousel arrows.
struct TallChevronShape: Shape {
    var direction: Direction

    enum Direction {
        case left, right
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        switch direction {
        case .right:
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        case .left:
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        }
        return path
    }
}

/// Translucent rounded-rectangle chevron button matching Apple Music macOS hover arrows.
struct CarouselChevronButton: View {
    let direction: TallChevronShape.Direction
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(white: 0.35).opacity(isHovering ? 0.85 : 0.6))
                    .frame(width: 36, height: 92)

                TallChevronShape(direction: direction)
                    .stroke(
                        Color.white.opacity(isHovering ? 1.0 : 0.85),
                        style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round)
                    )
                    .frame(width: 13, height: 44)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

private final class CoverMenuTarget: NSObject {
    let onFile: () -> Void
    let onPhotos: () -> Void

    init(onFile: @escaping () -> Void, onPhotos: @escaping () -> Void) {
        self.onFile = onFile
        self.onPhotos = onPhotos
    }

    @objc func chooseFile() {
        onFile()
    }

    @objc func choosePhotos() {
        onPhotos()
    }
}

private struct NoDimButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}
