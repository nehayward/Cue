import SwiftUI
import SonosKit

enum Filter: String, CaseIterable {
    case artist
    case songs
    case albums
    case playlists

    var title: String {
        self.rawValue.capitalized
    }
}

@Observable
class FilterSelection: Hashable, Identifiable {
    let filter: Filter
    var isFiltered: Bool
    var notFiltered: Bool { !isFiltered }

    init(filter: Filter, isFiltered: Bool) {
        self.filter = filter
        self.isFiltered = isFiltered
    }

    nonisolated static func == (lhs:
                                FilterSelection, rhs: FilterSelection) -> Bool {
        lhs === rhs
    }

    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }

    static var songs = FilterSelection(filter: .songs, isFiltered: false)
    static var albums = FilterSelection(filter: .albums, isFiltered: false)
    static var playlists = FilterSelection(filter: .playlists, isFiltered: false)
    static var artist = FilterSelection(filter: .artist, isFiltered: false)

    static var defaultFilters: [FilterSelection] = [.songs, .albums, .playlists]
}

struct FilterView: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Binding var filters: [FilterSelection]

    var body: some View {
        ScrollView(.horizontal) {
            HStack {
                ForEach($filters) { $filter in
                    Toggle(filter.filter.title, isOn: $filter.isFiltered)
                        .toggleStyle(.button)
                        .clipShape(Capsule())
                        .background {
                            if filter.isFiltered {
                                Capsule()
                                    .foregroundStyle(.accent.gradient)
                            } else {
                                Capsule()
                                    .foregroundStyle(.background)
                            }
                        }
                        .foregroundStyle(filter.isFiltered ? Color.black.gradient : Color.accentColor.gradient)
                        .onChange(of: filter) {
                            HapticManager.shared.fireHaptic(.selection)
                        }
                }
            }
            .scrollTargetLayout()
            .fontDesign(.rounded)
            .fontWeight(.bold)
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollIndicators(.hidden)
        .scrollContentBackground(.hidden)
        .contentMargins(.leading, 20, for: .scrollContent)
        .mask(
            HStack(spacing: 0) {
                // Left gradient
                LinearGradient(gradient:
                   Gradient(
                       colors: [Color.black.opacity(0), Color.black]),
                       startPoint: .leading, endPoint: .trailing
                   )
                   .frame(width: 20)

                // Middle
                Rectangle().fill(Color.black)

                // Right gradient
                LinearGradient(gradient:
                   Gradient(
                       colors: [Color.black, Color.black.opacity(0)]),
                       startPoint: .leading, endPoint: .trailing
                   )
                   .frame(width: 20)
            }
         )
    }
}

#Preview {
    FilterView(
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
