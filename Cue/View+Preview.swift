import SonosKit
import SwiftUI

extension View {
    func forPreview() -> some View {
        withEnvironments()
        .environment(SelectedGroupService(group: .theater))
        .onAppear {
            if OSEnvironment.isPreviews {
                SonosService.shared.monitor()
            }
        }
    }
}
