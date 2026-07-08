import XCTest
import MusicSearchKit
@testable import SonosKit

final class SelectedSearchServicesTests: XCTestCase {

    // MARK: Construction

    func testEmptySelectionDefaultsToApple() {
        XCTAssertEqual(SelectedSearchServices().services, [.apple])
        XCTAssertEqual(SelectedSearchServices(rawValue: "").services, [.apple])
        XCTAssertEqual(SelectedSearchServices(rawValue: "notaservice").services, [.apple])
    }

    func testInitCapsAtMaxCountAndDropsDuplicates() {
        let selection = SelectedSearchServices([.spotify, .spotify, .apple, .library, .plex])
        XCTAssertEqual(selection.services, [.spotify, .apple, .library])
        XCTAssertTrue(selection.isAtLimit)
    }

    func testRawValueRoundTripPreservesOrder() {
        let selection = SelectedSearchServices([.plex, .apple, .spotify])
        XCTAssertEqual(SelectedSearchServices(rawValue: selection.rawValue), selection)
        XCTAssertEqual(selection.primary, .plex)
    }

    // MARK: Toggle rules

    func testToggleAddsUpToLimitThenIgnores() {
        var selection = SelectedSearchServices([.apple])
        selection.toggle(.spotify)
        selection.toggle(.library)
        XCTAssertEqual(selection.services, [.apple, .spotify, .library])
        selection.toggle(.plex)
        XCTAssertEqual(selection.services, [.apple, .spotify, .library], "at the limit, new services are ignored")
    }

    func testToggleRemovesSelectedService() {
        var selection = SelectedSearchServices([.apple, .spotify])
        selection.toggle(.spotify)
        XCTAssertEqual(selection.services, [.apple])
    }

    func testUncheckingPrimaryPromotesNextSelection() {
        var selection = SelectedSearchServices([.apple, .spotify, .library])
        selection.toggle(.apple)
        XCTAssertEqual(selection.primary, .spotify)
        XCTAssertEqual(selection.services, [.spotify, .library])
    }

    func testLastServiceCannotBeRemoved() {
        var selection = SelectedSearchServices([.spotify])
        selection.toggle(.spotify)
        XCTAssertEqual(selection.services, [.spotify])
    }

    func testTuneInIsExclusive() {
        var selection = SelectedSearchServices([.apple, .spotify])
        selection.toggle(.tuneIn)
        XCTAssertEqual(selection.services, [.tuneIn])
    }

    func testLeavingTuneInSelectsTappedServiceAlone() {
        var selection = SelectedSearchServices([.tuneIn])
        selection.toggle(.plex)
        XCTAssertEqual(selection.services, [.plex])
    }

    // MARK: Settings pruning

    func testPruneDropsDisabledServices() {
        var selection = SelectedSearchServices([.apple, .spotify, .library])
        selection.prune(isEnabled: { $0 != .spotify }, fallback: .apple)
        XCTAssertEqual(selection.services, [.apple, .library])
    }

    func testPruneFallsBackWhenEverythingIsDisabled() {
        var selection = SelectedSearchServices([.spotify])
        selection.prune(isEnabled: { _ in false }, fallback: .library)
        XCTAssertEqual(selection.services, [.library])
    }

    func testPruneNoOpsWhenAllEnabled() {
        var selection = SelectedSearchServices([.apple, .spotify])
        let before = selection
        selection.prune(isEnabled: { _ in true }, fallback: .apple)
        XCTAssertEqual(selection, before)
    }
}
