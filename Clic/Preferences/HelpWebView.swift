import SwiftUI
import WebKit

struct HelpWebView: View {
    var body: some View {
        WebView(url: URL(string: "https://clic.dance/help")!)
            // Extend the page behind the home indicator so the site's own
            // footer renders at full height. WKWebView still needs
            // `contentInsetAdjustmentBehavior = .never` (below) — SwiftUI's
            // `ignoresSafeArea` alone leaves a black band because the
            // internal UIScrollView keeps adding its own bottom inset.
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle("Help & FAQ")
            .navigationBarTitleDisplayMode(.inline)
    }
}

struct WebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        // Stop WKWebView's internal scroll view from inserting bottom safe
        // area padding — otherwise the SwiftUI `ignoresSafeArea` and the
        // scroll view's inset both contribute and we still see a black
        // band where the home indicator sits.
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

#Preview {
    NavigationStack {
        HelpWebView()
    }
}
