import CloudStorage
import OrderedCollections
import Defaults
import SwiftUI
import SonosKit
import NukeUI
import VibesDS

struct SelectGroupView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SonosService.self) private var sonosService
    @Environment(SelectedGroupService.self) private var selectedGroupService

    @State private var filter: String = ""

    var onSelection: ((GroupRoom) async -> Void)? = nil

    var body: some View {
        List {
            if onSelection != nil {
                Text("Select Group To Play")
                    .bold()
                    .font(.title)
                    .multilineTextAlignment(.center)
                    .listRowBackground(Color.clear)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            TextField("Filter", text: $filter)
            ForEach(filteredAndSortedGroups) { group in
                VStack(alignment: .leading) {
                    Button {
                        HapticManager.shared.fireHaptic(.buttonPress)
                        withAnimation {
                            dismiss()
                        }
                        selectedGroupService.group = group
                        Task {
                            await onSelection?(group)
                        }
                    } label: {
                        Text(group.nameWithCount)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .listRowSpacing(10)
        .foregroundStyle(.primary)
        .fontDesign(.rounded)
        .task {
            try? await sonosService.updateGroups()
            try? await sonosService.load(useCache: true)
        }
        .listStyle(.insetGrouped)
        .addDismiss {
            dismiss()
        }
        .animation(.default, value: sonosService.sorted)
        .searchable(text: $filter)
    }

    var filteredAndSortedGroups: [GroupRoom] {
        let filtered = sonosService.sorted.filter { $0.nameWithCount.range(of: filter, options: .caseInsensitive) != nil }
        let nonFiltered = sonosService.sorted.filter { $0.nameWithCount.range(of: filter, options: .caseInsensitive) == nil }
        return (filtered + nonFiltered).sorted { $0.coordinatorRoom.isPlaying && !$1.coordinatorRoom.isPlaying }
    }
}

//@available(iOS 18, *)
//#Preview {
//    @Previewable @State var group: GroupRoom? = nil
//    Text(group?.nameWithCount ?? "Select")
//        .sheet(isPresented: .constant(true)) {
//            SelectGroupView(group: $group)
//                .withEnvironments()
//        }
//
//}
