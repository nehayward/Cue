import Analytics
import NewsletterKit
import SwiftUI

/// Optional newsletter capture step. Shows a single capsule TextField, a
/// state-machine pill (idle → submitting → subscribed / alreadySubscribed /
/// failure), and a Skip ghost button. Server (Buttondown via Clic's
/// `/newsletter/subscribe` endpoint) is the source of truth — no local
/// persistence.
struct EmailStep: View {
    enum SubmissionState: Equatable {
        case idle, submitting, subscribed, alreadySubscribed, failure(String)
    }

    @FocusState private var emailFocused: Bool
    @State private var email: String = ""
    @State private var state: SubmissionState = .idle
    var advance: () -> Void
    /// Tag passed to Buttondown so signups can be segmented by where they
    /// came from. Onboarding passes `"ios-onboarding"`, the Preferences
    /// entry passes `"ios-preferences"`.
    var source: String = "ios"

    private var isValid: Bool {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.contains("@") && trimmed.contains(".") && trimmed.count >= 5
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 12) {
                Image(systemName: "envelope.fill")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(.white)
                    .shadow(color: .white.opacity(0.35), radius: 20)

                Text("Get product updates and tips. No spam.")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            // No `prompt:` — iOS keeps overriding prompt color with the system
            // tint (blue against dark backgrounds). Custom overlay placeholder
            // gives us exact control.
            TextField("", text: $email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($emailFocused)
                .font(.headline)
                .foregroundStyle(.white)
                .tint(.white)
                .padding(.vertical, 14)
                .padding(.horizontal, 18)
                .background {
                    Capsule()
                        .fill(.white.opacity(0.12))
                        .overlay {
                            Capsule()
                                .strokeBorder(.white.opacity(emailFocused ? 0.5 : 0.2), lineWidth: 1)
                        }
                }
                .overlay(alignment: .leading) {
                    if email.isEmpty {
                        Text("you@example.com")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .padding(.leading, 18)
                            .allowsHitTesting(false)
                    }
                }
                // Cap the input width so it matches the pill button on iPad /
                // Mac — phone widths still constrained by the outer 28pt pad.
                .frame(maxWidth: 500)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 28)
                .submitLabel(.go)
                .onSubmit(submit)

            // Required disclosure for collecting an email address — gets us
            // through App Review without questions and lets users tap
            // straight to the policy if they want details. Sits right under
            // the input so the consent context is adjacent to the field.
            Link(destination: URL(string: "https://clic.dance/privacy")!) {
                Text("Privacy")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.55))
                    .underline()
            }

            if case let .failure(message) = state {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()

            VStack(spacing: 10) {
                PrimaryPillButton(
                    title: pillTitle,
                    icon: pillIcon,
                    isDisabled: !isValid || state == .submitting,
                    action: submit
                )

                Button {
                    Analytics.shared.track(OnboardingEvent.emailSkipped)
                    advance()
                } label: {
                    Text("Skip")
                        .font(.callout.weight(.medium))
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                }
                .foregroundStyle(.white.opacity(0.7))
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 44)
        }
    }

    private var pillTitle: String {
        switch state {
        case .idle, .failure: "Subscribe"
        case .submitting: "Subscribing…"
        case .subscribed: "Check your inbox"
        case .alreadySubscribed: "You're on the list"
        }
    }

    private var pillIcon: String? {
        switch state {
        case .idle, .failure: "paperplane.fill"
        case .submitting: nil
        case .subscribed, .alreadySubscribed: "checkmark"
        }
    }

    private func submit() {
        guard isValid, state != .submitting else { return }
        HapticManager.shared.fireHaptic(.buttonPress)
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        emailFocused = false
        state = .submitting

        Task {
            do {
                let result = try await NewsletterService.subscribe(
                    email: trimmed,
                    source: source
                )
                await MainActor.run {
                    switch result {
                    case .subscribed:        state = .subscribed
                    case .alreadySubscribed: state = .alreadySubscribed
                    }
                    // Track both new and existing-subscriber returns — both
                    // are successful submissions from the user's perspective
                    // (they typed an email, the server accepted it). The
                    // `source` property lets us split onboarding vs.
                    // preferences signups in the dashboard.
                    Analytics.shared.track(
                        OnboardingEvent.emailSubscribed,
                        with: ["source": source]
                    )
                }
                // Hold the confirmation pill a beat so the user reads it,
                // then advance to the next step (or dismiss if we're in the
                // standalone Preferences sheet).
                try? await Task.sleep(for: .milliseconds(900))
                await MainActor.run { advance() }
            } catch let error as NewsletterError {
                await MainActor.run {
                    state = .failure(error.errorDescription ?? "Couldn't subscribe — please try again.")
                }
            } catch {
                await MainActor.run {
                    state = .failure("Couldn't subscribe — please try again.")
                }
            }
        }
    }
}
