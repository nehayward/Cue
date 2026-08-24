import SwiftUI
import SonosKit
import OrderedCollections

struct FolderBrowseView: View {
    let item: PlayableContent
    let title: String
    
    @Environment(Router.self) private var router: Router?
    @Environment(LibraryBrowseService.self) private var browseService
    @Environment(AppleMusicBrowseService.self) private var appleMusicBrowseService
    @Environment(SelectedGroupService.self) private var selectedGroupService
    @State private var items: OrderedSet<PlayableContent> = []
    @State private var isLoading = false
    @State private var hasMore = true

    /// Matches the `RequestedCount` used by `browseFolder`; a full page implies
    /// there may be more items to load.
    private let pageSize = 500

    var body: some View {
        List {
            if item.content.service != .apple {
                Button {
                    Task {
                        let queue: ((GroupRoom, QueuePosition) async throws -> Void) = { group, selectedPosition in
                            QueueManager.shared.addToQueue(
                                item: QueueItem(
                                    playableContent: item,
                                    group: group,
                                    position: selectedPosition,
                                    showBanner: false
                                )
                            )
                            Router.main.show(destination: .player(groupID: group.coordinatorID))
                            return
                        }

                        guard let group = selectedGroupService.group else {
                            router?.sheet(to: .selectGroup(selectedGroupService: selectedGroupService, onQueueSelection: queue, defaultPosition: .now, content: item))
                            return
                        }

                        try await queue(group, .now)
                    }
                } label: {
                    Text("Play Folder")
                        .padding(.horizontal)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .foregroundStyle(.foreground)
                }
                .bold()
                .buttonStyle(.bordered)
                .tint(.accent)
                .listRowSeparator(.hidden)
            }
            ForEach(items) { folderItem in
                PlayableContentView(item: folderItem)
                    .listRowSeparator(.hidden)
                    .task {
                        await loadMoreIfNeeded(currentItem: folderItem)
                    }
            }

            if isLoading && !items.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
                    .listRowSeparator(.hidden)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadItems()
        }
        .refreshable {
            await loadItems()
        }
        .listStyle(.plain)
    }
    
    private func loadItems() async {
        isLoading = true
        hasMore = true

        if item.content.service == .apple && item.content.type == .folder {
            // Handle Apple Music playlist folders
            let (newItems, _) = await appleMusicBrowseService.getPlaylistFolderContents(id: item.id, offset: 0)
            items = OrderedSet(newItems)
            hasMore = false
        } else {
            // Handle regular Sonos library folders
            let newItems = await browseService.browseFolder(folderID: item.id)
            items = OrderedSet(newItems)
            hasMore = newItems.count >= pageSize
        }

        isLoading = false
    }

    /// Loads the next page of Sonos folder contents as the user nears the end.
    private func loadMoreIfNeeded(currentItem: PlayableContent) async {
        // Apple Music folders are loaded in a single request above.
        guard item.content.service != .apple else { return }
        guard !isLoading, hasMore,
              let index = items.firstIndex(of: currentItem),
              index >= items.count - 10
        else { return }

        isLoading = true
        defer { isLoading = false }

        let newItems = await browseService.browseFolder(folderID: item.id, offset: items.count)
        for newItem in newItems {
            items.updateOrAppend(newItem)
        }
        hasMore = newItems.count >= pageSize
    }
}
