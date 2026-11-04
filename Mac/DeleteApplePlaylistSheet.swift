import SonosKit
import SwiftUI

/// The confirmation for deleting an Apple Music playlist on the Mac, which Cue
/// asks the Music app to do (`ApplePlaylistDeleter`), and where it says why a
/// playlist can't go. A card fitted to its text, as `RouteTransferPrompt` is:
/// a navigation stack in a fitted sheet collapsed to 100 pt wide.
struct DeleteApplePlaylistSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(AlertService.self) private var alertService

    let content: PlayableContent

    private enum Step: Equatable {
        case checking
        case ready(linkedPersistentID: String?)
        case deleting
        case refused(ApplePlaylistDeleter.Problem)
    }

    @State private var step = Step.checking
    @State private var height: CGFloat = 300

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: refusal == nil ? "trash" : "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(refusal == nil ? .red : .secondary)

            Text(refusal == nil ? "Delete Playlist?" : "Can’t Delete Playlist")
                .font(.title2)
                .fontWeight(.bold)
                .fontDesign(.rounded)

            Text(refusal?.message ?? "“\(content.title)” will leave your Apple Music library on all your devices. This can’t be undone.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if refusal == nil {
                Text("Cue asks the Music app to do this, and opens it if it’s closed.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 10) {
                buttons
            }
            .controlSize(.large)
            .buttonBorderShape(.capsule)
            .padding(.top, 4)
        }
        .padding(24)
        .frame(width: 400)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        .presentationDetents([.height(height)])
        .presentationSizing(.fitted)
        .interactiveDismissDisabled(step == .deleting)
        .task {
            do {
                step = .ready(linkedPersistentID: try await ApplePlaylistDeleter.check(content))
            } catch {
                step = .refused(problem(from: error))
            }
        }
    }

    private var refusal: ApplePlaylistDeleter.Problem? {
        guard case let .refused(problem) = step else { return nil }
        return problem
    }

    @ViewBuilder
    private var buttons: some View {
        switch step {
        case .checking, .deleting:
            Button(role: .destructive) {} label: {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(true)

            cancelButton
                .disabled(step == .deleting)
        case let .ready(linkedPersistentID):
            Button(role: .destructive) {
                delete(linkedPersistentID: linkedPersistentID)
            } label: {
                Text("Delete Playlist")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)

            cancelButton
        case let .refused(problem):
            if problem.isPermission {
                Button {
                    openURL(ApplePlaylistDeleter.automationSettings)
                    dismiss()
                } label: {
                    Text("Open System Settings")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                cancelButton
            } else {
                Button {
                    dismiss()
                } label: {
                    Text("OK")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.primary)
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var cancelButton: some View {
        Button(role: .cancel) {
            dismiss()
        } label: {
            Text("Cancel")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(.primary)
        .keyboardShortcut(.cancelAction)
    }

    private func delete(linkedPersistentID: String?) {
        step = .deleting
        Task {
            do {
                try await ApplePlaylistDeleter.delete(content, linkedPersistentID: linkedPersistentID)
                ApplePlaylistDeleter.finish(content)
                alertService.showAlert(with: "Removed \(content.title)", imageName: "trash")
                dismiss()
            } catch {
                step = .refused(problem(from: error))
            }
        }
    }

    private func problem(from error: Error) -> ApplePlaylistDeleter.Problem {
        error as? ApplePlaylistDeleter.Problem ?? .init(message: error.localizedDescription)
    }
}
