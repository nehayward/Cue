import SwiftUI
import WatchSync

/// Fast Download: everything not on the watch yet, fetched over the watch's
/// own Wi‑Fi while Cue stays open.
///
/// It needs Bluetooth off on the iPhone. While the two are connected over
/// Bluetooth, watchOS sends the watch's traffic through the iPhone, and no
/// app can choose otherwise; turning Bluetooth off in the iPhone's Settings
/// (Control Center only disconnects accessories, and leaves the watch
/// connected) leaves the watch its own Wi‑Fi. The screen asks for that up
/// front, shows the speed as it goes, and asks again while the speed says
/// the songs are still coming through the iPhone.
struct FastDownloadScreen: View {
    @Environment(WatchDownloadStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    switch store.fastPhase {
                    case .off:
                        intro
                    case .running:
                        running
                    case .finished:
                        finished
                    }
                }
            }
            .navigationTitle("Fast Download")
        }
    }

    // MARK: - Before

    private var intro: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(store.remainingCount == 1 ? "1 song to download" : "\(store.remainingCount) songs to download")
                .font(.headline)
            Text("Through your iPhone it's slow. Turn off your iPhone's Bluetooth and your watch downloads over its own Wi‑Fi instead.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            step(1, "On your iPhone, open Settings › Bluetooth and turn it off.")
            Text("Control Center's button leaves your watch connected. Headphones stay connected to your watch.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            step(2, "Keep Cue open until it's done.")

            Button {
                store.startFastDownload()
            } label: {
                Label("Start", systemImage: "bolt.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(store.remainingCount == 0)
        }
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "\(number).circle.fill")
                .foregroundStyle(.tint)
            Text(text)
        }
    }

    // MARK: - While it runs

    private var running: some View {
        VStack(alignment: .leading, spacing: 10) {
            ProgressView(value: Double(store.fastCompleted), total: Double(max(store.fastTotal, 1)))
                .tint(.accentColor)
            Text("\(store.fastCompleted) of \(store.fastTotal) songs")
                .font(.headline)
                .monospacedDigit()

            routeRow

            if store.isWaitingForNetwork {
                Text("No connection. Check your watch is on Wi‑Fi in its Settings app.")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            } else if store.route == .throughPhone {
                Text("Still coming through your iPhone. Turn Bluetooth off in its Settings app, not Control Center.")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }

            ForEach(store.fastActive) { item in
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.track.title)
                        .font(.footnote)
                        .lineLimit(1)
                    if item.bytesExpected > 0 {
                        ProgressView(value: item.progress)
                    } else {
                        // A transcoded stream doesn't say how big it is.
                        Text(ByteCountFormatter.string(fromByteCount: item.bytesReceived, countStyle: .file))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }

            Button(role: .destructive) {
                store.stopFastDownload()
            } label: {
                Text("Stop")
                    .frame(maxWidth: .infinity)
            }
        }
    }

    /// How the songs are coming, by their speed.
    private var routeRow: some View {
        HStack(spacing: 6) {
            switch store.route {
            case .measuring:
                Image(systemName: "speedometer")
                    .foregroundStyle(.secondary)
                Text("Checking speed")
            case .wifi:
                Image(systemName: "wifi")
                    .foregroundStyle(.green)
                Text("Wi‑Fi")
            case .throughPhone:
                Image(systemName: "iphone")
                    .foregroundStyle(.orange)
                Text("Via iPhone")
            }
            Spacer(minLength: 0)
            Text(store.bytesPerSecond.map(Self.speedText) ?? "–")
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .font(.footnote)
    }

    // MARK: - After

    private var finished: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(store.failedCount == 0 ? "All Done" : "Done", systemImage: store.failedCount == 0 ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.headline)
                .foregroundStyle(store.failedCount == 0 ? Color.green : Color.orange)
            Text(store.fastCompleted == 1 ? "1 song downloaded." : "\(store.fastCompleted) songs downloaded.")
            if store.failedCount > 0 {
                Text(store.failedCount == 1 ? "1 song couldn't download." : "\(store.failedCount) songs couldn't download.")
                    .foregroundStyle(.secondary)
                Button {
                    store.startFastDownload()
                } label: {
                    Label("Try Again", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
            }
            Text("Turn your iPhone's Bluetooth back on whenever you like.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button {
                store.dismissFastDownload()
                dismiss()
            } label: {
                Text("Done")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    static func speedText(_ bytesPerSecond: Double) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytesPerSecond), countStyle: .file) + "/s"
    }
}
