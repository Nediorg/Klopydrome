import SwiftUI
import NavidromeClient

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

/// Minimal sign-in screen. Only contains what's needed to connect.
struct LoginView: View {
    @Environment(AppState.self) private var app

    @State private var urlText = ""
    @State private var username = ""
    @State private var password = ""
    @State private var authMode: AuthMode = .token
    @State private var showPassword = false
    @State private var busy = false
    @State private var errorMessage: String?
    @State private var confirmInsecure = false
    @State private var showAdvanced = false
    @FocusState private var focusedField: LoginField?

    private enum LoginField: Hashable {
        case server, username, password
    }

    private var serverAddress: LoginServerAddress {
        LoginServerAddress(url: urlText)
    }

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 10) {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 60, height: 60)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.accentColor.opacity(0.12))
                    )
                    .accessibilityHidden(true)
                Text("Добро пожаловать".localized)
                    .font(.title2.bold())
                Text("Чтобы продолжить, войдите в свой аккаунт".localized)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 12)

            VStack(spacing: 0) {
                joinedRow(icon: "network", title: "Адрес сервера".localized, focus: .server) {
                    TextField("server.example.com:4533", text: $urlText)
                        .disableAutocorrection(true)
                        .textContentType(.URL)
                        .focused($focusedField, equals: .server)
                        .onSubmit { focusedField = .username }
                        .accessibilityLabel("Адрес сервера".localized)
                }

                Divider().padding(.leading, 42)

                joinedRow(icon: "person", title: "Имя пользователя".localized, focus: .username) {
                    TextField("", text: $username)
                        .disableAutocorrection(true)
                        .textContentType(.username)
                        .focused($focusedField, equals: .username)
                        .onSubmit { focusedField = .password }
                        .accessibilityLabel("Имя пользователя".localized)
                }

                Divider().padding(.leading, 42)

                joinedRow(icon: "lock", title: "Пароль".localized, focus: .password) {
                    Group {
                        if showPassword {
                            TextField("", text: $password)
                                .focused($focusedField, equals: .password)
                        } else {
                            SecureField("", text: $password)
                                .focused($focusedField, equals: .password)
                        }
                    }
                    .textContentType(.password)
                    .onSubmit { connect() }
                    .accessibilityLabel("Пароль".localized)
                    .overlay(alignment: .trailing) {
                        Button {
                            showPassword.toggle()
                        } label: {
                            Image(systemName: showPassword ? "eye.slash" : "eye")
                                .foregroundStyle(.secondary)
                                .frame(width: 24, height: 24)
                                .padding(.trailing, 8)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .hoverBrighten()
                        .accessibilityLabel((showPassword ? "Скрыть пароль" : "Показать пароль").localized)
                        .help((showPassword ? "Скрыть пароль" : "Показать пароль").localized)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        focusedField == nil ? Color.primary.opacity(0.12) : Color.accentColor,
                        lineWidth: 1.5
                    )
            }
            .animation(.easeOut(duration: 0.15), value: focusedField)

            if let errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(errorMessage)
                        .font(.callout)
                        .lineLimit(3)
                }
                .foregroundStyle(Color.red)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.red.opacity(0.12))
                )
            }

            Button {
                connect()
            } label: {
                if busy {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Вход…".localized)
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    Text("Войти".localized)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(busy || serverAddress.host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      || username.isEmpty || password.isEmpty)
            .confirmationDialog(
                "Подключиться по незащищённому соединению?",
                isPresented: $confirmInsecure,
                titleVisibility: .visible
            ) {
                Button("Всё равно подключиться", role: .destructive) {
                    connect(allowInsecureHTTP: true)
                }
                Button("Отмена", role: .cancel) {}
            } message: {
                // swiftlint:disable:next line_length
                Text("Пароль и токен передаются в незашифрованном виде. Подключайтесь по http:// только к доверенным серверам (например, в локальной сети).".localized)
            }

            Button {
                withAnimation(Motion.spring(Motion.expand)) { showAdvanced.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(showAdvanced ? 90 : 0))
                    Text("Дополнительно".localized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .hoverBrighten()
            .accessibilityLabel("Дополнительно")
            .accessibilityValue(showAdvanced ? "Развернуто" : "Свернуто")

            if showAdvanced {
                Picker("Аутентификация", selection: $authMode) {
                    Text("Токен (рекомендуется)".localized).tag(AuthMode.token)
                    Text("Пароль (устаревший)".localized).tag(AuthMode.passwordMD5)
                }
                .labelsHidden()
                .pickerStyle(.radioGroup)
                .transition(.opacity)
            }

            Text("Пароль хранится только в связке ключей на этом Mac.".localized)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(width: 320)
        .padding(.horizontal, 28)
        .padding(.vertical, 28)
        .onAppear {
            prefill()
            if serverAddress.host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                focusedField = .server
            } else if username.isEmpty {
                focusedField = .username
            } else {
                focusedField = .password
            }
        }
    }

    /// One row of the joined field group: leading icon + plain field content.
    /// The `.focused` binding lives on the `TextField`/`SecureField` itself
    /// (a wrapper never receives focus); the group ring reads `focusedField`.
    @ViewBuilder
    private func joinedRow<Content: View>(
        icon: String,
        title: String,
        focus: LoginField,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .frame(width: 20)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                content()
                    .textFieldStyle(.plain)
                    .font(.body)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
        .onTapGesture {
            // Tapping the icon/label area focuses the field (plain fields
            // have no chrome of their own to tap).
            if focusedField != focus { focusedField = focus }
        }
    }

    private func prefill() {
        if urlText.isEmpty {
            urlText = app.serverConfig.url
            username = app.serverConfig.username
            authMode = app.serverConfig.authMode
            if !username.isEmpty {
                password = app.passwordForLoginPrefill() ?? ""
            }
        }
    }

    private func connect(allowInsecureHTTP: Bool = false) {
        let address = serverAddress
        if address.host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return }
        if !allowInsecureHTTP && address.scheme == .http {
            confirmInsecure = true
            return
        }
        busy = true
        errorMessage = nil
        Task {
            defer { busy = false }
            do {
                try await app.connect(url: address.url, username: username, password: password,
                                      authMode: authMode, allowInsecureHTTP: allowInsecureHTTP)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}