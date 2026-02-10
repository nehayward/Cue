import CloudStorage
import SwiftUI
import SonosKitMini

struct PreferenceScreen: View {
    @CloudStorage("com.clic.autoLaunchNowPlaying") private var autoLaunchNowPlaying: Bool = true
    @CloudStorage("sonos_ip") var sonosIP = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(isOn: $autoLaunchNowPlaying) {
                        Text("Auto Launch Group")
                    }
                    .tint(.accent)
                } footer: {
                    Text("Instantly jump to the group currently playing.")
                }
                
                Section {
                    NavigationLink {
                        HouseholdScreen()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "house.fill")
                                .font(.caption)
                                .foregroundStyle(.white)
                                .frame(width: 28, height: 28)
                                .background(.blue, in: RoundedRectangle(cornerRadius: 7))
                            Text("Discover Systems")
                        }
                    }
                } footer: {
                    Text("Find your Sonos system if it wasn't detected automatically.")
                }

                Section {
                    if let group = SonosMiniService.shared.sorted.first(where: { $0.ip == sonosIP }) {
                        VStack(alignment: .leading) {
                            Text(group.nameWithCount)
                                .foregroundStyle(.primary)
                            Text(group.ip)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text("Current Sonos IP \(sonosIP)")
                    }
                } header: {
                    Text("Hub")
                }

                VStack(alignment: .center) {
                    Text("Version **\(OSEnvironment.versionInfo)**")
                    Text("Build **\(OSEnvironment.buildNumber)**")
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }
        }
    }
}


//#Preview {
//    PreferenceScreen()
//        .withEnvironments()
//        .onAppear {
//            SonosService.shared.monitor()
//        }
//}

