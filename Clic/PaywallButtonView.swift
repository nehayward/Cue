import Analytics
import NukeUI
import SwiftUI
import SonosKit

struct PaywallButtonView: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Environment(Router.self) var router: Router?

    private var features = [
        ("Show All Devices", "Effortlessly manage all your Sonos devices in one place."),
        ("Cross-Platform Experience", "Enjoy seamless control on iPadOS, macOS, and watchOS"),
        ("Live Activities", "Instantly adjust playback and volume from the lock screen."),
        ("Widgets", "Convenient home screen widgets for immediate playback control."),
        ("Apple Watch", "Control your Sonos system with ease from your wrist."),
        ("Scenes", "Group rooms and set ideal volume with a single tap."),
        ("Apple Shortcuts", "Rapidly manage playback using the Shortcuts app.")
    ]

    @State private var title = ""
    @State private var current: Int? = 0
    @State private var count = 0
    @State private var timer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    var body: some View {
        Button {
            HapticManager.shared.fireHaptic(.buttonPress)
            Analytics.shared.track(.viewedPaywall)
            router?.presentedSheet = .paywall
        } label: {
            ScrollView(.horizontal) {
                HStack {
                    ForEach(Array(features.enumerated()), id: \.offset) { index, element in
                        VStack {
                            Text(element.0)
                                .font(.title2)
                                #if os(visionOS)
                                .foregroundStyle(.foreground)
                                #else
                                .foregroundStyle(.foreground)
                                #endif
                            Text(element.1)
                                .lineLimit(2, reservesSpace: true)
                                #if os(visionOS)
                                .foregroundStyle(.foreground)
                                #else
                                .foregroundStyle(.secondary)
                                #endif
                        }
                        .multilineTextAlignment(.center)
                        .containerRelativeFrame([.horizontal])
                        .id(index)
                        .scrollTransition(.animated, axis: .horizontal) { content, phase in
                            content
                                .opacity(phase.isIdentity ? 1.0 : 0.8)
                                .scaleEffect(phase.isIdentity ? 1.0 : 0.8)
                                .blur(radius: phase.isIdentity ? 0 : 8)
                        }
                    }
                }
                .scrollTargetLayout()
            }
            .scrollDisabled(true)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $current)
            .lineLimit(1, reservesSpace: true)
            .fontDesign(.rounded)
            .bold()
            .padding()
            .frame(maxWidth: .infinity)
            .background(.ultraThickMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .fixedSize(horizontal: false, vertical: true)
        }
        .buttonStyle(.plain)
        .buttonBorderShape(.roundedRectangle(radius: 12))
        .onReceive(timer) { _ in
            count += 1
            withAnimation {
                current = count % features.count
            }
        }
    }
}

#Preview {
    PaywallButtonView()
        .environment(SonosService())
}

