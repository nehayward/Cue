# MusicSearchKit

A Swift package for searching and accessing music content from various streaming services including Plex, Tidal, and more.

## Features

- **Plex Integration**: Full Plex Media Server API support
- **Tidal Integration**: Access to Tidal's music catalog
- **Unified API**: Consistent interface across different music services
- **Playable Content**: Ready-to-use content models for playback

## Plex API

### Authentication

```swift
import MusicSearchKit

// Set up authentication
await MainActor.run {
    PlexAuthenticator.shared.authToken = "your_plex_token"
}
```

### Basic Usage

```swift
let plexAPI = PlexAPI.shared

// Get all Plex servers
let servers = await plexAPI.getPlexServers()

// Get artists
let artists = await plexAPI.artists(limit: 50)

// Get albums
let albums = await plexAPI.albums(limit: 100)

// Get songs
let songs = await plexAPI.songs(limit: 100)
```

### Artist Albums by Type

The new `getArtistAlbums` method allows you to fetch all album types for an artist, organized by category:

```swift
// Get all album types for an artist
let albumHubs = await plexAPI.getArtistAlbums(key: "artist_rating_key")

if let hubs = albumHubs {
    for hub in hubs {
        print("\(hub.title): \(hub.size) albums")
        
        // Access albums in this category
        if let albums = hub.metadata {
            for album in albums {
                print("  - \(album.title ?? "Unknown") (\(album.year ?? 0))")
            }
        }
    }
}
```

#### Album Categories

The API returns different album categories including:

- **Singles & EPs**: Individual singles and extended plays
- **Live Albums**: Live recordings and performances
- **Soundtracks**: Movie and TV show soundtracks
- **Compilations**: Various artist compilations
- **Demos**: Demo recordings
- **Remixes**: Remix albums and versions

#### Response Structure

```swift
public struct PlexAlbumHub {
    public let title: String           // Category name (e.g., "Singles & EPs")
    public let type: String           // Content type (e.g., "album")
    public let size: Int              // Number of albums in category
    public let hubIdentifier: String? // Unique identifier
    public let metadata: [PlexAlbumItem]? // Array of albums
}
```

#### Example Response

For an artist like Dua Lipa, you might get:

```
Singles & EPs (67 albums)
  - CAN THEY HEAR US (2021)
  - Fever (2020)
  - Levitating (2020)
  ...

Live Albums (1 albums)
  - Live from the Royal Albert Hall (2024)

Remixes (1 albums)
  - Club Future Nostalgia (2020)
```

### Advanced Usage

```swift
// Get specific album categories
if let singlesHub = albumHubs?.first(where: { $0.title.contains("Singles") }) {
    let singles = singlesHub.metadata ?? []
    // Process singles
}

// Get albums with specific criteria
if let liveHub = albumHubs?.first(where: { $0.title.contains("Live") }) {
    let liveAlbums = liveHub.metadata ?? []
    // Process live albums
}
```

### Error Handling

```swift
let albumHubs = await plexAPI.getArtistAlbums(key: "artist_key")

switch albumHubs {
case .some(let hubs):
    // Process successful response
    print("Found \(hubs.count) album categories")
case .none:
    // Handle error (invalid key, network issue, etc.)
    print("Failed to fetch artist albums")
}
```

## Testing

Run the test suite to verify functionality:

```bash
swift test
```

The test suite includes examples for:
- Server discovery
- Library access
- Artist album retrieval
- Error handling

## Requirements

- iOS 15.0+ / macOS 12.0+
- Swift 5.5+
- Xcode 13.0+

## Installation

Add MusicSearchKit to your project dependencies:

```swift
dependencies: [
    .package(url: "path/to/MusicSearchKit", from: "1.0.0")
]
```

## License

This project is licensed under the MIT License - see the LICENSE file for details. 
