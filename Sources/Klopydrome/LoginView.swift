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
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 56, height: 56)
                    .background(
                        Circle()
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

            // Input fields
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Адрес сервера".localized)
                        .font(.subheadline.weight(.medium))

                    TextField("https://music.example.com:4533", text: $urlText)
                        .textFieldStyle(.plain)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.horizontal, 8)
                        .loginFieldChrome(isFocused: focusedField == .server) {
                            focusedField = .server
                        }
                        .disableAutocorrection(true)
                        .textContentType(.URL)
                        .focused($focusedField, equals: .server)
                        .onSubmit { focusedField = .username }
                        .accessibilityLabel("Адрес сервера".localized)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Имя пользователя".localized)
                        .font(.subheadline.weight(.medium))

                    TextField("Имя пользователя".localized, text: $username)
                        .textFieldStyle(.plain)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.horizontal, 8)
                        .loginFieldChrome(isFocused: focusedField == .username) {
                            focusedField = .username
                        }
                        .disableAutocorrection(true)
                        .textContentType(.username)
                        .focused($focusedField, equals: .username)
                        .onSubmit { focusedField = .password }
                        .accessibilityLabel("Имя пользователя".localized)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Пароль".localized)
                        .font(.subheadline.weight(.medium))

                    HStack(spacing: 6) {
                        Group {
                            if showPassword {
                                TextField("Пароль".localized, text: $password)
                                    .focused($focusedField, equals: .password)
                            } else {
                                SecureField("Пароль".localized, text: $password)
                                    .focused($focusedField, equals: .password)
                            }
                        }
                        .textFieldStyle(.plain)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                        .textContentType(.password)
                        .onSubmit { connect() }
                        .accessibilityLabel("Пароль".localized)

                        Button {
                            showPassword.toggle()
                        } label: {
                            Image(systemName: showPassword ? "eye.slash" : "eye")
                                .font(.system(size: 13, weight: .regular))
                                .foregroundStyle(.secondary)
                                .frame(width: 20, height: 20)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .hoverBrighten()
                        .accessibilityLabel((showPassword ? "Скрыть пароль" : "Показать пароль").localized)
                        .help((showPassword ? "Скрыть пароль" : "Показать пароль").localized)
                    }
                    .padding(.leading, 8)
                    .padding(.trailing, 6)
                    .loginFieldChrome(isFocused: focusedField == .password) {
                        focusedField = .password
                    }
                }
            }
            .padding(.vertical, 4)

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
            .keyboardShortcut(.defaultAction)
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
            .accessibilityLabel("Дополнительно".localized)
            .accessibilityValue((showAdvanced ? "Развернуто" : "Свернуто").localized)

            if showAdvanced {
                Picker("Аутентификация".localized, selection: $authMode) {
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
        .padding(.horizontal, 32)
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity)
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

// MARK: - Login Field Styling

private struct LoginFieldChrome: ViewModifier {
    let isFocused: Bool
    let onActivate: () -> Void

    func body(content: Content) -> some View {
        content
            .frame(height: 30)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor))
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.accentColor.opacity(isFocused ? 0.10 : 0))
                IBeamCursorArea(onMouseDown: onActivate)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(
                        isFocused ? Color.accentColor : Color(nsColor: .separatorColor),
                        lineWidth: isFocused ? 2 : 1
                    )
                    .allowsHitTesting(false)
            }
            .animation(.easeInOut(duration: 0.15), value: isFocused)
    }
}

private extension View {
    func loginFieldChrome(isFocused: Bool, onActivate: @escaping () -> Void) -> some View {
        modifier(LoginFieldChrome(isFocused: isFocused, onActivate: onActivate))
    }
}

private struct IBeamCursorArea: NSViewRepresentable {
    let onMouseDown: () -> Void

    func makeNSView(context: Context) -> IBeamCursorView {
        let view = IBeamCursorView()
        view.onMouseDown = onMouseDown
        return view
    }

    func updateNSView(_ nsView: IBeamCursorView, context: Context) {
        nsView.onMouseDown = onMouseDown
    }
}

private final class IBeamCursorView: NSView {
    var onMouseDown: (() -> Void)?

    override func resetCursorRects() {
        discardCursorRects()
        addCursorRect(bounds, cursor: .iBeam)
    }

    override func mouseDown(with event: NSEvent) {
        onMouseDown?()
    }
}