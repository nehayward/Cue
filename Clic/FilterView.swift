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

struct FilterSelection {
    let filter: Filter
    let isOn: Bool
}

struct FilterView: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @State var show: Bool = false
    @State var selected: Bool = false

    var scenes: [SonosScene] = []
    struct Alarm: Hashable, Identifiable {
        var id = UUID()
        var isOn = false
        var name = ""
    }


    @State private var alarms = [
        Alarm(isOn: true, name: "Morning"),
        Alarm(isOn: false, name: "Evening")
    ]


    var body: some View {
        ScrollView(.horizontal) {
            HStack {
                ForEach(Filter.allCases, id: \.self) { filter in
//                    Button {
//
//                    } label: {
//                        Text(filter.title)
//                            .padding(12)
//                            .background{
//                                Capsule()
//                                    .foregroundStyle(.thinMaterial)
//                            }
//                            .padding(2)
//                    }
//                    .buttonStyle(.plain)
                    Toggle(filter.title, isOn: $selected)
                        .toggleStyle(.button)

                }
            }
            .scrollTargetLayout()
            .fontDesign(.rounded)
            .fontWeight(.bold)
            ForEach($alarms, id: \.self) { $filter in
//                    Button {
//
//                    } label: {
//                        Text(filter.title)
//                            .padding(12)
//                            .background{
//                                Capsule()
//                                    .foregroundStyle(.thinMaterial)
//                            }
//                            .padding(2)
//                    }
//                    .buttonStyle(.plain)
                Toggle(filter.name, isOn: $filter.isOn)
                    .toggleStyle(.button)
                    .clipShape(Capsule())

            }
            Toggle("Enable all alarms", sources: $alarms, isOn: \.isOn)
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollIndicators(.hidden)
        .scrollContentBackground(.hidden)
        .mask(alignment: .trailing) {
            LinearGradient(stops: [.init(color: Color.black, location: 0.95), .init(color: Color.black.opacity(0), location: 1.05)], startPoint: .leading, endPoint: .trailing)
        }
    }
}

#Preview {
    FilterView()
        .environment(SonosService())
}
