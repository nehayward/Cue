import MusicSearchKit
import SonosKit
import SwiftUI

/// The Files provider's setup: which folder, how the scan is going, and a
/// way out. Unlike the streaming services there is no account — the folder
/// is the whole setup, and everything plays on this device.
struct FilesManagementView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var library = FilesLibraryService.shared
    @State private var pickError: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if let name = library.folderName {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(name)
                                Text(library.isCloudFolder ? "iCloud Drive" : "On this device")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: library.isCloudFolder ? "icloud" : "folder")
                                .foregroundStyle(MusicService.files.brandColor)
                        }
                    }
                    Button {
                        chooseFolder()
                    } label: {
                        Label(library.isConfigured ? "Choose a Different Folder…" : "Choose Folder…", systemImage: "folder.badge.plus")
                    }
                } footer: {
                    Text("Pick any folder of music — on this device, in iCloud Drive, or on another location the Files app can open. Cue reads the tags of MP3, AAC, ALAC, FLAC, WAV and AIFF files, falls back to an Artist/Album/Song folder layout for untagged ones, picks up .m3u playlists, and plays everything on this device.")
                }

                if library.isConfigured {
                    Section {
                        LabeledContent("Songs", value: library.songs.count.formatted())
                        LabeledContent("Albums", value: library.albums.count.formatted())
                        LabeledContent("Artists", value: library.artists.count.formatted())
                        if !library.playlists.isEmpty {
                            LabeledContent("Playlists", value: library.playlists.count.formatted())
                        }

                        if library.isScanning {
                            HStack(spacing: 12) {
                                ProgressView()
                                Text(library.foundCount > 0
                                     ? "Reading tags… \(library.scannedCount) of \(library.foundCount)"
                                     : "Looking for music…")
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        } else if let lastScan = library.lastScan {
                            LabeledContent("Last Scan", value: lastScan.formatted(.relative(presentation: .named)))
                        }

                        if library.pendingDownloadCount > 0 {
                            Label {
                                Text(library.pendingDownloadCount == 1
                                     ? "1 song is in iCloud only. It's listed by name until it's downloaded — play it, or fetch it from Downloads."
                                     : "\(library.pendingDownloadCount.formatted()) songs are in iCloud only. They're listed by name until downloaded — play them, or fetch them from Downloads.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            } icon: {
                                Image(systemName: "icloud.and.arrow.down")
                            }
                        }

                        Button {
                            library.rescan()
                        } label: {
                            Label("Rescan Folder", systemImage: "arrow.clockwise")
                        }
                        .disabled(library.isScanning)
                    } header: {
                        Text("Library")
                    } footer: {
                        Text("The library refreshes itself when opened; rescan to pick up changes right away. Only files that changed are read again, and the index is kept on this device so the library is ready at launch.")
                    }

                    Section {
                        Button(role: .destructive) {
                            library.removeFolder()
                        } label: {
                            Text("Remove Folder")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                        .listRowBackground(Color.clear)
                    } footer: {
                        Text("Forgets the folder and its index. The files themselves aren't touched.")
                    }
                }

                if let error = library.lastError ?? pickError {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Files")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Dismiss", systemImage: "xmark") { dismiss() }
                }
            }
        }
    }

    private func chooseFolder() {
        FolderPicker.shared.present { url in
            guard let url else { return }
            pickError = nil
            library.setFolder(url)
            if let error = library.lastError {
                AlertService.shared.showAlert(with: error, imageName: "exclamationmark.triangle")
            } else {
                AlertService.shared.showAlert(with: "Reading \(url.lastPathComponent)…", imageName: "folder.fill")
            }
            // Discovery turns Files off while no folder is chosen (it can't
            // play from nothing); a chosen folder turns it back on so it
            // shows in search and browse straight away.
            CoreFeatures.shared.enabledServices(.files).wrappedValue = true
            // And into the tab view, so the folder is one tap away rather
            // than another trip through Customize Tabs.
            TabProviderStore.shared.add(.files)
        }
    }
}

#Preview {
    FilesManagementView()
        .withEnvironments()
}
