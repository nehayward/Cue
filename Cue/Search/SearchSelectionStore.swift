import Defaults
import Foundation
import Observation
import SonosKit

/// The services Search looks in (`AppStorageKeys.selectedSearchServices`),
/// observed rather than held in `@AppStorage`. A view holding `@AppStorage`
/// re-runs on every UserDefaults write, of any key and iOS's own included,
/// and comes back as a new view each time `CueApp` re-runs (every tab
/// switch, every trip to the background and back), so the Search tab
/// rebuilt itself whole, hidden or not, right as a return to Cue was
/// being scrolled. Written only when it changes.
@MainActor
@Observable
final class SearchSelectionStore {
    static let shared = SearchSelectionStore()

    var selection: SelectedSearchServices {
        didSet {
            guard selection != oldValue else { return }
            UserDefaults.standard.set(selection.rawValue, forKey: AppStorageKeys.selectedSearchServices)
        }
    }

    private init() {
        selection = UserDefaults.standard.string(forKey: AppStorageKeys.selectedSearchServices)
            .map(SelectedSearchServices.init(rawValue:)) ?? SelectedSearchServices()
    }
}
