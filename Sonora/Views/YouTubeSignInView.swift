import SwiftUI
import WebKit

/// Google's sign-in page in a throwaway browser session. Once the proof cookies appear on the
/// YouTube Music page, their header is handed back and the sheet closes. Nothing is kept in the
/// web view's own storage, so no browser profile rotates the cookies behind the app's back.
struct YouTubeSignInView: View {
    @Environment(\.dismiss) private var dismiss
    let onSignedIn: (String) -> Void

    var body: some View {
        NavigationStack {
            SignInWebView { header in
                onSignedIn(header)
                dismiss()
            }
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle("YouTube Music")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

private struct SignInWebView: UIViewRepresentable {
    let onHeader: (String) -> Void

    private static let signInURL = URL(string: "https://accounts.google.com/ServiceLogin?ltmpl=music&service=youtube&passive=true&continue=https%3A%2F%2Fwww.youtube.com%2Fsignin%3Faction_handle_signin%3Dtrue%26next%3Dhttps%253A%252F%252Fmusic.youtube.com%252F")!

    func makeCoordinator() -> Coordinator { Coordinator(onHeader: onHeader) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: configuration)
        // Google refuses sign-in from an embedded web view, so the page is told it is Safari.
        view.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
        view.navigationDelegate = context.coordinator
        context.coordinator.view = view
        context.coordinator.startPolling()
        view.load(URLRequest(url: Self.signInURL))
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {}

    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        coordinator.stopPolling()
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let onHeader: (String) -> Void
        weak var view: WKWebView?
        private var poll: Task<Void, Never>?
        private var delivered = false

        init(onHeader: @escaping (String) -> Void) {
            self.onHeader = onHeader
        }

        func startPolling() {
            poll = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    await self?.check()
                }
            }
        }

        func stopPolling() {
            poll?.cancel()
        }

        /// Hands back the header once the page is on YouTube Music and the cookies prove an account.
        @MainActor
        private func check() async {
            guard !delivered, let view, view.url?.host?.hasSuffix("music.youtube.com") == true else { return }
            let cookies = await view.configuration.websiteDataStore.httpCookieStore.allCookies()
                .filter { $0.domain.hasSuffix("youtube.com") }
            guard cookies.contains(where: { YouTubeSession.proof.contains($0.name) }) else { return }
            delivered = true
            onHeader(cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; "))
        }
    }
}

private extension WKHTTPCookieStore {
    func allCookies() async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            getAllCookies { continuation.resume(returning: $0) }
        }
    }
}
