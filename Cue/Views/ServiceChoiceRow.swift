import MusicSearchKit
import SwiftUI

/// A service to pick, as onboarding's services page and the Audiobooks tab
/// without a server offer them: the service's mark on a tile of its brand
/// colour, its name, a line on what it is (`choiceDetail`), and on the right
/// whether it's chosen or that a tap opens its sign-in. One look wherever
/// Cue asks for a service, so the choice reads the same everywhere.
///
/// Colours are the hierarchical ones, so it sits on the tab's own background
/// as well as on onboarding's, which sets the dark scheme around it.
struct ServiceChoiceRow: View {
    enum Accessory: Equatable {
        /// Chosen or not: a filled check or an empty ring.
        case check(Bool)
        /// A tap opens the service's sign-in.
        case disclosure
        /// Waiting on an answer, such as Apple Music's alert.
        case progress
    }

    let service: MediaSearchService
    /// In place of the service's name, for a row that says what a tap does
    /// ("Choose Plex Books").
    var title: String? = nil
    var detail: String? = nil
    var accessory: Accessory = .disclosure
    let action: () -> Void

    private var isChosen: Bool { accessory == .check(true) }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ServiceMarkTile(service: service)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title ?? service.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(detail ?? service.choiceDetail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

                accessoryView
                    .frame(width: 28)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background {
                let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
                shape
                    .fill(Color.primary.opacity(isChosen ? 0.10 : 0.05))
                    .overlay {
                        // One width either way: only the colour says it's
                        // chosen, so nothing in the row moves.
                        shape.strokeBorder(
                            isChosen ? Color.accentColor.opacity(0.8) : Color.primary.opacity(0.08),
                            lineWidth: 1.5
                        )
                    }
            }
            .contentShape(.rect(cornerRadius: 18))
        }
        .buttonStyle(ServiceChoiceButtonStyle())
        .disabled(accessory == .progress)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: accessory)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isChosen ? .isSelected : [])
    }

    @ViewBuilder
    private var accessoryView: some View {
        switch accessory {
        case let .check(isOn):
            Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundStyle(isOn ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tertiary))
                #if !targetEnvironment(macCatalyst)
                // Not on the Mac, where an animated symbol swap costs ~90 MB
                // of GPU memory for a couple of seconds (CLAUDE.md).
                .contentTransition(.symbolEffect(.replace))
                #endif
                .accessibilityHidden(true)
        case .disclosure:
            Image(systemName: "chevron.right")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        case .progress:
            ProgressView()
        }
    }
}

/// The service's mark on a rounded tile washed in its brand colour.
struct ServiceMarkTile: View {
    let service: MediaSearchService
    var size: CGFloat = 44

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
            .fill(service.brandColor.opacity(0.16))
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                    .strokeBorder(service.brandColor.opacity(0.22), lineWidth: 1)
            }
            .overlay {
                // Apple Music's mark is a symbol sized by its font; the rest
                // are images that fit the frame, wider than tall for a
                // wordmark like TuneIn's.
                service.iconForMusicService
                    .font(.system(size: size * 0.46, weight: .semibold))
                    .frame(width: size * 0.72, height: size * 0.54)
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// A press that gives a little, as the system's list rows do.
private struct ServiceChoiceButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

#Preview {
    VStack(spacing: 10) {
        ServiceChoiceRow(service: .apple, accessory: .check(true)) { }
        ServiceChoiceRow(service: .plex, accessory: .check(false)) { }
        ServiceChoiceRow(service: .tuneIn, accessory: .progress) { }
        ServiceChoiceRow(service: .audiobookshelf) { }
    }
    .padding()
}
