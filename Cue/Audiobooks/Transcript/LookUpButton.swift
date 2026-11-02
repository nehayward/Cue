import SwiftUI

/// A word looked up before, to look up again: a tap opens its definition,
/// the system dictionary's page over whatever is up on iPhone and iPad
/// (`DictionaryPresenter`), and on the Mac, where that page only opens
/// Dictionary, Cue's own in a popover (`DictionaryDefinitionView`).
struct LookUpButton<Label: View>: View {
    let term: String
    @ViewBuilder let label: Label

    @State private var showsDefinition = false

    var body: some View {
        Button {
            HapticManager.shared.fireHaptic(.selection)
#if targetEnvironment(macCatalyst)
            showsDefinition = true
#else
            DictionaryPresenter.present(term)
#endif
        } label: {
            label
        }
        .accessibilityHint("Shows its meaning")
#if targetEnvironment(macCatalyst)
        .popover(isPresented: $showsDefinition) {
            DictionaryDefinitionView(term: term)
                .frame(width: 380, height: 460)
        }
#endif
    }
}
