import CryptoKit
import Foundation

/// The proof a single sign-on carries (PKCE, RFC 7636): a secret made for
/// one sign-in, whose hash goes with its first step and the secret itself
/// with its last, so a code caught on its way back to Cue is no use to
/// anyone else. `state` names the sign-in, so an answer to another isn't
/// taken for this one's.
struct AudiobookshelfPKCE: Sendable {
    let verifier: String
    let challenge: String
    let state: String

    init() {
        // 48 random bytes are 64 characters: within the 43 to 128 allowed.
        self.init(verifier: Self.random(byteCount: 48), state: Self.random(byteCount: 24))
    }

    init(verifier: String, state: String) {
        self.verifier = verifier
        self.state = state
        challenge = Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    /// Where the server sends the sign-in back to: the scheme its own apps
    /// use, which a server allows unless its admin has said otherwise, so
    /// Cue needs nothing set up on it. The web sign-in session catches it,
    /// whichever app has the scheme.
    static let redirectURI = "audiobookshelf://oauth"
    static let callbackScheme = "audiobookshelf"

    private static func random(byteCount: Int) -> String {
        var generator = SystemRandomNumberGenerator()
        return base64URL(Data((0..<byteCount).map { _ in UInt8.random(in: .min ... .max, using: &generator) }))
    }

    /// Base64 with the URL-safe alphabet and no padding.
    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
