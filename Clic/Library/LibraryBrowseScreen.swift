import Analytics
import CloudStorage
import MusicSearchKit
import Defaults
import NukeUI
import MusicKit
import OrderedCollections
import SwiftUI
import SonosKit
import Defaults
import TipKit

struct LibraryBrowseScreen: View {
    @Environment(\.dismiss) var dismiss

    @Environment(SonosService.self) private var sonosService
    @Environment(MusicSearchService.self) var musicSearchService
    @Environment(LibraryBrowseService.self) var browseService
    @Environment(SelectedGroupService.self) private var selectedGroupService: SelectedGroupService

    @State private var router = Router()
    @State private var alertService = AlertService()

    var body: some View {
        @Bindable var sonosService = sonosService

        NavigationStack(path: $router.path) {
            List {
                NavigationLink(value: RouterDestination.playableContentList(group: selectedGroupService.group, contentType: .artist)) {
                    Label("Artists", systemImage: "music.mic")
                }

                NavigationLink(value: RouterDestination.playableContentList(group: selectedGroupService.group, contentType: .album)) {
                    Label("Albums", systemImage: "smallcircle.circle.fill")
                }

                NavigationLink(value: RouterDestination.playableContentList(group: selectedGroupService.group, contentType: .track)) {
                    Label("Songs", systemImage: "music.note")
                }

//                NavigationLink(value: RouterDestination.playableContentList(group: selectedGroupService.group, contentType: .playlist)) {
//                    Label("Playlists", systemImage: "rectangle.stack.badge.play")
//                }

//                if !browseService.playlists.isEmpty {
//                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 16)], spacing: 16) {
//                        ForEach(browseService.playlists.prefix(5)) { item in
//                            PlayableCardView(item: item)
//                        }
//                    }
//                }

                NavigationLink(value: RouterDestination.playableContentList(group: selectedGroupService.group, contentType: .playlist)) {
                    Label("Saved Playlists", systemImage: "rectangle.stack.badge.play")
                }
                if !browseService.playlists.isEmpty {
                    ForEach(browseService.playlists.prefix(5)) { item in
                        PlayableContentView(item: item)
                    }
                }
            }
            .miniPlayerOnScrollHandler()
            .listStyle(.inset)
            .navigationTitle("Music Library")
            .navigationBarTitleDisplayMode(.inline)
            .fontDesign(.rounded)
            .task {
                await browseService.updatePlaylists()
            }
            // MARK: Workaround into I can use extension on view iOS 18 bug
            .navigationDestination(for: RouterDestination.self) { destination in
                switch destination {
                case let .player(groupID):
                    if let group = sonosService.sorted.firstIndex(where: { $0.coordinatorID == groupID }) {
                        LargePlayerView(group: $sonosService.sorted[group])
                    } else {
                        Text("Group No Longer Available")
                            .onTapGesture {
                                dismiss()
                            }
                    }
                case let .groupDestination(content, position):
                    PlayerSelectionView(playableContent: content, position: position)
                case .manageScenes:
                    ManageSceneScreen()
                case let .mediaDetail(content, _):
                    MediaDetailView(playableContent: content)
                case let .artistDetail(content, _):
                    ArtistDetailView(playableContent: content)
                case .createScene:
                    SceneBuilderScreen()
                case .alarms:
                    AlarmListView()
                case let .addAlarm(group):
                    AlarmView(group: group, alarm: .newAlarm)
                case let .editAlarm(alarm):
                    AlarmView(edit: true, alarm: alarm)
                case .speakerSettingsList:
                    SpeakerSettingsListView()
                case let .speakerSettings(room: room):
                    SpeakerSettingsView(room: room)
                case let .playableContentList(group: group, contentType: contentType):
                    let title = switch contentType {
                    case .track:
                        "Songs"
                    case .album:
                        "Albums"
                    case .artist:
                        "Artists"
                    case .playlist:
                        "Playlists"
                    default:
                        ""
                    }
                    PlayableContentList(type: contentType)
                        .navigationTitle(title)
                        .environment(group)
                case .fullPlayHistoryList:
                    PlayHistoryFullView()
                case let .playableLibraryList(title: title, items: items, action: action):
                    PlayableList(items: items, action: action)
                        .navigationTitle(title)
                case let .playableGridScreen(title: title, items: items, action: action):
                    PlayableGridScreen(items: items, action: action)
                        .navigationTitle(title)
                case .houseHold:
                    HouseholdScreen()
                case .servicePreferenceScreen:
                    ServicePreferenceScreen()
                }
            }
        }
        .environment(router)
        .withSheetDestinations(sheetDestinations: $router.presentedSheet) {
            Task {
                try? await Task.sleep(for: .milliseconds(300))
                await browseService.updatePlaylists()
            }
        }
    }
}

#Preview {
    LibraryBrowseScreen()
        .withEnvironments()
}

