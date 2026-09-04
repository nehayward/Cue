import SwiftUI

extension View {
    /// Greys the view out while `feature` is for sale, and puts the paywall
    /// on a tap — the treatment the Super rows in Settings use. A disabled
    /// row can't open the paywall by itself, so the tap target sits over it,
    /// outside the `.disabled`.
    ///
    /// A remotely disabled feature is greyed with no tap: nothing to sell.
    func gated(_ feature: GatedFeature) -> some View {
        modifier(FeatureGateModifier(feature: feature))
    }

    /// Hides the view unless the feature is available — for a control that
    /// makes no sense greyed, like the Create Scene toolbar button.
    @ViewBuilder
    func onlyIfAvailable(_ feature: GatedFeature) -> some View {
        modifier(FeatureAvailableModifier(feature: feature))
    }
}

private struct FeatureGateModifier: ViewModifier {
    @Environment(FeatureGate.self) private var gate
    @Environment(Router.self) private var router: Router?

    let feature: GatedFeature

    func body(content: Content) -> some View {
        let availability = gate.availability(of: feature)
        content
            .disabled(availability != .available)
            .overlay {
                if availability == .needsSuper {
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .onTapGesture { gate.presentPaywall(via: router ?? .main) }
                        .accessibilityLabel("\(feature.title), requires Cue Super")
                        .accessibilityHint("Opens the Cue Super paywall")
                }
            }
    }
}

private struct FeatureAvailableModifier: ViewModifier {
    @Environment(FeatureGate.self) private var gate

    let feature: GatedFeature

    func body(content: Content) -> some View {
        if gate.isAvailable(feature) {
            content
        }
    }
}

/// The Super badge, shown only while the feature is still something to buy
/// — once subscribed it is noise on every row.
struct FeatureBadge: View {
    @Environment(FeatureGate.self) private var gate

    let feature: GatedFeature

    var body: some View {
        if gate.needsSuper(feature) {
            SuperBadge()
        }
    }
}

#if DEBUG
/// Debug-only: force each gate on or off to see both sides without a
/// purchase. Reachable from the Debug section in Settings.
struct FeatureGateDebugView: View {
    @Environment(FeatureGate.self) private var gate

    private enum Choice: String, CaseIterable, Identifiable {
        case `default`, on, off
        var id: String { rawValue }
        var label: String {
            switch self {
            case .default: "Default"
            case .on: "On"
            case .off: "Off"
            }
        }
    }

    var body: some View {
        List {
            Section {
                ForEach(GatedFeature.allCases) { feature in
                    Picker(selection: binding(for: feature)) {
                        ForEach(Choice.allCases) { choice in
                            Text(choice.label).tag(choice)
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(feature.title)
                            Text(describe(feature))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .pickerStyle(.menu)
                }
            } footer: {
                Text("Default follows the subscription and remote flags. On and Off override that on this device only.")
            }
            Section {
                Button("Clear Overrides", role: .destructive) { gate.clearOverrides() }
                    .disabled(gate.overrides.isEmpty)
            }
        }
        .navigationTitle("GatedFeature Gates")
    }

    private func binding(for feature: GatedFeature) -> Binding<Choice> {
        Binding {
            switch gate.overrides[feature] {
            case .some(true): .on
            case .some(false): .off
            case .none: .default
            }
        } set: { choice in
            switch choice {
            case .default: gate.setOverride(nil, for: feature)
            case .on: gate.setOverride(true, for: feature)
            case .off: gate.setOverride(false, for: feature)
            }
        }
    }

    private func describe(_ feature: GatedFeature) -> String {
        let state = switch gate.availability(of: feature) {
        case .available: "available"
        case .needsSuper: "needs Super"
        case .disabledRemotely: "off remotely"
        }
        return "\(requirementText(feature.requirement)) · \(state)"
    }

    private func requirementText(_ requirement: FeatureGate.Requirement) -> String {
        switch requirement {
        case .free: "Free"
        case .superTier: "Super"
        case let .remoteFlag(flag): "Flag \(flag.rawValue)"
        case let .all(list): list.map(requirementText).joined(separator: " + ")
        }
    }
}
#endif
