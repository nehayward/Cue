import SwiftUI

struct GroupNoLongerAvailableScreen: View {
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        Text("Group No Longer Available")
            .foregroundStyle(.secondary)
            .fontDesign(.rounded)
            .font(.title2)
    }
}
