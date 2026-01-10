import SwiftUI
import WebKit

struct HelpWebView: View {
    var body: some View {
        WebView(url: URL(string: "https://clic.dance/help")!)
            .navigationTitle("Help & FAQ")
            .navigationBarTitleDisplayMode(.inline)
    }
}

struct WebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
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
