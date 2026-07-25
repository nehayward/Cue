import SwiftUI
import CloudStorage
import SonosKit

struct ConnectByIPScreen: View {
    @Environment(SonosService.self) private var sonosService
    @Environment(AlertService.self) private var alertService

    /// The user's explicit speaker choice — NOT `sonos_ip`, which the reconnect
    /// race rewrites to whichever speaker answered first, making the tick jump
    /// off the speaker that was just tapped.
    @CloudStorage("sonos_preferred_speaker_ip") var preferredSpeakerIP = ""

    @State private var manualConnectIPAddress: String = ""
    @State private var errorMessage: String?
    @State private var isValidIP: Bool = false
    @State private var deviceFound: Bool = false
    @State private var probeTask: Task<Void, Never>?
    @State private var isConnecting: Bool = false
    @State private var isProbing: Bool = false
    /// Bumped once a speaker choice actually lands, so the haptic confirms the
    /// result rather than firing on tap and buzzing for a change that failed.
    @State private var selectionFeedback: Int = 0
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
        .sensoryFeedback(.success, trigger: selectionFeedback)
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
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    Task {
                        guard let device = await sonosService.setPriorityDevice() else { return }
                        selectionFeedback += 1
                        announceConnection(to: device.name)
                    }
                } label: {
                    Label("Choose Best Speaker", systemImage: "wand.and.stars")
                        .fontWeight(.semibold)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.accent)

                Text("Prefers LAN-connected and mains-powered speakers, and skips portables like Roam or Move")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
        } header: {
            Text("How Clic Connects")
        } footer: {
            Text("One speaker answers Clic's system-wide requests — how your speakers are grouped, album artwork, and your library, favorites and playlists. Play, pause and volume go straight to the speaker you're controlling. Picking one that's wired and always awake keeps everything else quick.")
        }
    }

    // MARK: - Speaker picker

    private var speakerSection: some View {
        Section {
            ForEach(sonosService.sortedRooms) { room in
                Button {
                    Task {
                        await sonosService.setStaticIP(ip: room.ip)
                        selectionFeedback += 1
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

                        if preferredSpeakerIP == room.ip {
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

                HStack(spacing: 8) {
                    TextField("192.168.1.100", text: $manualConnectIPAddress)
                        .keyboardType(.numbersAndPunctuation)
                        .onChange(of: manualConnectIPAddress, initial: true) {
                            validateIP(manualConnectIPAddress)
                        }

                    // No ✕ here: the field already has the system clear button,
                    // and a second red circle-with-x beside it read as a second
                    // control rather than as validation feedback. Wrongness is
                    // shown by tinting the field instead.
                    if isProbing {
                        ProgressView()
                            .controlSize(.small)
                    } else if deviceFound {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .imageScale(.medium)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(showsInvalidIP ? Color.red.opacity(0.12) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(showsInvalidIP ? Color.red.opacity(0.5) : Color.clear, lineWidth: 1)
                )
                .animation(.smooth(duration: 0.2), value: showsInvalidIP)

                if showsInvalidIP {
                    Text("That doesn't look like an IP address — four numbers separated by dots, like 192.168.1.100")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                } else if isValidIP && !deviceFound && !isProbing {
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

    /// Whether to style the field as wrong. Deliberately NOT `!isValidIP`: while
    /// someone is typing, "192." is an incomplete address, not a bad one, and
    /// flagging it on the way to a valid entry is what made the field feel like
    /// it was rejecting every keystroke.
    private var showsInvalidIP: Bool {
        !manualConnectIPAddress.isEmpty && !isPartialIP(manualConnectIPAddress)
    }

    /// True while the text could still grow into a valid IPv4 address — at most
    /// four dot-separated groups, each 1–3 digits and ≤ 255, with only the final
    /// group allowed to be empty (the user just typed a dot).
    private func isPartialIP(_ ip: String) -> Bool {
        let parts = ip.components(separatedBy: ".")
        guard parts.count <= 4 else { return false }
        for (index, part) in parts.enumerated() {
            if part.isEmpty {
                guard index == parts.count - 1 else { return false }
                continue
            }
            guard part.count <= 3,
                  part.allSatisfy(\.isNumber),
                  let value = Int(part), value <= 255 else {
                return false
            }
        }
        return true
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
            isProbing = true
            probeTask = Task {
                // Probe reachability only — do NOT adopt/pin a household from a
                // transient, still-being-typed IP. Adoption happens on an explicit
                // tap (Connect, a speaker row, or Choose Best Speaker).
                let groups = (try? await sonosService.getGroups(with: ip)) ?? []
                // A superseded probe leaves the flags alone: the newer validateIP
                // call already owns them.
                guard !Task.isCancelled, ip == manualConnectIPAddress else { return }
                deviceFound = !groups.isEmpty
                isProbing = false
            }
        } else {
            deviceFound = false
            isProbing = false
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
            selectionFeedback += 1
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
