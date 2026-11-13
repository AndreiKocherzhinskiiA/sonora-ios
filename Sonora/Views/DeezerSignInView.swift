import SwiftUI
import WebKit

/// Signs in to Deezer using either an embedded throwaway WebKit browser session or a pasted `arl` cookie.
struct DeezerSignInView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case browser = "Browser"
        case token = "Paste ARL"
        var id: Self { self }
    }

    @Environment(\.dismiss) private var dismiss
    let onSignedIn: (String) -> Void

    @State private var mode: Mode = .browser
    @State private var arlInput = ""
    @State private var isVerifying = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Sign-in method", selection: $mode) {
                    ForEach(Mode.allCases) { entry in
                        Text(entry.rawValue).tag(entry)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, Theme.inset)
                .padding(.vertical, 10)
                Hairline()

                switch mode {
                case .browser:
                    DeezerWebSignIn { arl in
                        onSignedIn(arl)
                        dismiss()
                    }
                case .token:
                    tokenForm
                }
            }
            .background(Theme.background)
            .navigationTitle("Deezer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isVerifying)
                }
            }
        }
    }

    private var tokenForm: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Paste your Deezer `arl` cookie value. Sonora stores it in your device Keychain only.")
                    .font(.small)
                    .foregroundStyle(Theme.mutedForeground)

                VStack(alignment: .leading, spacing: 6) {
                    Text("ARL cookie").font(.small).foregroundStyle(Theme.mutedForeground)
                    SecureField("", text: $arlInput, prompt: Text("192-character hex token").foregroundColor(Theme.mutedForeground))
                        .font(.bodyText)
                        .foregroundStyle(Theme.foreground)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).fill(Theme.secondary)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                        .stroke(Theme.border, lineWidth: Theme.hairline)
                )

                if let errorMessage {
                    Text(errorMessage)
                        .font(.small)
                        .foregroundStyle(Theme.danger)
                }

                Button {
                    submitToken()
                } label: {
                    HStack(spacing: 8) {
                        if isVerifying {
                            ProgressView().tint(Theme.primaryForeground)
                        }
                        Text(isVerifying ? "Verifying…" : "Sign in")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(DeezerSession.parseARL(arlInput) == nil || isVerifying)
            }
            .padding(.horizontal, Theme.inset)
            .padding(.top, 16)
        }
    }

    private func submitToken() {
        guard let parsed = DeezerSession.parseARL(arlInput) else {
            errorMessage = DeezerError.invalidARL.localizedDescription
            return
        }
        errorMessage = nil
        isVerifying = true
        Task {
            defer { isVerifying = false }
            do {
                _ = try await DeezerClient(arl: parsed).library()
                onSignedIn(parsed)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct DeezerWebSignIn: UIViewRepresentable {
    let onARL: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onARL: onARL)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent =
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 " +
            "(KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
        webView.load(URLRequest(url: URL(string: "https://www.deezer.com/login")!))
        context.coordinator.watch(webView.configuration.websiteDataStore.httpCookieStore)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator {
        private let onARL: (String) -> Void
        private var finished = false
        private var task: Task<Void, Never>?

        init(onARL: @escaping (String) -> Void) {
            self.onARL = onARL
        }

        deinit {
            task?.cancel()
        }

        func watch(_ store: WKHTTPCookieStore) {
            task = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(500))
                    let cookies = await store.allCookies()
                    if let arlCookie = cookies.first(where: { cookie in
                        cookie.domain.hasSuffix("deezer.com")
                            && cookie.name == "arl"
                            && DeezerSession.parseARL(cookie.value) != nil
                    }), let parsed = DeezerSession.parseARL(arlCookie.value) {
                        guard let self, !self.finished else { return }
                        self.finished = true
                        self.onARL(parsed)
                        return
                    }
                }
            }
        }
    }
}
