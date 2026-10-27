@testable import MusicSearchKit
import XCTest

final class AudiobookshelfSignOnTests: XCTestCase {
    /// RFC 7636, Appendix B.
    func testChallengeIsTheVerifiersHash() {
        let proof = AudiobookshelfPKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk", state: "s")
        XCTAssertEqual(proof.challenge, "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    func testEachSignInIsItsOwn() {
        let first = AudiobookshelfPKCE()
        let second = AudiobookshelfPKCE()
        XCTAssertNotEqual(first.verifier, second.verifier)
        XCTAssertNotEqual(first.state, second.state)
        // Within the lengths RFC 7636 allows, in its alphabet.
        XCTAssert((43...128).contains(first.verifier.count))
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        XCTAssert(first.verifier.unicodeScalars.allSatisfy(allowed.contains))
    }

    func testStatusNamesTheWaysIn() throws {
        let json = """
        { "app": "audiobookshelf", "serverVersion": "2.37.1", "isInit": true, "language": "en-us",
          "authMethods": ["local", "openid"],
          "authFormData": { "authLoginCustomMessage": null, "authOpenIDButtonText": "Login with Authentik", "authOpenIDAutoLaunch": false } }
        """
        let status = try JSONDecoder().decode(AudiobookshelfStatus.self, from: Data(json.utf8))
        XCTAssertEqual(status.authMethods, ["local", "openid"])
        XCTAssertEqual(status.authFormData?.authOpenIDButtonText, "Login with Authentik")
    }
}
