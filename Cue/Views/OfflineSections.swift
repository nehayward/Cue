import MusicSearchKit
import SonosKit
import SwiftUI

/// What the home screen shows while `OfflineMode` is active, as sections
/// for a `List`: one line on why the providers aren't there, and then the
/// on-device library (`OnDeviceLibrarySections`) — Play and Shuffle across
/// everything on this device, and Artists, Albums and Songs over it, from
/// every provider at once. Home hosts these on iPad and Mac; on the phone,
/// whose home is Browse, `OfflineBrowseScreen` does.
struct OfflineSections: View {
    @State private var offline = OfflineMode.shared
    @State private var downloads = DownloadManager.shared
    @State private var apple = AppleDownloadsIndex.shared
    @State private var files = FilesLibraryService.shared

    var body: some View {
        // Read here so a download finishing or an index rebuilding
        // re-decides between the empty note and the library.
        let _ = downloads.completed.count
        let _ = apple.version
        let _ = files.indexVersion

        statusSection
        if OnDeviceLibrary.isEmpty {
            emptySection
        } else {
            OnDeviceLibrarySections()
        }
    }

    /// Why the providers aren't showing, in a line: the network is gone,
    /// or the user asked. The switch is the one thing worth offering here,
    /// and it sits on the trailing side rather than taking a row of its own.
    private var statusSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: offline.hasNetwork ? "airplane" : "wifi.slash")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(offline.hasNetwork ? "Offline Mode" : "No Connection")
                        .font(.headline)
                    Text(offline.hasNetwork
                         ? "Plays on this device"
                         : "Plays on this device until the network is back")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if offline.isOn {
                    Button {
                        HapticManager.shared.fireHaptic(.buttonPress)
                        withAnimation(.spring(response: 0.3)) {
                            offline.isOn = false
                        }
                    } label: {
                        Text("Turn Off")
                            .fontWeight(.medium)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
                }
            }
            .padding(.vertical, 2)
        }
        .onAppear {
            apple.refreshIfNeeded()
        }
    }

    /// Empty, it says what to download next time.
    private var emptySection: some View {
        Section {
            ContentUnavailableView {
                Label("Nothing on This Device", systemImage: "arrow.down.circle")
            } description: {
                Text(OnDeviceLibrary.emptyDescription(for: nil))
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }
}

#Preview {
    NavigationStack {
        List {
            OfflineSections()
        }
    }
    .withEnvironments()
}
