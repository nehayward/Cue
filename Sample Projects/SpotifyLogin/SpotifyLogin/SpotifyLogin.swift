import Foundation
import CommonCrypto


struct Spotify {
    let clientID = "6569f80e8a74407392c62894a4c10d8c"
    let redirectURI = "testing://authorize"

    func authorize() -> URL {
        // Generate a random string for the code verifier (43-128 characters)
        let codeVerifier = generateRandomString(length: 128)
        print("Code Verifier")
        print(codeVerifier)
        print("HERE")

        // Calculate the code challenge
        let codeChallenge = generateCodeChallenge(from: codeVerifier)

        // Construct the authorization URL
        let authorizationURLString = "https://accounts.spotify.com/authorize" +
        "?client_id=\(clientID)" +
        "&response_type=code" +
        "&redirect_uri=\(redirectURI)" +
        "&code_challenge=\(codeChallenge)" +
        "&code_challenge_method=S256" +
        "&scope=user-read-private"

        print(codeChallenge)

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

    // Helper function to generate the code challenge
    func generateCodeChallenge(from codeVerifier: String) -> String {
        var buffer = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        let data = codeVerifier.data(using: .utf8)!
        _ = data.withUnsafeBytes {
            CC_SHA256($0.baseAddress, CC_LONG(data.count), &buffer)
        }
        let hashData = Data(buffer: UnsafeBufferPointer(start: &buffer, count: buffer.count))
        return hashData.base64URLEncodedString()
    }

}

// Extension to handle base64 URL encoding
extension Data {
    func base64URLEncodedString() -> String {
        return base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").trimmingCharacters(in: CharacterSet(charactersIn: "="))
    }
}

