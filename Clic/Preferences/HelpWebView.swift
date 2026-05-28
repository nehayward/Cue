import SwiftUI
import WebKit

struct HelpWebView: View {
    @State private var isLoading = true

    // Hide the site's own fixed header (`<header class="header">`) so the
    // iOS nav bar is the only chrome — otherwise the page shows the
    // "Clic" logo + hamburger above the FAQ content, duplicating the
    // app's navigation. The header is `position: fixed`, so removing it
    // doesn't shift any layout. Body top-padding uses
    // `env(safe-area-inset-top)` so content stays below the (now
    // translucent) iOS nav bar — works because the site already sets
    // `viewport-fit=cover`.
    static let injectedCSS = """
    header.header { display: none !important; }
    body { padding-top: env(safe-area-inset-top) !important; }
    main > section.text-center { display: none !important; }
    main { padding-top: 1rem !important; }
    """

    var body: some View {
        ZStack {
            // Backstop color shown while the page is loading. Matches the
            // surrounding nav chrome so the moment between "view appears"
            // and "HTML paints" doesn't flash WKWebView's default white.
            Color(.systemBackground)
                .ignoresSafeArea()

            WebView(
                url: URL(string: "https://clic.dance/help")!,
                injectedCSS: HelpWebView.injectedCSS,
                isLoading: $isLoading
            )
                // Extend the page edge-to-edge so the dark page background
                // bleeds under the iOS nav bar and home indicator. WKWebView
                // still needs `contentInsetAdjustmentBehavior = .never`
                // (below) — SwiftUI's `ignoresSafeArea` alone leaves a black
                // band because the internal UIScrollView keeps adding its
                // own bottom inset. Body top-padding is handled CSS-side
                // via `env(safe-area-inset-top)` (see the injected user
                // script) so content stays below the nav bar.
                .ignoresSafeArea()
                .opacity(isLoading ? 0 : 1)

            if isLoading {
                ProgressView()
                    .controlSize(.large)
            }
        }
        .navigationTitle("Help & FAQ")
        .navigationBarTitleDisplayMode(.inline)
        // Thin material so the page bleeds through the nav while the title
        // and back-chevron stay legible against the frosted backdrop —
        // mirrors the site's own blurred header (which we hide).
        .toolbarBackground(.thinMaterial, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

struct WebView: UIViewRepresentable {
    let url: URL
    let injectedCSS: String
    @Binding var isLoading: Bool

    func makeUIView(context: Context) -> WKWebView {
        let hideHeader = WKUserScript(
            source: """
            var s = document.createElement('style');
            s.innerHTML = `\(injectedCSS)`;
            document.head.appendChild(s);
            """,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        let config = WKWebViewConfiguration()
        config.userContentController.addUserScript(hideHeader)
        // Without this, iOS fullscreens <video> on play even with the
        // `playsinline` attribute set — WKWebView ignores playsinline
        // unless inline playback is explicitly allowed.
        config.allowsInlineMediaPlayback = true

        let webView = WKWebView(frame: .zero, configuration: config)
        // Transparent so the ZStack's backstop color shows through during
        // load — otherwise WKWebView's default opaque-white background
        // flashes between view-appear and first HTML paint.
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        // Stop WKWebView's internal scroll view from inserting bottom safe
        // area padding — otherwise the SwiftUI `ignoresSafeArea` and the
        // scroll view's inset both contribute and we still see a black
        // band where the home indicator sits.
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.navigationDelegate = context.coordinator
        // `returnCacheDataElseLoad` shows cached content instantly on repeat
        // opens (no revalidation round-trip) and falls back to network on
        // first visit. If the team needs the FAQ to update mid-session,
        // switch to `.useProtocolCachePolicy` and serve proper Cache-Control
        // headers from clic.dance.
        webView.load(URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 10))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(isLoading: $isLoading)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        @Binding var isLoading: Bool

        init(isLoading: Binding<Bool>) {
            self._isLoading = isLoading
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isLoading = false
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            isLoading = false
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            isLoading = false
        }
    }
}

#Preview {
    NavigationStack {
        HelpWebView()
    }
}
