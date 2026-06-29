import MusicSearchKit
import SwiftUI

/// Modern segmented control for choosing the Plex connection type, shared
/// between onboarding (`PlexStep`) and the Plex settings screen
/// (`PlexManagementView`). Shows the three connection modes — Auto / Remote /
/// Local — with a sliding accent pill and a short description of the current
/// choice underneath.
///
/// Uses adaptive colors (`.primary` / `.secondary`) so it reads correctly in
/// both light and dark contexts; place it in a `.dark` color scheme when shown
/// over the onboarding background.
struct PlexConnectionPicker: View {
    @Binding var selection: PlexAPI.ConnectionPreference

    @Namespace private var pillNamespace

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 0) {
                ForEach(PlexAPI.ConnectionPreference.allCases, id: \.self) { preference in
                    segment(preference)
                }
            }
            .padding(4)
            .background {
                Capsule(style: .continuous)
                    .fill(Color.primary.opacity(0.08))
            }

            Text(selection.description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.easeInOut(duration: 0.2), value: selection)
        }
    }

    private func segment(_ preference: PlexAPI.ConnectionPreference) -> some View {
        let isSelected = selection == preference
        return Button {
            HapticManager.shared.fireHaptic(.selection)
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                selection = preference
            }
        } label: {
            Text(preference.shortName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background {
                    if isSelected {
                        Capsule(style: .continuous)
                            .fill(Color.accentColor)
                            .matchedGeometryEffect(id: "selectedPill", in: pillNamespace)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
