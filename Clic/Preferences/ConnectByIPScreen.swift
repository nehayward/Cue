import SwiftUI
import CloudStorage
import SonosKit

struct ConnectByIPScreen: View {
    @Environment(SonosService.self) private var sonosService
    @Environment(AlertService.self) private var alertService
    
    @CloudStorage("sonos_ip") var sonosIP = ""

    @State private var manualConnectIPAddress: String = ""
    @State private var discoveredIPs: [String] = []
    @State private var isSearching: Bool = false
    @State private var errorMessage: String?
    @State private var isValidIP: Bool = false
    @State private var deviceFound: Bool = false
    @State private var probeTask: Task<Void, Never>?
    @State private var isConnecting: Bool = false
    
    // IPv4 regex pattern
    private let ipv4Pattern = #"^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$"#

    var body: some View {
        Form {
            Section(header: Text("How to find IP of Device")) {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("1. Open Sonos App")
                        Text("2. Go to Settings - Manage - About My System")
                        Text("3. Input one of the (preferably non-portable and lan connected) speaker IP address. i.e 192.167.1.100")
                    }
                    .font(.subheadline)
                }
                .padding(.vertical, 8)
            }
            
            Section {
                HStack {
                    TextField("192.168.2.1", text: $manualConnectIPAddress)
                        .keyboardType(.numbersAndPunctuation)
                        .onChange(of: manualConnectIPAddress, initial: true) {
                            validateIP(manualConnectIPAddress)
                        }
                    
                    if !manualConnectIPAddress.isEmpty {
                        Image(systemName: isValidIP ? (deviceFound ? "checkmark.circle.fill" : "checkmark.circle") : "xmark.circle.fill")
                            .foregroundStyle(isValidIP ? (deviceFound ? .green : .secondary) : .red)
                            .imageScale(.medium)
                    }
                }
                if isValidIP && deviceFound {
                    Button {
                        connectToManualIP()
                    } label: {
                        if isConnecting {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Connect to This Device")
                                .bold()
                                .fontDesign(.rounded)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(isConnecting)
                }
            } header: {
                Text("Enter Device IP Address")
            } footer: {
                if !isValidIP && !manualConnectIPAddress.isEmpty {
                    Text("Invalid IP Address Format")
                        .foregroundStyle(.secondary)
                } else if isValidIP && !deviceFound && !manualConnectIPAddress.isEmpty {
                    Text("No Sonos system found at this IP address")
                        .foregroundStyle(.secondary)
                }
            }
            
            Section {
                VStack(spacing: 8) {
                     Button {
                         Task {
                             guard let device = await sonosService.setPriorityDevice() else { return }
                             alertService.showAlert(with: "Assigning Priority to \(device.name)", imageName: "1.circle.fill")
                         }
                     } label: {
                         Text("Set Priority Device")
                             .bold()
                             .fontDesign(.rounded)
                             .padding(.vertical, 8)
                             .frame(maxWidth: .infinity)
                     }
                     .buttonStyle(.bordered)
                     .tint(.accent)

                     Text("Prefers wired devices, newer models, and excludes portable speakers like Roam, Move or Play.")
                         .font(.caption2)
                         .foregroundStyle(.secondary)
                         .multilineTextAlignment(.leading)
                 }
                 .listRowBackground(Color.clear)
                 .listRowInsets(EdgeInsets())
            }
            
            ForEach(sonosService.sortedRooms) { room in
                Button {
                    Task {
                        await sonosService.setStaticIP(ip: room.ip)
                        alertService.showAlert(with: "Assigning Priority to \(room.name)", imageName: "1.circle.fill")
                    }
                } label: {
                    Label {
                        Text(room.name)
                        HStack(spacing: 0) {
                            if let info = room.info {
                                Text("\(info.modelDisplayName) • ")
                            }
                            Text(room.ip)
                                .foregroundStyle(manualConnectIPAddress == room.ip ? .green : .secondary)
                        }
                    } icon: {
                        Image(systemName: "circle")
                            .foregroundStyle(.accent)
                            .transition(.scale.combined(with: .opacity))
                            .symbolVariant(sonosIP == room.ip  ? .fill : .none)
                    }
                }
                .tint(.primary)
            }
            
            if let error = errorMessage {
                Section {
                    Text(error)
                        .foregroundColor(.red)
                }
            }
        }
        .headerProminence(.increased)
        .fontDesign(.rounded)
    }
    
    private func validateIP(_ ip: String) {
        let regex = try? NSRegularExpression(pattern: ipv4Pattern)
        let range = NSRange(location: 0, length: ip.utf16.count)
        isValidIP = regex?.firstMatch(in: ip, range: range) != nil

        // Each keystroke re-validates; cancel the in-flight probe so a slow
        // response for a prefix IP (e.g. "…1.1" while typing "…1.10") can't land
        // after the full address's probe and overwrite a good result.
        probeTask?.cancel()
        if isValidIP {
            probeTask = Task {
                // Probe reachability only — do NOT adopt/pin a household from a
                // transient, still-being-typed IP. Adoption happens on an explicit
                // tap (Connect, a room row, or Set Priority Device).
                let groups = (try? await sonosService.getGroups(with: ip)) ?? []
                guard !Task.isCancelled, ip == manualConnectIPAddress else { return }
                deviceFound = !groups.isEmpty
            }
        } else {
            deviceFound = false
        }
    }

    private func connectToManualIP() {
        let ip = manualConnectIPAddress
        isConnecting = true
        Task {
            defer { isConnecting = false }
            // Adopts the device's household (S1 or S2) and pins the IP, so a
            // system on another generation than the active one becomes selectable.
            await sonosService.setStaticIP(ip: ip)
            let name = sonosService.sortedRooms.first(where: { $0.ip == ip })?.name ?? ip
            alertService.showAlert(with: "Connected to \(name)", imageName: "checkmark.circle.fill")
        }
    }
}

#Preview {
    NavigationStack {
        ConnectByIPScreen()
    }
    .environment(SonosService.shared)
}
