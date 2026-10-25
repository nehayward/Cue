import SubscriptionKit
import SwiftUI

/// Settings ▸ About: the newsletter, Last.fm's credit, and the version and
/// this install's ID for support.
struct AboutSettingsScreen: View {
    @Environment(SubscriptionService.self) private var subscriptionService
    @Environment(Router.self) private var router: Router?

    var body: some View {
        Form {
            Section {
                LabeledContent("Version", value: OSEnvironment.versionInfo)
                LabeledContent("ID") {
                    Text(subscriptionService.userID)
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Section {
                Button {
                    HapticManager.shared.fireHaptic(.buttonPress)
                    router?.presentedSheet = .newsletter
                } label: {
                    Label {
                        HStack {
                            Text("Newsletter")
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    } icon: {
                        SettingsIcon(symbol: "envelope.fill", colors: [Color(red: 0.20, green: 0.62, blue: 0.70), Color(red: 0.10, green: 0.45, blue: 0.55)])
                    }
                }
                .tint(.primary)

                Link(destination: URL(string: "https://www.last.fm")!) {
                    Label {
                        HStack {
                            Text("Powered by Audioscrobbler")
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: "arrow.up.forward")
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        SettingsIcon(symbol: "music.note.list", colors: [Color(red: 0.85, green: 0.15, blue: 0.15), Color(red: 0.65, green: 0.1, blue: 0.1)])
                    }
                }
                .tint(.primary)
            }
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
        .fontDesign(.rounded)
    }
}
