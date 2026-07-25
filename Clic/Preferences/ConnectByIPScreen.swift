import SwiftUI
import CloudStorage
import SonosKit

struct ConnectByIPScreen: View {
    @Environment(SonosService.self) private var sonosService
    @Environment(AlertService.self) private var alertService

    @CloudStorage("sonos_ip") var sonosIP = ""

    @State private var manualConnectIPAddress: String = ""
    @State private var errorMessage: String?
    @State private var isValidIP: Bool = false
    @State private var deviceFound: Bool = false
    @State private var probeTask: Task<Void, Never>?
    @State private var isConnecting: Bool = false
    /// Manual IP entry is a recovery path, so it stays collapsed — unless nothing
    /// was discovered, in which case it's the only way forward and leads instead.
    @State private var showManualEntry: Bool = false

    // IPv4 regex pattern
    private let ipv4Pattern = #"^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$"#

    var body: some View {
        Form {
            automaticSection

            if !sonosService.sortedRooms.isEmpty {
                speakerSection
            }

            manualEntrySection

            if let error = errorMessage {
                Section {
                    Text(error)
                        .foregroundColor(.red)
                }
            }
        }
        .navigationTitle("Connectivity")
        .headerProminence(.increased)
        .fontDesign(.rounded)
        .onAppear {
            // Nothing to pick from means discovery found nothing — open the manual
            // path rather than showing an empty screen with a hidden way out.
            if sonosService.sortedRooms.isEmpty {
                showManualEntry = true
            }
        }
    }

    // MARK: - Automatic

    private var automaticSection: some View {
        Section {
            Button {
                Task {
                    guard let device = await sonosService.setPriorityDevice() else { return }
                    announceConnection(to: device.name)
                }
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Choose Best Speaker")
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                        Text("Prefers LAN-connected and mains-powered speakers, and skips portables like Roam or Move")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } icon: {
                    Image(systemName: "wand.and.stars")
                        .foregroundStyle(.accent)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } header: {
            Text("How Clic Connects")
        } footer: {
            Text("Clic sends its commands through one speaker, which passes them on to the rest of your system. Choosing one that's wired and always awake makes the whole app more responsive.")
        }
    }

    // MARK: - Speaker picker

    private var speakerSection: some View {
        Section {
            ForEach(sonosService.sortedRooms) { room in
                Button {
                    Task {
                        await sonosService.setStaticIP(ip: room.ip)
                        announceConnection(to: room.name)
                    }
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(room.name)
                                .foregroundStyle(.primary)
                            HStack(spacing: 0) {
                                if let info = room.info {
                                    Text("\(info.modelDisplayName) • ")
                                }
                                Text(room.ip)
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 8)

                        connectionBadge(for: room)

                        if sonosIP == room.ip {
                            Image(systemName: "checkmark")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.green)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("Connect Through")
        } footer: {
            Text("Tap a speaker to connect through it. LAN means it's wired to your router — those stay reachable when other speakers sleep, so they're the most reliable choice.")
        }
    }

    // MARK: - Manual IP entry

    private var manualEntrySection: some View {
        Section {
            DisclosureGroup(isExpanded: $showManualEntry) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("1. Open the Sonos app")
                    Text("2. Go to Settings › Manage › About My System")
                    Text("3. Find the IP address listed under one of your speakers — prefer one that's wired to your router (LAN) or mains-powered, not a portable like Move or Roam")
                    Text("4. Enter that address below, then tap Connect once the speaker is found")
                }
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)

                HStack {
                    TextField("192.168.1.100", text: $manualConnectIPAddress)
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

                if !isValidIP && !manualConnectIPAddress.isEmpty {
                    Text("Invalid IP address format")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if isValidIP && !deviceFound && !manualConnectIPAddress.isEmpty {
                    Text("No Sonos system found at this IP address")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if isValidIP && deviceFound {
                    Button {
                        connectToManualIP()
                    } label: {
                        if isConnecting {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Connect")
                                .bold()
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(isConnecting)
                }
            } label: {
                Text("Can't find your speakers?")
                    .fontWeight(.medium)
            }
        } footer: {
            Text("Enter a speaker's address by hand when Clic can't find your system on its own — on networks that block device discovery, or to reach a system Clic hasn't seen before.")
        }
    }

    // MARK: - Pieces

    /// "LAN" when the speaker reports a wired link, "Wi-Fi" when it reports a
    /// wireless one. Shows nothing when it reports neither — some older S1
    /// players omit both attributes from ZoneGroupState, and a missing `EthLink`
    /// would otherwise read as "this speaker is on Wi-Fi", which is exactly the
    /// claim this badge exists to get right.
    @ViewBuilder
    private func connectionBadge(for room: Room) -> some View {
        if room.ethernetEnabled {
            badge("LAN", systemImage: "cable.connector", tint: .green)
        } else if room.wifiEnabled {
            badge("Wi-Fi", systemImage: "wifi", tint: .secondary)
        }
    }

    private func badge(_ title: String, systemImage: String, tint: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: systemImage)
            Text(title)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(tint)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(tint.opacity(0.12), in: Capsule())
    }

    // MARK: - Actions

    /// Every path on this screen ends in the same operation — pinning the speaker
    /// Clic talks to — so they all report it the same way.
    private func announceConnection(to name: String) {
        alertService.showAlert(with: "Now connecting through \(name)", imageName: "checkmark.circle.fill")
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
                // tap (Connect, a speaker row, or Choose Best Speaker).
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
            announceConnection(to: sonosService.sortedRooms.first(where: { $0.ip == ip })?.name ?? ip)
        }
    }
}

#Preview {
    NavigationStack {
        ConnectByIPScreen()
    }
    // The screen reads AlertService as well as SonosService; the shared
    // environment set supplies both (the old preview injected only the latter).
    .withEnvironments()
}
