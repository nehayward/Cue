import MusicSearchKit
import SwiftUI

/// The layout of onboarding's set-up pages, one for each service chosen that
/// needs signing in or a folder (`SubsonicSetupStep`,
/// `AudiobookshelfSetupStep`, `FilesSetupStep`; Plex's page has its own body
/// and the same footer): the service's tile, a title and a line, what the
/// page asks for, then its action and Set Up Later (`SetupPageFooter`).
/// Choosing a service on the services page only ticks it; this is where it's
/// set up, in onboarding's own look rather than Settings' sheet over it.
struct SetupPage<Content: View>: View {
    let service: MediaSearchService
    let title: String
    let subtitle: String
    let actionTitle: String
    var actionIcon: String? = nil
    var isActionDisabled = false
    let action: () -> Void
    let later: () -> Void
    @ViewBuilder var content: Content

    @State private var contentIn = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    VStack(spacing: 10) {
                        ServiceMarkTile(service: service, size: 60)
                            .padding(.bottom, 4)
                        Text(title)
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Text(subtitle)
                            .font(.callout)
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(.horizontal, 28)
                    }
                    .multilineTextAlignment(.center)
                    .padding(.top, 36)
                    .padding(.bottom, 24)

                    content
                        .padding(.horizontal, 20)
                        .frame(maxWidth: 500)
                        .opacity(contentIn ? 1 : 0)
                        .offset(y: contentIn ? 0 : 24)
                }
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)

            SetupPageFooter(
                actionTitle: actionTitle,
                actionIcon: actionIcon,
                isActionDisabled: isActionDisabled,
                action: action,
                later: later
            )
            .opacity(contentIn ? 1 : 0)
            .offset(y: contentIn ? 0 : 24)
        }
        // Dark fields, keyboard and placeholders on the dark mesh, whatever
        // the app's appearance.
        .environment(\.colorScheme, .dark)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) { contentIn = true }
        }
    }
}

/// A set-up page's foot: its action, Set Up Later, and where to finish it
/// later, so passing a service by is plainly fine.
struct SetupPageFooter: View {
    let actionTitle: String
    var actionIcon: String? = nil
    var isActionDisabled = false
    let action: () -> Void
    let later: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            PrimaryPillButton(title: actionTitle, icon: actionIcon, isDisabled: isActionDisabled) {
                HapticManager.shared.fireHaptic(.buttonPress)
                action()
            }
            Button {
                HapticManager.shared.fireHaptic(.selection)
                later()
            } label: {
                Text("Set Up Later")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.85))
            Text("You can finish this any time in Settings.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.55))
        }
        .padding(.horizontal, 28)
        .padding(.top, 8)
        .padding(.bottom, 20)
    }
}

/// The fields of a set-up page on one rounded card, as a form groups them.
struct SetupFieldCard<Fields: View>: View {
    @ViewBuilder var fields: Fields

    var body: some View {
        VStack(spacing: 0) {
            fields
        }
        .background {
            let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
            shape
                .fill(.white.opacity(0.08))
                .overlay { shape.strokeBorder(.white.opacity(0.12), lineWidth: 1) }
        }
    }
}

/// The hairline between two fields on a `SetupFieldCard`.
struct SetupFieldDivider: View {
    var body: some View {
        Rectangle()
            .fill(.white.opacity(0.12))
            .frame(height: 1)
            .padding(.leading, 16)
    }
}

extension View {
    /// A field on a `SetupFieldCard`.
    func setupField() -> some View {
        self
            .font(.body)
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
    }
}

/// A set-up page's line under its fields: what went wrong, red, else the
/// hint.
struct SetupFieldNote: View {
    var error: String?
    let hint: String

    var body: some View {
        Text(error ?? hint)
            .font(.footnote)
            .foregroundStyle(error == nil ? AnyShapeStyle(.white.opacity(0.6)) : AnyShapeStyle(Color.red))
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .contentTransition(.opacity)
            .animation(.easeInOut(duration: 0.2), value: error)
    }
}
