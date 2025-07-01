import MusicSearchKit
import XCTest

final class PlexTests: XCTestCase {
    
    // MARK: - Test Properties
    private let plexAPI = PlexAPI.shared
    private let testAccessToken = "5waszmycsG4C-5j-sQL6" // Replace with your actual token
    
    // MARK: - Setup
    override func setUp() async throws {
        // Set the access token for testing
        await MainActor.run {
            PlexAuthenticator.shared.authToken = testAccessToken
        }
    }
    
    // MARK: - Server Tests
    func testGetPlexServers() async throws {
        // Given: A valid access token is set
        
        // When: Getting Plex servers
        let servers = await plexAPI.getPlexServers()
        
        // Then: Should return servers with access tokens
        XCTAssertFalse(servers.isEmpty, "Should return at least one server")
        
        for server in servers {
            XCTAssertNotNil(server.accessToken, "Server should have an access token")
            XCTAssertNotNil(server.name, "Server should have a name")
            XCTAssertNotNil(server.clientIdentifier, "Server should have a client identifier")
            XCTAssertFalse(server.externalURIs.isEmpty, "Server should have external URIs")
            
            print("Server: \(server.name)")
            print("  - Client ID: \(server.clientIdentifier ?? "N/A")")
            print("  - External URIs: \(server.externalURIs)")
            print("  - Access Token: \(server.accessToken ?? "N/A")")
        }
    }
    
    func testGetPlexServersWithInvalidToken() async throws {
        // Given: An invalid access token
        await MainActor.run {
            PlexAuthenticator.shared.authToken = "invalid_token"
        }
        
        // When: Getting Plex servers
        let servers = await plexAPI.getPlexServers()
        
        // Then: Should return empty array
        XCTAssertTrue(servers.isEmpty, "Should return empty array with invalid token")
        
        // Reset token for other tests
        await MainActor.run {
            PlexAuthenticator.shared.authToken = testAccessToken
        }
    }
    
    // MARK: - Library Tests
    func testGetMusicLibraries() async throws {
        PlexAuthenticator.shared.authToken = testAccessToken
        // Given: A valid access token and servers
        let servers = await plexAPI.getPlexServers()
        XCTAssertFalse(servers.isEmpty, "Need at least one server for library tests")
        
        // When: Getting music libraries for each server
        for server in servers {
            let libraries = await plexAPI.getMusicLibraries(server: server)
            
            // Then: Should return music libraries
            print("Server: \(server.name)")
            print("  - Music Libraries: \(libraries.count)")
            
            for library in libraries {
                XCTAssertEqual(library.type, "artist", "Library should be of type 'artist'")
                XCTAssertNotNil(library.key, "Library should have a key")
                XCTAssertNotNil(library.title, "Library should have a title")
                XCTAssertNotNil(library.uuid, "Library should have a UUID")
                
                print("    - Library: \(library.title) (Key: \(library.key))")
            }
        }
    }
    
    func testGetMusicLibrariesWithSpecificServer() async throws {
        // Given: A specific server (first available)
        let servers = await plexAPI.getPlexServers()
        guard let firstServer = servers.first else {
            XCTSkip("No servers available for testing")
            return
        }
        
        // When: Getting music libraries for the specific server
        let libraries = await plexAPI.getMusicLibraries(server: firstServer)
        
        // Then: Should return music libraries
        XCTAssertFalse(libraries.isEmpty, "Should have at least one music library")
        
        print("Testing with server: \(firstServer.name)")
        print("Found \(libraries.count) music libraries:")
        
        for library in libraries {
            print("  - \(library.title) (Type: \(library.type), Key: \(library.key))")
        }
    }
    
    // MARK: - Integration Tests
    func testCompleteWorkflow() async throws {
        // Given: A valid access token
        PlexAuthenticator.shared.authToken = testAccessToken

        // When: Getting servers and then libraries
        let servers = await plexAPI.getPlexServers()
        XCTAssertFalse(servers.isEmpty, "Should have servers")
        
        var totalLibraries = 0
        for server in servers {
            let libraries = await plexAPI.getMusicLibraries(server: server)
            totalLibraries += libraries.count
            
            print("Server '\(server.name)' has \(libraries.count) music libraries")
        }
        
        // Then: Should have libraries across all servers
        XCTAssertGreaterThan(totalLibraries, 0, "Should have at least one music library across all servers")
        print("Total music libraries across all servers: \(totalLibraries)")
    }
    
    // MARK: - Error Handling Tests
    func testGetLibrariesWithNoToken() async throws {
        

        // When: Getting servers
        let servers = await plexAPI.getPlexServers()
        
        // Then: Should return empty array
        XCTAssertTrue(servers.isEmpty, "Should return empty array when no token is set")
        
        // Reset token for other tests
        await MainActor.run {
            PlexAuthenticator.shared.authToken = testAccessToken
        }
    }
    
    func testDecodeServers() async throws {
        let plexResourceServers = Bundle.module.url(forResource: "plexResourceServers", withExtension: "json")
        let plexResourceServerData = try! Data(contentsOf: plexResourceServers!)
        let servers = try JSONDecoder().decode([PlexServer].self, from: plexResourceServerData)
        XCTAssertEqual(servers.count, 9)
    }
    
    // MARK: - Artist Albums Tests
    func testGetArtistAlbums() async throws {
        // Given: A valid access token and a known artist key
        PlexAuthenticator.shared.authToken = testAccessToken
        
        // Use a known artist key (Dua Lipa from the example)
        let artistKey = "1695"
        
        // When: Getting artist albums
        let albumHubs = await plexAPI.getArtistAlbums(key: artistKey)
        
        // Then: Should return album hubs
        XCTAssertNotNil(albumHubs, "Should return album hubs")
        
        if let hubs = albumHubs {
            XCTAssertFalse(hubs.isEmpty, "Should have at least one album hub")
            
            print("Found \(hubs.count) album hubs for artist:")
            
            for hub in hubs {
                print("  - \(hub.title) (\(hub.size) albums)")
                XCTAssertNotNil(hub.title, "Hub should have a title")
                XCTAssertNotNil(hub.type, "Hub should have a type")
                XCTAssertNotNil(hub.hubIdentifier, "Hub should have an identifier")
                
                // Check if hub has albums
                if let albums = hub.metadata {
                    XCTAssertEqual(albums.count, hub.size, "Hub size should match actual album count")
                    
                    for album in albums.prefix(3) { // Show first 3 albums
                        print("    - \(album.title ?? "Unknown") (\(album.year ?? 0))")
                        XCTAssertNotNil(album.ratingKey, "Album should have a rating key")
                        XCTAssertNotNil(album.sonosID, "Album should have a Sonos ID")
                    }
                    
                    if albums.count > 3 {
                        print("    ... and \(albums.count - 3) more albums")
                    }
                }
            }
        }
    }
    
    func testGetArtistAlbumsWithInvalidKey() async throws {
        // Given: A valid access token but invalid artist key
        PlexAuthenticator.shared.authToken = testAccessToken
        
        // When: Getting artist albums with invalid key
        let albumHubs = await plexAPI.getArtistAlbums(key: "invalid_key")
        
        // Then: Should return nil or empty array
        XCTAssertTrue(albumHubs == nil || albumHubs?.isEmpty == true, "Should return nil or empty array for invalid key")
    }
}
