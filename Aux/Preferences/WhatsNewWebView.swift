import Defaults
import SwiftUI
import WebKit

struct WhatsNewWebView: View {
    @State private var isLoading = true

    @AppStorage(Defaults.AppStorageKeys.lastSeenWhatsNewVersion)
    private var lastSeenVersion: String = ""

    // The site's `/latest` hero pads 7rem off the top to clear the site's
    // fixed nav. We hide that nav in-app, so the eyebrow + version end up
    // floating well below the iOS nav bar — collapse the padding so the
    // "What's New" banner sits right under the chrome.
    private static let injectedCSS = """
    header.header { display: none !important; }
    body { padding-top: env(safe-area-inset-top) !important; }
    .latest-hero { padding-top: 1.5rem !important; padding-bottom: 1rem !important; }
    .old-release { padding-top: 0.5rem !important; }
    footer { display: none !important; }
    """

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            // Open the version-specific permalink so a user on an older
            // build sees the notes for the build they actually have, not
            // whatever's newest on the site. /latest would always render
            // releases[0] regardless of which app version is installed.
            WebView(
                url: URL(string: "https://clic.dance/releases/\(OSEnvironment.versionInfo)")!,
                injectedCSS: Self.injectedCSS,
                isLoading: $isLoading
            )
            .ignoresSafeArea()
            .opacity(isLoading ? 0 : 1)

            if isLoading {
                ProgressView()
                    .controlSize(.large)
            }
        }
        .navigationTitle("What's New")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.thinMaterial, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear {
            lastSeenVersion = OSEnvironment.versionInfo
        }
    }
}

#Preview {
    NavigationStack {
        WhatsNewWebView()
    }
}
