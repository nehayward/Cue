import Foundation
import CommonCrypto
import CryptoKit


@MainActor
@Observable
final class SpotifySimple {
    let clientID = "6569f80e8a74407392c62894a4c10d8c"
    let redirectURI = "testing://authorize"
    var codeVerifier: String = ""
    var code: String = ""
    var isAuthorized: Bool = false

    func authorize() -> URL {
        let authorizationURLString = "https://accounts.spotify.com/authorize" +
        "?client_id=\(clientID)" +
        "&response_type=code" +
        "&redirect_uri=\(redirectURI)" +
        "&state=\(generateRandomString(length: 16))" +
        "&show_dialog=false" +
        "&scope=user-read-private playlist-read-private playlist-read-collaborative user-library-read user-library-modify"

        guard let authorizationURL = URL(string: authorizationURLString) else {
            fatalError("Failed to create authorization URL")
        }

        return authorizationURL
    }

    // Helper function to generate a random string
    func generateRandomString(length: Int) -> String {
        let characters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        return String((0..<length).map { _ in characters.randomElement()! })
    }
}
