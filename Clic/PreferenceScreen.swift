import SwiftUI
import SonosKit

struct PreferenceScreen: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Environment(SubscriptionService.self) var superMember: SubscriptionService

    @State var showPaywall = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        showPaywall = true
                    } label: {
                        Text("Subscribe")
                            .font(.callout)
                            .bold()
                            .foregroundStyle(.ultraThickMaterial)
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                    .buttonStyle(.plain)
                    .fontDesign(.rounded)
                    .background(Color.accentColor.gradient)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .sensoryFeedback(.success, trigger: showPaywall)
                } header: {
                    Text("Subscription")
                        .foregroundStyle(.accent.gradient)
                        .padding(.bottom)
                }
                .headerProminence(.increased)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())


                Section {
                    Text(!sonosService.sonosPulse.isCancelled ? "Monitoring" : "")
                } header: {
                    Text("Sonos System")
                }

            }
            .sheet(isPresented: $showPaywall) {
                PaywallScreen()
            }
            .navigationTitle("Settings")
        }
        .task {
            guard ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" else { return }
            sonosService.monitor()
        }
    }
}


#Preview {
    PreferenceScreen()
        .environment(SonosService())
        .environment(SubscriptionService())
}

