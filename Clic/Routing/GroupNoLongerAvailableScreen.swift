import SwiftUI

struct GroupNoLongerAvailableScreen: View {
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        Text("Group No Longer Available")
            .fontDesign(.rounded)
            .font(.title)
            .task {
                try? await Task.sleep(for: .seconds(2))
                dismiss()
            }
    }
}
