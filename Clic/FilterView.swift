import SwiftUI
import SonosKit
import MusicSearchKit

enum Filter: String, CaseIterable {
    case artist
    case songs
    case albums
    case playlists
    case library

    var title: String {
        self.rawValue.capitalized
    }

    var toContentType: [ContentType] {
        switch self {
        case .artist:
            return [.artist, .libraryArtist]
        case .songs:
            return [.track, .libraryTrack]
        case .albums:
            return [.album, .libraryAlbum]
        case .playlists:
            return [.playlist, .libraryPlaylist]
        case .library:
            return [.libraryAlbum, .libraryTrack, .libraryArtist, .libraryPlaylist]
        }
    }

    var symbol: String {
        switch self {
        case .songs:
            return "music.note"
        case .albums:
            return "smallcircle.circle.fill"
        case .artist:
            return "music.mic"
        case .playlists:
            return "rectangle.stack.badge.play"
        case .library:
            return "books.vertical.fill"
        }
    }
}

@Observable
final class FilterSelection: Hashable, Identifiable {
    let filter: Filter
    var isFiltered: Bool
    var notFiltered: Bool { !isFiltered }

    init(filter: Filter, isFiltered: Bool) {
        self.filter = filter
        self.isFiltered = isFiltered
    }

    nonisolated static func == (lhs: FilterSelection, rhs: FilterSelection) -> Bool { lhs === rhs}

    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }

    static var songs = FilterSelection(filter: .songs, isFiltered: false)
    static var albums = FilterSelection(filter: .albums, isFiltered: false)
    static var playlists = FilterSelection(filter: .playlists, isFiltered: false)
    static var artist = FilterSelection(filter: .artist, isFiltered: false)
    static var library = FilterSelection(filter: .library, isFiltered: false)

    static var defaultFilters: [FilterSelection] = [.songs, .albums, .playlists, .artist]
    static var appleFilters: [FilterSelection] = [.songs, .albums, .playlists, .artist, .library]
    static var alarmFilters: [FilterSelection] = [.albums, .playlists]
}

struct FilterView: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Binding var selectedService: MediaSearchService
    @Binding var filters: [FilterSelection]
    
    @Namespace private var animation

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach($filters) { $filter in
                    FilterButton(filter: $filter, animation: animation)
                }
            }
            .scrollTargetLayout()
            .fontDesign(.rounded)
            .fontWeight(.bold)
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollIndicators(.hidden)
        .scrollContentBackground(.hidden)
        .task(id: selectedService) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                if selectedService == .apple {
                    filters = FilterSelection.appleFilters
                } else {
                    filters = FilterSelection.defaultFilters
                }
            }
        }
        .mask(
            HStack(spacing: 0) {
                LinearGradient(gradient: Gradient(colors: [Color.black.opacity(0), Color.black]),
                               startPoint: .leading, endPoint: .trailing)
                    .frame(width: 20)
                Rectangle().fill(Color.black)
                LinearGradient(gradient: Gradient(colors: [Color.black, Color.black.opacity(0)]),
                               startPoint: .leading, endPoint: .trailing)
                    .frame(width: 20)
            }
            .padding(.leading, -15)
        )
        .scrollClipDisabled()
    }
}

struct FilterButton: View {
    @Binding var filter: FilterSelection
    let animation: Namespace.ID
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                filter.isFiltered.toggle()
            }
            HapticManager.shared.fireHaptic(.selection)
        }) {
            HStack(spacing: 6) {
                Image(systemName: filter.filter.symbol)
                    .imageScale(.medium)
                if filter.isFiltered {
                    Text(filter.filter.title)
                        .font(.body.smallCaps())
                        .transition(.opacity)
                        .matchedGeometryEffect(id: "filterText\(filter.filter.rawValue)", in: animation)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(filter.isFiltered ? AnyShapeStyle(Color.primary.gradient) : AnyShapeStyle(Color.secondary.opacity(0.2)))
                    .matchedGeometryEffect(id: "filterBackground\(filter.filter.rawValue)", in: animation)
            )
            .foregroundStyle(filter.isFiltered ? AnyShapeStyle(.ultraThickMaterial) : AnyShapeStyle(.secondary))
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered ? 1.05 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

#Preview {
    FilterView(
        selectedService: .constant(MediaSearchService.apple),
        filters: .constant(
            [
                FilterSelection(
                    filter: .albums,
                    isFiltered: false
                ),
                FilterSelection(
                    filter: .artist,
                    isFiltered: false
                ),
                FilterSelection(
                    filter: .songs,
                    isFiltered: false
                ),
                FilterSelection(
                    filter: .playlists,
                    isFiltered: false
                ),
            ]
        )
    )
    .environment(
        SonosService()
    )
}
