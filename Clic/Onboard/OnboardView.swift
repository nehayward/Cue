import CloudStorage
import VibesDS
import SwiftUI
import SonosKit
import RevenueCatUI

struct OnboardView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: Int = 1
    @State private var phase = 1.0

    var body: some View {
        NavigationStack {
            TabView(selection: $selectedTab) {
                VStack {
                    Text("Welcome lets get you set up!")
                        .font(.title)

                    Text("First, tap the button below to allow Clic to discover Sonos devices")

                    Button {
                        selectedTab += 1
                    } label: {
                        Text("Discover")
                            .bold()
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                }
                .padding()
                .tag(1)
                
                ClicPaywall()
                    .tag(2)
                //            PaywallView()
            }
            .animation(.bouncy, value: selectedTab)
            .tabViewStyle(.page(indexDisplayMode: .always))
            .overlay(alignment: .bottom) {
                VStack(spacing: 12) {
                    Button {
                        selectedTab += 1
                    } label: {
                        Image(systemName: "arrow.forward")
                            .font(.body)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    Button {
                        dismiss()
                    } label: {
                        Text("Skip")
                            .font(.caption)
                    }.opacity(0.4)
                }
            }
            .fontDesign(.rounded)
        }
    }
}

#Preview {
    OnboardView()
}
