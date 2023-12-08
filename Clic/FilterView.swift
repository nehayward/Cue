import SwiftUI
import SonosKit

enum Filter: String, CaseIterable {
    case artist
    case tracks
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
}

struct FilterView: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Binding var filters: [FilterSelection]

    var body: some View {
        ScrollView(.horizontal) {
            HStack {
                ForEach($filters) { $filter in
                    Toggle(filter.filter.title, isOn: $filter.isFiltered)
                        .sensoryFeedback(.selection, trigger: filter.isFiltered)
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
                }
            }
            .scrollTargetLayout()
            .fontDesign(.rounded)
            .fontWeight(.bold)
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollIndicators(.hidden)
        .scrollContentBackground(.hidden)
        .contentMargins(.leading, 12, for: .scrollContent)
        .mask(alignment: .trailing) {
            LinearGradient(stops: [.init(color: Color.black, location: 0.9), .init(color: Color.black.opacity(0), location: 1.05)], startPoint: .leading, endPoint: .trailing)
        }
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
                    filter: .tracks,
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
