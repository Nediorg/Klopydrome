import AppKit
import NavidromeClient
import SwiftUI

struct ServerDraft: Equatable {
    var name: String = ""
    var urlString: String = ""
    var username: String = ""
    var password: String = ""
    var allowSelfSignedCert: Bool = false

    var normalizedURL: URL? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let withScheme = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: withScheme),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil else {
            return nil
        }
        return url
    }

    var isValid: Bool {
        normalizedURL != nil &&
        !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !password.isEmpty
    }
}

enum LoginServerScheme: String, CaseIterable, Identifiable {
    case https
    case http

    var id: String { rawValue }
    var prefix: String { "\(rawValue)://" }
}

struct LoginServerAddress: Equatable {
    var scheme: LoginServerScheme
    var host: String

    init(scheme: LoginServerScheme = .https, host: String) {
        self.scheme = scheme
        self.host = host
    }

    init(url: String) {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = trimmed.lowercased()
        if lowercased.hasPrefix(LoginServerScheme.http.prefix) {
            scheme = .http
            host = String(trimmed.dropFirst(LoginServerScheme.http.prefix.count))
        } else if lowercased.hasPrefix(LoginServerScheme.https.prefix) {
            scheme = .https
            host = String(trimmed.dropFirst(LoginServerScheme.https.prefix.count))
        } else {
            scheme = .https
            host = trimmed
        }
    }

    var url: String {
        scheme.prefix + host.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct ServerConnectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var app

    @State var draft = ServerDraft()
    @State private var showAdvanced = false
    @State private var isConnecting = false
    @State private var errorMessage: String?

    var onConnect: ((ServerDraft) async throws -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Name".localized, text: $draft.name, prompt: Text("Optional".localized))
                    TextField("Address".localized, text: $draft.urlString, prompt: Text("https://music.example.com:4533"))
                        .textContentType(.URL)
                }

                Section {
                    TextField("Username".localized, text: $draft.username)
                        .textContentType(.username)
                    SecureField("Password".localized, text: $draft.password)
                        .textContentType(.password)
                } footer: {
                    Text("Password is stored in macOS Keychain.".localized)
                }

                Section {
                    DisclosureGroup("Advanced".localized, isExpanded: $showAdvanced) {
                        Toggle("Allow self-signed certificates".localized, isOn: $draft.allowSelfSignedCert)
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.callout)
                    }
                }
            }
            .formStyle(.grouped)
            .disabled(isConnecting)

            Divider()

            HStack(spacing: 10) {
                if isConnecting {
                    ProgressView()
                        .controlSize(.small)
                }

                Spacer()

                Button("Cancel".localized) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Connect".localized) {
                    submit()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!draft.isValid || isConnecting)
            }
            .padding()
        }
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func submit() {
        guard let url = draft.normalizedURL else { return }

        errorMessage = nil
        isConnecting = true

        let trimmedName = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = trimmedName.isEmpty ? (url.host ?? "Server".localized) : trimmedName
        let cleanUsername = draft.username.trimmingCharacters(in: .whitespacesAndNewlines)

        Task {
            do {
                if let onConnect {
                    try await onConnect(draft)
                } else {
                    try await app.connect(
                        url: url.absoluteString,
                        username: cleanUsername,
                        password: draft.password,
                        authMode: .token,
                        allowInsecureHTTP: draft.allowSelfSignedCert,
                        profileName: resolvedName
                    )
                }
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isConnecting = false
            }
        }
    }
}
