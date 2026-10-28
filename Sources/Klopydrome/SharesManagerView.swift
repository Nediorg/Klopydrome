import SwiftUI
import NavidromeClient
import AppKit

struct SharesManagerView: View {
    @Environment(AppState.self) private var app
    @State private var shares: [SubsonicShare] = []
    @State private var loading = true
    @State private var loadError: String?
    @State private var sharePendingRevocation: SubsonicShare?
    @State private var copiedShareID: String?
    @State private var sortOrder = [KeyPathComparator(\SubsonicShare.sortCreated, order: .reverse)]

    private static let compactDate = Date.FormatStyle()
        .day(.twoDigits).month(.twoDigits).year()
        .hour(.twoDigits(amPM: .abbreviated)).minute(.twoDigits)

    var body: some View {
        Group {
            if let loadError {
                LibraryUnavailableView(
                    title: "Failed to load links".localized,
                    systemImage: "wifi.exclamationmark",
                    message: loadError,
                    retry: { Task { await load() } }
                )
            } else if loading && shares.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if shares.isEmpty {
                ContentUnavailableView(
                    "No Active Links".localized,
                    systemImage: "link",
                    description: Text("Public links you create will appear here.".localized)
                )
            } else {
                sharesTable
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            await load()
        }
        .onChange(of: app.isConnected) { _, isConnected in
            if isConnected {
                Task { await load() }
            }
        }
        .confirmationDialog(
            "Revoke link?".localized,
            isPresented: Binding(
                get: { sharePendingRevocation != nil },
                set: { if !$0 { sharePendingRevocation = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Revoke".localized, role: .destructive) {
                if let share = sharePendingRevocation {
                    revoke(share)
                }
                sharePendingRevocation = nil
            }
            Button("Cancel".localized, role: .cancel) {
                sharePendingRevocation = nil
            }
        } message: {
            Text("The link will stop working for all users.".localized)
        }
    }

    private var sharesTable: some View {
        Table(shares.sorted(using: sortOrder), sortOrder: $sortOrder) {
            TableColumn("Title".localized, value: \.sortTitle) { share in
                Text(share.sortTitle).lineLimit(1)
            }
            TableColumn("Created".localized, value: \.sortCreated) { share in
                Text(share.sortCreated, format: Self.compactDate)
                    .foregroundStyle(.secondary)
            }
            .width(min: 110, ideal: 130)
            TableColumn("Expires".localized, value: \.sortExpires) { share in
                if share.sortExpires == .distantFuture {
                    Text("—").foregroundStyle(.secondary)
                } else {
                    Text(share.sortExpires, format: Self.compactDate)
                        .foregroundStyle(.secondary)
                }
            }
            .width(min: 110, ideal: 130)
            TableColumn("Views".localized, value: \.sortVisits) { share in
                Text("\(share.sortVisits)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .width(70)
            TableColumn("") { share in
                HStack(spacing: 8) {
                    Button {
                        copyLink(share)
                    } label: {
                        Image(systemName: copiedShareID == share.id ? "checkmark" : "doc.on.doc")
                    }
                    .help("Copy Link".localized)

                    Button(role: .destructive) {
                        sharePendingRevocation = share
                    } label: {
                        Image(systemName: "trash")
                    }
                    .help("Revoke Link".localized)
                }
                .buttonStyle(.borderless)
            }
            .width(52)
        }
    }

    private func copyLink(_ share: SubsonicShare) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(share.url, forType: .string)
        copiedShareID = share.id
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if copiedShareID == share.id {
                copiedShareID = nil
            }
        }
    }

    private func load() async {
        guard !Task.isCancelled else { return }
        guard let client = app.client, !app.isOfflineSession else {
            loading = false
            return
        }
        loading = true
        loadError = nil
        defer {
            if !Task.isCancelled {
                loading = false
            }
        }
        do {
            let fetched = try await client.getShares()
            guard !Task.isCancelled else { return }
            shares = fetched
            loadError = nil
        } catch {
            if error is CancellationError || Task.isCancelled { return }
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled { return }
            loadError = error.localizedDescription
        }
    }

    private func revoke(_ share: SubsonicShare) {
        guard let client = app.client else { return }
        Task {
            do {
                try await client.deleteShare(id: share.id)
                shares.removeAll { $0.id == share.id }
            } catch {
                if error is CancellationError || Task.isCancelled { return }
                let nsError = error as NSError
                if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled { return }
                loadError = error.localizedDescription
            }
        }
    }
}
