import SwiftUI
import NavidromeClient
import AppKit

// MARK: - Share types

enum ShareKind: String, CaseIterable, Sendable {
    case song, album, playlist, artist

    var label: String {
        switch self {
        case .song: "Song"
        case .album: "Album"
        case .playlist: "Playlist"
        case .artist: "Artist"
        }
    }
}

struct ShareTarget: Identifiable, Hashable {
    let entityID: String
    let title: String
    let kind: ShareKind

    var id: String { "\(kind.rawValue):\(entityID)" }
}

enum ShareError: LocalizedError {
    case notConfigured
    case sharingDisabled

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "No connection to the Navidrome server.".localized
        case .sharingDisabled:
            return "The server doesn't support link sharing (EnableSharing is off).".localized
        }
    }
}

// MARK: - AppState helpers

extension AppState {
    func presentShare(_ target: ShareTarget) {
        guard confirmOfflineAction() else { return }
        presentInMainWindow { self.shareTarget = target }
    }

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
            throw ShareError.sharingDisabled
        }
    }
}

// MARK: - Share sheet

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

    @State private var showingSharesManager = false

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
        .sheet(isPresented: $showingSharesManager) {
            NavigationStack {
                SharesManagerView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close".localized) {
                                showingSharesManager = false
                            }
                        }
                    }
            }
            .frame(minWidth: 500, minHeight: 400)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "link")
                .font(.title2)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Share".localized).font(.headline)
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
                Picker("Validity period".localized, selection: $expiry) {
                    ForEach(ExpiryChoice.allCases) { choice in
                        Text(choice.label.localized).tag(choice)
                    }
                }
                Toggle("Allow download".localized, isOn: $allowDownload)
                descriptionField
            }
            .formStyle(.grouped)

            if expiry == .custom {
                DatePicker("Expires".localized, selection: $customDate,
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
                Button("Cancel".localized) { dismiss() }
                Button("All Links…".localized) {
                    showingSharesManager = true
                }
                Spacer()
                Button(action: createLink,
                       label: {
                    if isWorking {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Create Link".localized)
                    }
                })
                .disabled(isWorking)
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var descriptionField: some View {
        ZStack(alignment: .topLeading) {
            if descriptionText.isEmpty {
                Text("Description (optional)".localized)
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
                TextField("Link".localized, text: .constant(url))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                HStack(spacing: 12) {
                    Button(action: { copy(url) },
                           label: {
                        Label((copied ? "Copied" : "Copy").localized,
                              systemImage: copied ? "checkmark" : "doc.on.doc")
                    })
                    if let destination = URL(string: url) {
                        Link("Open".localized, destination: destination)
                    }
                    Spacer()
                    Button("Done".localized) { dismiss() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
            } else {
                Text("Failed to get link.".localized).foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    Button("Done".localized) { dismiss() }
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

private enum ExpiryChoice: Identifiable, CaseIterable {
    case oneDay, oneWeek, oneMonth, oneYear, indefinite, custom

    var id: String { "\(self)" }

    var label: String {
        switch self {
        case .oneDay: "1 day"
        case .oneWeek: "1 week"
        case .oneMonth: "1 month"
        case .oneYear: "1 year"
        case .indefinite: "Never"
        case .custom: "Custom date"
        }
    }

    var date: Date? {
        let day: TimeInterval = 86400
        switch self {
        case .oneDay: return Date().addingTimeInterval(day)
        case .oneWeek: return Date().addingTimeInterval(day * 7)
        case .oneMonth: return Date().addingTimeInterval(day * 30)
        case .oneYear: return Date().addingTimeInterval(day * 365)
        case .indefinite: return Date().addingTimeInterval(day * 365 * 100)
        case .custom: return nil
        }
    }
}
