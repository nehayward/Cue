import Analytics
import NukeUI
import SwiftUI
import SonosKit

/// Upgrade affordance modeled on the marketing card style at
/// clic.dance/macstories — pure black surface, thin teal stroke with a soft
/// teal aura, a social-proof eyebrow, a shimmering headline, and a fixed
/// value-prop subtitle. Pairs with a bordered teal CTA pill at the bottom.
struct PaywallButtonView: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Environment(Router.self) var router: Router?

    /// Personalizes the headline. When > 0 the card reads
    /// "Unlock N more rooms" — concrete and tied to the user's actual setup,
    /// which converts harder than a generic "Unlock Everything." "Rooms"
    /// rather than "groups" because the section headers in the speaker list
    /// are already named after rooms (Kitchen, Living Room, …) — that's the
    /// user's mental model. "Groups" is Sonos jargon; "speakers" is wrong
    /// (a group can contain multiple speakers).
    var lockedCount: Int = 0

    private let cornerRadius: CGFloat = 18

    private var headline: String {
        lockedCount > 0 ? "Unlock \(lockedCount) more rooms" : "Unlock Every Room"
    }

    var body: some View {
        Button(action: tap) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("JOIN 2,000+ MEMBERS")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.accentColor)

                    ShimmerHeadline(text: headline)

                    Text("Lock screen controls, Widgets, Shortcuts, and more.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(2, reservesSpace: false)
                }

                ctaPill
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardSurface)
            .overlay(cardBorder)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .background(tealAura)
            .padding(6)
            .fixedSize(horizontal: false, vertical: true)
        }
        .buttonStyle(NoDimButtonStyle())
        .buttonBorderShape(.roundedRectangle(radius: cornerRadius))
        .fontDesign(.rounded)
    }

    private func tap() {
        HapticManager.shared.fireHaptic(.buttonPress)
        Analytics.shared.track(.viewedPaywall)
        router?.presentedFullScreenCover = .paywall
    }

    /// Bottom CTA styled like the "Claim offer" / "Get lifetime" buttons on
    /// clic.dance — full-width bordered pill with teal text and a soft halo.
    private var ctaPill: some View {
        HStack {
            Spacer()
            Text("Start Free Trial")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.accentColor)
            Spacer()
        }
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.accentColor.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.7), lineWidth: 1)
        )
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.accentColor.opacity(0.22))
                .blur(radius: 14)
        )
    }

    /// Near-black surface with a whisper of teal in the bottom-right corner —
    /// matches the subtle gradient on the marketing offer cards.
    private var cardSurface: some View {
        ZStack {
            Color.black
            RadialGradient(
                colors: [Color.accentColor.opacity(0.12), .clear],
                center: .bottomTrailing,
                startRadius: 0,
                endRadius: 280
            )
        }
    }

    /// Thin teal stroke that brightens toward the bottom — same shape language
    /// as the "Claim offer" / "Get lifetime" buttons on the site.
    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    colors: [
                        Color.accentColor.opacity(0.45),
                        Color.accentColor.opacity(0.85)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: 1
            )
    }

    /// Soft teal halo bleeding outside the card so the stroke reads as glowing.
    private var tealAura: some View {
        RoundedRectangle(cornerRadius: cornerRadius + 4, style: .continuous)
            .fill(Color.accentColor.opacity(0.18))
            .blur(radius: 18)
            .padding(-2)
    }
}

/// Keeps the label fully opaque while pressed. `.buttonStyle(.plain)` still
/// dims its label on press, which makes the teal stroke + aura on this card
/// look washed-out on tap.
private struct NoDimButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

/// Slow, paused shimmer sweep — sweeps once over ~1.6s, then waits ~3.4s
/// before the next pass. Long dwell keeps it feeling premium rather than
/// frantic. Earlier shimmer iteration on `ShimmeringUpgradeText` was scrapped
/// for being too aggressive on paying users; this card is for *prospects* so
/// a quiet sweep is the right intensity.
private struct ShimmerHeadline: View {
    let text: String

    /// `.idleLeft` — bar parked off-screen left, invisible. Wait period.
    /// `.sweepRight` — bar slides to off-screen right at full opacity (the visible sweep).
    /// `.fadeOut` — instantly drop opacity to 0 while still off-screen right.
    /// Cycle repeats: `.fadeOut` → `.idleLeft` is the long 3.4s "do nothing" stretch.
    private enum Phase: CaseIterable {
        case idleLeft, sweepRight, fadeOut
    }

    var body: some View {
        Text(text)
            .font(.title2.weight(.bold))
            .foregroundStyle(.white)
            .overlay {
                GeometryReader { geo in
                    let width = geo.size.width
                    Rectangle()
                        .fill(
                            LinearGradient(
                                stops: [
                                    .init(color: .clear, location: 0.0),
                                    .init(color: .white.opacity(0.85), location: 0.5),
                                    .init(color: .clear, location: 1.0)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: width * 0.55)
                        .blendMode(.plusLighter)
                        .phaseAnimator(Phase.allCases) { content, phase in
                            content
                                .offset(x: offset(for: phase, width: width))
                                .opacity(phase == .sweepRight ? 1 : 0)
                        } animation: { phase in
                            switch phase {
                            case .sweepRight:  .easeInOut(duration: 1.6)
                            case .fadeOut:     .linear(duration: 0)
                            case .idleLeft:    .linear(duration: 3.4)
                            }
                        }
                }
                .mask(
                    Text(text)
                        .font(.title2.weight(.bold))
                )
            }
            .allowsHitTesting(false)
    }

    private func offset(for phase: Phase, width: CGFloat) -> CGFloat {
        switch phase {
        case .idleLeft:                return -width
        case .sweepRight, .fadeOut:    return width
        }
    }
}

#Preview {
    PaywallButtonView()
        .environment(SonosService())
        .padding()
        .background(Color.black)
}
