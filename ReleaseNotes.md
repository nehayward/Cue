# 2024.2

- Improve new volume slider
- Update Queue, fallback to Sonos Album Art
- Fix playlist not queuing sometimes

## Internal

- Add vanished devices
- Add Open in Spotify

# 2024.1

- Fixed duplicate live activities.
- Added an action extension in the share sheet to play any public playlist, album, or track from Spotify.
- Added an action extension in the share sheet to play any song from Apple Music.
- Added a tiny widget (accessory circle) to create a live activity for the selected room.
- Fixed the searching overlay pill.
- You can now reorder the queue; simply drag an item to the desired location.
- Improved queueing.
- Added haptics to watchOS.

## Internal 

- Increase search to 15 per item on spotify
- Add group count name to group room model
- Add update group function to SonosService
- Fix font and image clipping on spotify search
- Add name to live activity
- Add VolumeControlView to Vibe
- Add playlist and album search to MusicSearchKit
- Add MediaContent model
- Add unit test for parsing Apple Music URLs
- Fix padding on bottom of search view.

# 2023.7

- Added scrubbing functionality for playback progress.
- Implemented a feature to queue a song next on Spotify and Apple Music tracks through swipe gestures.
- Updated the volume slider for enhanced usability; it now supports swiping anywhere on the track.
- Introduced a swipe gesture to delete tracks from the queue.
- Fixed an issue where the volume slider would jump unexpectedly.
- Updated room volume controls on the player screen for better integration.

## Internal
- Fix reviews not being requested
- Update grouping background color
- Add VibeSlider

# 2023.3

Scenes have been added to the Group screen

- Scenes not set the volume first then groups rooms.
- Improve Live Activities
- Add refresh on Live Activities 
- Add transition to Live Activities
- Add scroll to current queue
- Fix queue screen with identical tracks
- Fix queue placement 
- Fix history sorting 
- Move scene creation to group screen 
- Improved animations 
- Modal for scene running