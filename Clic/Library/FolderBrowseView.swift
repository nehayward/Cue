import SwiftUI
import SonosKit
import OrderedCollections

struct FolderBrowseView: View {
    let item: PlayableContent
    let title: String
    
    @Environment(Router.self) private var router: Router?
    @Environment(LibraryBrowseService.self) private var browseService
    @Environment(SelectedGroupService.self) private var selectedGroupService
    @State private var items: OrderedSet<PlayableContent> = []
    @State private var isLoading = false
    
    var body: some View {
        List {
            Button {
                Task {
                    let queue: ((GroupRoom) async throws -> Void) = { group in
                        QueueManager.shared.addToQueue(
                            item: QueueItem(
                                playableContent: item,
                                group: group,
                                position: .now,
                                showBanner: false
                            )
                        )
                        Router.main.show(destination: .player(groupID: group.coordinatorID))
                        return
                    }
                    
                    guard let group = selectedGroupService.group else {
                        router?.sheet(to: .selectGroup(selectedGroupService: selectedGroupService, onSelection: queue, content: item))
                        return
                    }
                    
                    try await queue(group)
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
            ForEach(items) { item in
                PlayableContentView(item: item)
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
        let newItems = await browseService.browseFolder(folderID: item.id)
        items = OrderedSet(newItems)
        isLoading = false
    }
}
