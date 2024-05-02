# 2024.19

## External 

+ Show if the Queue is Active now.
+ Fixed an issue where playlists/songs wouldn't start if the queue was inactive.
+ Enhanced album art display for Radio.
+ Improved Queue List functionality.
+ Added badge for Radio.
+ Added crossfade settings for groups.
+ Enhanced queuing speed.
+ Added new releases to search results.
+ Enabled drag-and-drop functionality for songs/tracks between rooms.

## Internal

+ Add disabled mode to VibeSlider
+ Add Available Actions to Sonos API
+ Update TV Mode, get it from media info
+ Add Playback Service, whether queue is active
+ Use duration for playback position
+ Add playbackService to SonosService
+ Fix queue not being activated
+ Clean up URL queue


# 2024.18

## External 

+ Improved grouping speakers, you can now remove any speaker from group.
+ Improve search, even faster now.
+ Add group button to toolbar.
+ Search from HomeScreen shortcut.
+ Added View Album on ellipsis button on player screen.
+ Added View Artist on ellipsis button on player screen.

+ Improve Live Activities
+ Customize App Icon
- Fixed and issue where toolbar would get hidden on iPad. Thanks Jason!

## Internal
+ Fix track showing wrong album art
+ Fix Live Activity not transitioning animation.


# 2024.17

## External 

+ New App Icon
+ Added artist to search results.
+ Added album details.
+ Added Artist details.
- Fix Sonos Move and Roam Battery Level not being updated.
- Fix slow launch due to Roam or Move being powered off/sleeping

## Internal
+ Add Storekit Configuration Integration


# 2024.13

## External 

+ Improved Search!
+ Search Suggestions
+ Queue Apple Albums and Playlists
+ Long press for instant search

## Internal

- Update when no scenes are created.
- Fix live activity buttons
- Fix playback button being jumpy

# 2024.12

## External 

+ Add favorites to search, you can now browse and play your Sonos Favorites with a single tap.
+ Add star to content artwork

## Internal
- Start multi house setup.
+ Add favorite type to playable content.
+ Fix parsing of stations.

# 2024.11

+ Fix widgets subscription info being lost

# 2024.10

+ Add integration with NowPlaying!
+ Add drag and drop support for Apple Music and Spotify
+ Add Open in for Apple Music and Spotify
+ UI Tweaks
+ Improve Watch UI
+ Add Icon when in TV Mode
+ Add repeat and shuffle controls
+ Add content type to Play History

## External 

+ InvalidatableContent State to Widgets

# 2024.6

## External 

- Improved system monitoring.
- Watch app will now auto launch to currently playing group. You can turn this off in settings.
- Added play history.
- UI Improvements.

## Internal

- Improved monitoring so SwiftUI view isn't constantly redrawn.
- Adding function to observe group changes.
- Remove queue index number on watch and phone.
- Add Defaults Package
- Fix permission button not showing.
# 2024.6

## External 

- Improved system monitoring.
- Watch app will now auto launch to currently playing group. You can turn this off in settings.
- Added play history.
- UI Improvements.

## Internal

- Improved monitoring so SwiftUI view isn't constantly redrawn.
- Adding function to observe group changes.
- Remove queue index number on watch and phone.
- Add Defaults Package
- Fix permission button not showing.

# 2024.3

## External 

- Fix queueing with Apple Music
- Update group list
- Visual tweaks
- Add TV Settings to LockScreen Widget
- Add search to main screen.

## Internal

- Changed group naming to include room name if less then 3 rooms.
- Prep for macOS Support move live activity to manager with protocol.
- Setup play component for integration with NFC.
- Remove Promo Code Button
- Refresh all devices if group changes, even when selected
- Improve slider for playback.
- Create WidgetManager
- Setup PlaygroupScreen for Search and Queueing
- Add queueing option for media content
- Add play url scheme "clic://play/spotify/album/5pTaRVLwZOFObIbRBubmeb"
- Fix routing options
- Switch to NavigationStack
- Create separate view for iPad
- Move to Nuke
- Update review service, use number of opens.

# 2024.2

- Improve new volume slider
- Update Queue, fallback to Sonos Album Art
- Fix playlist not queuing sometimes
- Live Activities Lock Screen now matches system color scheme (i.e light/dark mode). Thanks Guillaume!
- Widget now matches system color scheme (i.e light/dark mode)
- Add Scene URL Scheme
- Add Artwork to Live Activities
- Add compact mode to Live Activities

## Internal

- Fix Queue not parsing Spotify
- Add Artwork Manager
- Add Sonos System
- Add vanished devices
- Add Open in Spotify foundation

## Released
- Enhanced Volume Slider: The volume slider has been redesigned for better accuracy and smoother user experience.
- Queue Update with Album Art Fallback: Improved the Queue functionality. Now, if specific artwork is unavailable, the system will automatically use Sonos Album Art as a fallback.
- Playlist Queueing Issue Fixed: Resolved an intermittent issue where playlists were not queuing as expected.
- Live Activities Lock Screen - System Color Scheme Integration: The Live Activities Lock Screen now automatically adapts to the system's color scheme (i.e., light or dark mode). Special thanks to Guillaume for this suggestion!
- Widget System Color Scheme Compatibility: Widgets have been updated to match the system's light or dark color schemes, enhancing visual consistency.
- New Scene URL Scheme Added: Introduced a Scene URL Scheme feature for advanced user customization and integration.
- Artwork Integration in Live Activities: Live Activities now include artwork, offering a more visually engaging experience.
Compact Mode for Live Activities: Added a new compact mode to Live Activities, allowing for a more streamlined and space-efficient display.

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