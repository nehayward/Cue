import SwiftUI
import SonosKit
import VibesDS
import CloudStorage
import Defaults
import NukeUI
import MusicKit
import OrderedCollections

struct QueueListView: View {
    private var sonosService: SonosService = .shared
    
    @State private var isQueueing: Bool = false
    @State private var content: PlayableContent?
    
    @State private var groupVolume: Double = 0
    @State private var selections = Set<String>()
    @State private var rooms: [Room] = []
    
    private var playHistoryService = PlayHistoryService.shared
    
    var viewModel: ViewModel
    var context: NSExtensionContext?
    var openURL: ((URL) -> Void)?
    
    private let impactFeedbackGenerator = UIImpactFeedbackGenerator()
    
    public init(
        viewModel: ViewModel,
        context: NSExtensionContext? = nil,
        openURL: ((URL) -> Void)?
    ) {
        self.viewModel = viewModel
        self.context = context
        self.openURL = openURL
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack {
                    if let playableContent = content {
                        HStack(alignment: .top) {
                            VibeContentArtworkView(content: playableContent)
                                .frame(width: 80, height: 80)
                                .environment(sonosService)
                            VStack(alignment: .leading) {
                                Text(playableContent.title)
                                Text(playableContent.subtitle)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fontDesign(.rounded)
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden, edges: .all)
                        .listRowInsets(EdgeInsets())
                        
                        ScrollView(.horizontal) {
                            HStack {
                                ForEach(sonosService.groups.filter { $0.rooms.count > 1 } ) { group in
                                    Button {
                                        play(group: group)
                                    } label: {
                                        VStack {
                                            Text(group.nameWithCount)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .lineLimit(1)
                                            HStack {
                                                Text(group.groupVolume, format: .number)
                                                    .foregroundStyle(.secondary)
                                                    .font(.caption)
                                                ProgressView(value: group.groupVolume / 100)
                                                    .foregroundStyle(.primary)
                                            }
                                        }
                                        .padding()
                                        .background {
                                            RoundedRectangle(cornerRadius: 12)
                                                .foregroundStyle(.thinMaterial)
                                        }
                                        .containerRelativeFrame(.horizontal, count: 2, span: 1, spacing: 12, alignment: .topLeading)
                                    }
                                }
                            }
                        }
                        .scrollIndicators(.hidden)
                        .scrollClipDisabled()
                        
                        playEverywhereButton
                        
                        ForEach($rooms) { $room in
                            VStack {
                                Button {
                                    impactFeedbackGenerator.impactOccurred()
                                    if selections.contains(room.id) {
                                        selections.remove(room.id)
                                    } else {
                                        selections.insert(room.id)
                                        if groupVolume.isZero {
                                            groupVolume = room.volume
                                        }
                                    }
                                } label: {
                                    HStack {
                                        Text(room.name)
                                            .bold()
                                        Spacer()
                                        Image(systemName: selections.contains(room.id) ? "checkmark.circle.fill" : "circle")
                                            .symbolRenderingMode(.hierarchical)
                                            .contentTransition(.symbolEffect(.replace))
                                            .foregroundStyle(selections.contains(room.id) ? Color.accentColor : .primary.opacity(0.7))
                                    }
                                    .fontDesign(.rounded)
                                    .padding()
                                }
                            }
                        }
                    }
                }
                .disabled(isQueueing)
                .fontDesign(.rounded)
                .onAppear {
                    Task {
                        if sonosService.sortedRooms.isEmpty {
                            try? await sonosService.updateGroups()
                        }
                        rooms = sonosService.sortedRooms.filter {
                            $0.state == .active
                        }.map {
                            let room = Room(id: $0.id, ip: $0.ip, name: $0.name, channelMap: $0.channelMap)
                            room.volume = $0.volume
                            return room
                        }
                    }
                }
                .animation(.default, value: sonosService.sorted)
                .animation(.default, value: selections)
                .animation(.default, value: groupVolume)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") {
                            self.context?.completeRequest(returningItems: [])
                        }
                        .keyboardShortcut(.escape)
                    }
                    
                    ToolbarItem(placement: .topBarLeading) {
                        Link(destination: URL(string: "clic://")!) {
                            Text("Open Clic…")
                        }
                    }
                }
                .navigationBarTitleDisplayMode(.inline)
            }
        }
        .foregroundStyle(.primary)
        .scrollContentBackground(.hidden)
        .padding(.horizontal)
        .overlay {
            if isQueueing {
                ProgressView()
                    .background {
                        Circle()
                            .padding()
                            .foregroundStyle(.thinMaterial)
                    }
            }
        }
        .task {
            try? await sonosService.updateGroups()
            try? await sonosService.load(useCache: true)
            impactFeedbackGenerator.prepare()
        }
        .onChange(of: viewModel.url) { newValue in
            Task {
                viewModel.isLoading = true
                self.content = await fetchContentWithRetry(from: newValue)
                viewModel.isLoading = false
            }
        }
        .overlay {
            if content == nil, !viewModel.isLoading {
                VStack {
                    Text("Only Apple Music, Spotify, and Tidal Supported")
                        .font(.title)
                        .padding()
                        .multilineTextAlignment(.center)
                    Text("Album, Songs, and Public Playlists.")
                        .multilineTextAlignment(.center)
                }
            }
            if content != nil, sonosService.groups.isEmpty {
                Text("No system available")
                    .font(.title)
                    .padding()
                    .multilineTextAlignment(.center)
            }
            if viewModel.isLoading {
                ProgressView()
            }
        }
        .overlay(alignment: .bottom) {
            VStack {
                HStack {
                    VibeSlider(value: $groupVolume, step: 1)
                    Text(groupVolume/100, format: .percent)
                        .animation(nil, value: groupVolume)
                        .monospacedDigit()
                }
                .frame(height: 24)
                .padding(.bottom)
                Button {
                    Task {
                        impactFeedbackGenerator.impactOccurred()
                        let rooms = rooms.filter { room in
                            selections.contains(room.id)
                        }
                        guard let newGroup = await sonosService.speedGroup(rooms: rooms), let content else {
                            print("Failed!")
                            return
                        }
                        isQueueing = true
                        playHistoryService.history.remove(content)
                        playHistoryService.history.insert(content, at: 0)
                        
                        try await sonosService.queue(playable: content, group: newGroup, position: .now)
                        
                        await withTaskGroup(of: Void.self) { group in
                            group.addTask {
                                await sonosService.play(ip: newGroup.ip)
                            }
                            for room in rooms {
                                group.addTask {
                                    await sonosService.setDeviceVolume(ip: room.ip, volume: Int(groupVolume))
                                    await sonosService.setRoomMute(IP: room.ip, mute: false)
                                }
                            }
                        }
                        
                        try await Task.sleep(for: .microseconds(200))
                        await sonosService.snapShotGroup(ip: newGroup.ip)
                        
                        openURL?(URL(string: "clic://device?id=\(newGroup.coordinatorID)")!)
                        self.context?.completeRequest(returningItems: [])
                    }
                } label: {
                    Text("Play")
                        .frame(maxWidth: .infinity)
                        .bold()
                        .fontDesign(.rounded)
                }
                .transition(.slide)
                .buttonStyle(.borderedProminent)
                .tint(.accentColor)
                .disabled(selections.isEmpty)
                .disabled(isQueueing)
            }
            .padding()
            .background(.thinMaterial)
        }
        .accentColor(.teal)
    }
    
    var playEverywhereButton: some View {
        Button {
            impactFeedbackGenerator.impactOccurred()
            for room in rooms {
                if groupVolume.isZero {
                    groupVolume = room.volume
                }
                selections.insert(room.id)
            }
        } label: {
            Text("Everywhere")
                .frame(maxWidth: .infinity)
                .bold()
        }
        .buttonStyle(.bordered)
        .fontDesign(.rounded)
        .tint(.accentColor)
        .foregroundStyle(Color.accentColor)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())
    }
    
    func play(group: GroupRoom) {
        Task {
            guard let content else { return }
            impactFeedbackGenerator.impactOccurred()

            isQueueing = true
            playHistoryService.history.remove(content)
            playHistoryService.history.insert(content, at: 0)
            
            try await sonosService.queue(playable: content, group: group, position: .now)
            await sonosService.play(ip: group.ip)
    
            openURL?(URL(string: "clic://device?id=\(group.coordinatorID)")!)
            self.context?.completeRequest(returningItems: [])
        }
    }
    
    @Observable
    final class ViewModel {
        var url: URL?
        var isLoading: Bool = true
    }
    
    
    @MainActor
    private func fetchContentWithRetry(from url: URL?) async -> PlayableContent? {
        guard let url else { return nil }

        if let content = await sonosService.getContent(from: url) {
            return content
        }
        // Retry once
        return await sonosService.getContent(from: url)
    }
}
