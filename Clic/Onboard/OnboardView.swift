import CloudStorage
import VibesDS
import SwiftUI
import SonosKit
import RevenueCatUI
import Defaults

struct OnboardView: View {
    @Environment(SonosService.self) var sonosService
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: Int = 0
    @AppStorage(GroupStorageKeys.hasOnboarded, store: GroupStorageKeys.storage) private var hasOnboarded: Bool = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    welcomeView(proxy: proxy)
                        .id(0)  // Add this
                    servicesView(proxy: proxy)  // Pass proxy here
                        .id(1)  // Add this
                    paywallView(proxy: proxy)  // Add this view and pass proxy
                        .id(2)  // Add this
                }
                .scrollTargetLayout()
                .fontDesign(.rounded)
            }
            .scrollTargetBehavior(.paging)
            .scrollIndicators(.hidden)
            .scrollContentBackground(.hidden)
            .scrollDisabled(true)
        }.onDisappear {
            hasOnboarded = true
        }
    }
    
    func welcomeView(proxy: ScrollViewProxy) -> some View {
        VStack {
            Image("clic.icon")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: 200)
                .foregroundStyle(.accent.gradient)

            Text("Welcome, let's get you set up!")
                .font(.largeTitle)
            Text("Please ensure you're on the same network as your Sonos Devices")
            
            Button {
                sonosService.monitor()
                withAnimation {
                    proxy.scrollTo(1, anchor: .center)
                }
            } label: {
                Text("Discover")
                    .bold()
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
        }
        .padding()
        .containerRelativeFrame([.horizontal, .vertical])
    }
    
    func servicesView(proxy: ScrollViewProxy) -> some View {
        VStack {
            Text("Services")
                .font(.title)
            Text(sonosService.sorted.count, format: .number)
            Button {
                withAnimation {
                    proxy.scrollTo(2, anchor: .center)
                }
            } label: {
                Text("Next")
                    .bold()
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
        }
        .containerRelativeFrame([.horizontal, .vertical])
    }
    
    func paywallView(proxy: ScrollViewProxy) -> some View {
        VStack {
            ClicPaywall()
            
            Button {
                dismiss()
            } label: {
                Text("Finish")
                    .bold()
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
        }
        .padding()
        .containerRelativeFrame([.horizontal, .vertical])
    }
}

#Preview {
    Text("Onboard")
        .sheet(isPresented: .constant(true)) {
            OnboardView()
                .withEnvironments()
        }
}
