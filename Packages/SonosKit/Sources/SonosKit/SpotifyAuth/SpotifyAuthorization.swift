import Foundation
import CommonCrypto
import CryptoKit

// TODO: Next
@MainActor
@Observable
public final class SpotifyAuthorization {
    public static var shared = SpotifyAuthorization()

    let clientID = "6569f80e8a74407392c62894a4c10d8c"
    let redirectURI = "clic://spotifyAuthorize"
    var codeVerifier: String = ""
    var code: String = ""
    var isAuthorized: Bool = false

    public func authorize() -> URL {
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


    public struct SpotifyTokenResponse: Codable {
        public let accessToken: String
        public let tokenType: String
        public let expiresIn: Int
        public let refreshToken: String?
        public let scope: String?
    }

//    {
//      "access_token": "BQDyN9gONIiBf5cikn8W_5wn_oWFIoW_b1CUrVyIIvnowf4SoXkALq_FHJhfKndKd0nQus24VmktP5uze-fAncynaWfklIV_nVW32T7Ph8WMwjF1pIxfHDr5Mkl3GRRK5usHLKowqhELP-XpLHDQ7_3waYPaDwBVNd8hoqz83IZR_3ny_I8cqdaQ3asGQVX2G3rVOv4_12hj7Rc7VK34gY1pV1LUJwc1",
//      "token_type": "Bearer",
//      "expires_in": 3600,
//      "refresh_token": "AQCK-fxIx_WyHeDaS_9Ukb7xl0If7Dyn-3wbxCLzSksmtQDfeT55fIOePGoEwAKn_AtxMsH7i4TpDqHaGSUxoSAmTeiohFxBlXAwANGCTZQ2D9x_LEFh-dR1V0MBJjUYl-c",
//      "scope": "playlist-read-private playlist-read-collaborative user-library-read user-library-modify user-read-private"
//    }

    public func fetchSpotifyToken(code: String, state: String) async throws -> SpotifyTokenResponse {
        let url = URL(string: "https://accounts.spotify.com/api/token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let authString = "6569f80e8a74407392c62894a4c10d8c:215fa39804da4b2c8032cf76bc81107e"
        let authData = authString.data(using: .utf8)!.base64EncodedString()
        request.setValue("Basic \(authData)", forHTTPHeaderField: "Authorization")

        let bodyParameters = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": "clic://spotifyAuthorize",
            "state": state
        ]
        let bodyString = bodyParameters.map { "\($0)=\($1)" }.joined(separator: "&")
        request.httpBody = bodyString.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let tokenResponse = try decoder.decode(SpotifyTokenResponse.self, from: data)
        return tokenResponse
    }
}
