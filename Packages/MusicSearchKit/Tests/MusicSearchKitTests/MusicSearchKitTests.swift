import XCTest
@testable import MusicSearchKit

final class MusicSearchKitTests: XCTestCase {
    func testSearchForCryYourHeartOutSong() throws {
        let cryYourHeartOutQueryURL = Bundle.module.url(forResource: "cryYourHeartOutSearch", withExtension: "json")!
        let musicSearch = try JSONDecoder().decode(ItunesMusicSearch.self, from: Data(contentsOf: cryYourHeartOutQueryURL))
        XCTAssertEqual(musicSearch.results.count, 50)
        XCTAssertEqual(musicSearch.results.first?.trackName, "Cry Your Heart Out")
    }

    func testSpotifyDecode() throws {
        let duaLipa = Bundle.module.url(forResource: "duaLipaSpotifyPlaylistsResponse", withExtension: "json")!
        let decoder =  JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let spotifySearch = try XCTUnwrap(decoder.decode(SpotifyResult.self, from: Data(contentsOf: duaLipa)))
        let playlists = try XCTUnwrap(spotifySearch.playlists)
        XCTAssertEqual(playlists.items.count, 20)
    }

//    func testPlexDecode() throws {
//        let dance = Bundle.module.url(forResource: "plex_search_dance", withExtension: "xml")!
//        let data = try Data(contentsOf: dance)
//        let tracks = PlexParser().parseXML(xmlData: data)
//    }

//    func testSpotifyAPITokenRefreshHandler() async throws {
//        // Create a mock token refresh handler
//        let mockHandler = MockTokenRefreshHandler()
//        
//        // Create SpotifyAPI with the mock handler
//        let spotifyAPI = SpotifyAPI(tokenRefreshHandler: mockHandler)
//        
//        // Test that the API can handle token refresh responses
//        let refreshResponse = SpotifyTokenRefreshResponse(
//            authToken: "new_auth_token",
//            privateKey: "new_private_key",
//            userIdHashCode: "user_hash",
//            accountTier: "premium",
//            nickname: "test_user"
//        )
//        
//        // This should not throw since we have a handler
//        try await spotifyAPI.handleTokenRefreshResponse(
//            householdId: "test_household",
//            refreshResponse: refreshResponse
//        )
//        
//        // Verify the mock handler was called
//        XCTAssertTrue(mockHandler.handleTokenRefreshCalled)
//        XCTAssertEqual(mockHandler.lastHouseholdId, "test_household")
//        XCTAssertEqual(mockHandler.lastRefreshResponse?.authToken, "new_auth_token")
//    }
    
//    func testSpotifyAPIWithoutTokenHandler() async throws {
//        // Create SpotifyAPI without a token refresh handler
//        let spotifyAPI = SpotifyAPI(tokenRefreshHandler: nil)
//        
//        // This should throw AuthError.missingTokenHandler when trying to make a request
//        do {
//            let _: SpotifyUser = try await spotifyAPI.loadAuthorized(URL(string: "https://api.spotify.com/v1/users/test")!)
//            XCTFail("Expected AuthError.missingTokenHandler to be thrown")
//        } catch AuthError.missingTokenHandler {
//            // Expected error
//        } catch {
//            XCTFail("Unexpected error: \(error)")
//        }
//    }
}

// Mock token refresh handler for testing
private class MockTokenRefreshHandler: TokenRefreshHandler {
    var handleTokenRefreshCalled = false
    var lastHouseholdId: String?
    var lastRefreshResponse: SpotifyTokenRefreshResponse?
    var shouldReturnCredentials = true
    
    func handleTokenRefresh(householdId: String, token: String, key: String) async throws {
        handleTokenRefreshCalled = true
        lastHouseholdId = householdId
    }
    
    func getCredentials() async throws -> Credentials? {
        if shouldReturnCredentials {
            return Credentials(
                deviceId: "test_device",
                householdId: "test_household",
                token: "test_token",
                key: "test_key"
            )
        }
        return nil
    }
}
