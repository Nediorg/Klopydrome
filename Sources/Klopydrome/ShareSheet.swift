import SwiftUI
import NavidromeClient
import AppKit

// MARK: - Share types

/// The kind of library entity being shared. Drives the share label and the
/// entity id sent to Navidrome.
enum ShareKind: String, CaseIterable, Sendable {
    case song, album, playlist, artist

    var label: String {
        switch self {
        case .song: "Песня"
        case .album: "Альбом"
        case .playlist: "Плейлист"
        case .artist: "Исполнитель"
        }
    }
}

/// Identifies the exact entity a share sheet is being opened for. `Identifiable`
/// so it can drive a `.sheet(item:)` presentation on `AppState.shareTarget`.
struct ShareTarget: Identifiable, Hashable {
    let entityID: String
    let title: String
    let kind: ShareKind

    var id: String { "\(kind.rawValue):\(entityID)" }
}

/// Errors specific to share creation, surfaced in the share sheet.
enum ShareError: LocalizedError {
    case notConfigured
    case sharingDisabled

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return NSLocalizedString("Нет подключения к серверу Навидром.", comment: "ShareError")
        case .sharingDisabled:
            return NSLocalizedString(
                "Сервер не поддерживает публикацию ссылок (EnableSharing выключен).",
                comment: "ShareError"
            )
        }
    }
}

// MARK: - AppState helpers

extension AppState {
    /// Opens the share sheet for the given entity. Declared here (rather than in
    /// a context-menu component) because the modal must be presented from the
    /// app root, not from a menu's transient view tree.
    ///
    /// The sheet is attached to `MainView`, so requests from the mini-player
    /// panel are routed through `presentInMainWindow` (panel closes first, the
    /// main window becomes visible again, then the sheet presents into it).
    func presentShare(_ target: ShareTarget) {
        presentInMainWindow { self.shareTarget = target }
    }

    /// Creates a share via Navidrome's native API and returns its public URL.
    /// The native `/api/share` route is used (not the Subsonic `createShare`)
    /// because it is the one that honours the `downloadable` flag.
    func createShareLink(for target: ShareTarget, expires: Date?, downloadable: Bool,
                         description: String? = nil) async throws -> String {
        guard let api = navidrome else { throw ShareError.notConfigured }
        do {
            let share = try await api.createShare(resourceIds: [target.entityID],
                                                  description: description,
                                                  expiresAt: expires,
                                                  downloadable: downloadable)
            return api.baseURL.appendingPathComponent("share").appendingPathComponent(share.id).absoluteString
        } catch let NavidromeAPIError.http(code) where code == 404 {
            // The native `/api/share` route is only registered when the server
            // has `EnableSharing=true`; otherwise it 404s. Surface that clearly.
            throw ShareError.sharingDisabled
        }
    }
}

// MARK: - Share sheet

/// Modal that asks for an expiry and an "allow download" toggle, then calls
/// Navidrome to mint a public share link. Built entirely from native SwiftUI
/// controls (`Picker`, `DatePicker`, `Toggle`, `TextField`, `Button`).
struct ShareSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss

    let target: ShareTarget

    @State private var phase: Phase = .form
    @State private var expiry: ExpiryChoice = .oneMonth
    @State private var customDate = Date().addingTimeInterval(86400 * 30)
    @State private var allowDownload = false
    @State private var descriptionText = ""
    @State private var isWorking = false
    @State private var generatedURL: String?
    @State private var errorMessage: String?
    @State private var copied = false

    private enum Phase { case form, result }

    var body: some View {
        VStack(spacing: 16) {
            header
            if phase == .form {
                formBody
            } else {
                resultBody
            }
        }
        .frame(width: 440)
        .padding(20)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "link")
                .font(.title2)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Поделиться".localized).font(.headline)
                Text("\(target.kind.label.localized): \(target.title)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
        }
    }

    private var formBody: some View {
        VStack(spacing: 12) {
            Form {
                Picker("Срок действия", selection: $expiry) {
                    ForEach(ExpiryChoice.allCases) { choice in
                        Text(choice.label.localized).tag(choice)
                    }
                }
                Toggle("Разрешить загрузку", isOn: $allowDownload)
                descriptionField
            }
            .formStyle(.grouped)

            if expiry == .custom {
                DatePicker("Истекает", selection: $customDate,
                           displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.graphical)
                    .padding(8)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Button("Отмена") { dismiss() }
                Spacer()
                Button(action: createLink,
                       label: {
                    if isWorking {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Создать ссылку".localized)
                    }
                })
                .disabled(isWorking)
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    /// Multi-line description editor rendered as a grouped-Form row, so it
    /// shares the width and surface of the expiry/download rows (same pattern
    /// as the create-playlist modal). Placeholder overlays the editor text.
    private var descriptionField: some View {
        ZStack(alignment: .topLeading) {
            if descriptionText.isEmpty {
                Text("Описание (необязательно)".localized)
                    .foregroundStyle(.tertiary)
                    .padding(8)
                    .allowsHitTesting(false)
            }
            MultilineTextEditor(text: $descriptionText)
                .padding(8)
                .frame(height: 72)
        }
    }

    private var resultBody: some View {
        VStack(spacing: 14) {
            if let url = generatedURL {
                TextField("Ссылка", text: .constant(url))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                HStack(spacing: 12) {
                    Button(action: { copy(url) },
                           label: {
                        Label(copied ? "Скопировано" : "Копировать",
                              systemImage: copied ? "checkmark" : "doc.on.doc")
                    })
                    if let destination = URL(string: url) {
                        Link("Открыть", destination: destination)
                    }
                    Spacer()
                    Button("Готово") { dismiss() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
            } else {
                Text("Не удалось получить ссылку.".localized).foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    Button("Готово") { dismiss() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
    }

    private var effectiveExpiry: Date? {
        expiry == .custom ? customDate : expiry.date
    }

    private func createLink() {
        isWorking = true
        errorMessage = nil
        Task {
            do {
                let url = try await app.createShareLink(for: target,
                                                        expires: effectiveExpiry,
                                                        downloadable: allowDownload,
                                                        description: descriptionText.isEmpty ? nil : descriptionText)
                generatedURL = url
                phase = .result
            } catch {
                errorMessage = describe(error)
            }
            isWorking = false
        }
    }

    private func describe(_ error: Error) -> String {
        if let shareError = error as? ShareError { return shareError.errorDescription ?? "\(shareError)" }
        if let apiError = error as? NavidromeAPIError { return apiError.errorDescription ?? "\(apiError)" }
        return error.localizedDescription
    }

    private func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        copied = true
    }
}

// MARK: - Expiry presets

/// Native picker options for share expiry. `.custom` reveals a `DatePicker`.
private enum ExpiryChoice: Identifiable, CaseIterable {
    case oneDay, oneWeek, oneMonth, oneYear, indefinite, custom

    var id: String { "\(self)" }

    var label: String {
        switch self {
        case .oneDay: "1 день"
        case .oneWeek: "1 неделя"
        case .oneMonth: "1 месяц"
        case .oneYear: "1 год"
        case .indefinite: "Бессрочно"
        case .custom: "Выбрать дату"
        }
    }

    var date: Date? {
        let day: TimeInterval = 86400
        switch self {
        case .oneDay: return Date().addingTimeInterval(day)
        case .oneWeek: return Date().addingTimeInterval(day * 7)
        case .oneMonth: return Date().addingTimeInterval(day * 30)
        case .oneYear: return Date().addingTimeInterval(day * 365)
        // Navidrome has no true "never" — a nil expiry falls back to the server's
        // default (1 year). A far-future date is the honest way to mean "Бессрочно".
        case .indefinite: return Date().addingTimeInterval(day * 365 * 100)
        case .custom: return nil
        }
    }
}
