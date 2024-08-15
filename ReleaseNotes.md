# 2024.36

## External

- Now supports S1!
- Supports multiple households.

## Internal

# 2024.35

## External

New Features
- Plex Support!: Browse and search your Plex library directly within the app.

Enhancements
- Improved Volume Control: Volume adjustments are now even more responsive, providing a smoother user experience.
- Enhanced MiniPlayer: The MiniPlayer has been optimized for better performance and usability.
- Music Filtering Adjustments: Music filtering has been fine-tuned to provide more accurate results.
- Queue Improvements: We've made several updates to improve the overall functionality and stability of the queue.
- Duration Removal from Queue Screen: The duration has been removed from the queue screen for a cleaner look.

Bug Fixes
- Queue Dismissal in Portrait Mode: Fixed an issue where the queue couldn't be dismissed in portrait mode. Thanks, Alex, for the feedback!
- Tidal NowPlaying Fix: Resolved an issue preventing Tidal from opening in the NowPlaying view.
- Unreleased Tracks Fix: Fixed a bug where unreleased tracks were incorrectly shown as playable.
- Fix open in Spotify

## Internal

+ Add analytics for number of devices
+ Remove dependency on URLRequest
+ Add pagination to MediaDetailView, need to add it for other sources.
+ Add number of playlists to PlexBrowseScreen.
+ Add plex logging and url to upload logs.

# 2024.33

## External

+ Fixed an issue where "Open in Apple Music" wasn't showing. Thanks Shawn!
+ Fixed Height Settings not being updated in Speaker settings.
+ Fixed and issue with some playlist not playing. i.e Bob Marley & The Wailers

+ Improve Live Activity compact view
+ Add Recently Added for Apple Music
+ Adjust Sub for any speaker, not just sound bars.

## Internal

# 2024.32

## External

+ Add User Apple Playlists and User Recently Played
+ Browse Sonos Library! (Artists, Album, Songs, Saved Playlists)
+ Add replace queue option and queue next.
+ Improved favorites.

## Internal

+ Fix Artwork not getting removed
+ Disable play button when not able to play
+ Added Glur, might replace with alternative


# 2024.31

## External

+ Added Radio to Spotify and Apple Music, you can now start a station for an artist.
+ Added MiniPlayer to Search and other views to control playback and skip songs.
+ Improve Play Action in share sheet.
+ Fixed an issue where you couldn't dismiss a view when trying to add a a song to an alarm.

## Internal

+ Add SelectGroup View
+ Add SelectedGroupService, now and env for selected group.

# 2024.30

## External

+ Add TuneIn Support!
+ Add Line In Switch for TV
+ Added empty playlist state.
+ Add Icons for filters
+ Improve queueing
+ Energy and performance improvements 
- Fix Apple Playlists not showing up in Search.
- Fix Live Activity TV audio format display.

## Internal
- Ground work for browse library
- Made PlayHistory Environment variable
- Ground work for TuneIn
- Fixed Queue when queue is not active, not properly playing first song
- Use Load for watch now
- Remove fetch
- Add symbol names for Filters
- Fix PlayerSelection Background

# 2024.29

## External

+ Add EQ controls for Speakers!
+ Add Medium Widget.
+ Customize search options.

## Internal
- Improve Live Activities.
- Add channel map info.
- Move icons to packages and reduced size.

# 2024.28

## External

+ New Icon!
+ You can now easily manage and add songs to your playlists.
+ Improved Queueing (Should be instant now).
+ Added hint for how to switch search.
+ Add sleep timers when in TV mode.

## Internal
- Queue uses PlayableContent now.
- Added simple get Queue count API
- Reduced size of spotify images

# 2024.27

## External
+ Custom Sleep Timers Added!: Now you can set personalized sleep timers to automatically stop playback after a specified duration.

- Track Title Display Fix: Resolved an issue where the track title would not display if the album art was missing.

+ Fixed an issue where queue would jump to beginning of track before going to selected track. Thanks Paul!

+ Add option to hide NowPlaying… open in.

## Internal
+ Fixed paywall button not showing in preferences 
+ Move spotify to new queueing

# 2024.26

## External
+ Add beta support for Tidal
+ Improve search

# 2024.23

## External
+ Fix missing album art in some cases.
+ Improved search.

## Internal
+ Add Audio Broadcast to to ContentType Lookup
+ Improve favorite album art lookup
+ Add initial support for Tidal

# 2024.22

## External
+ Alarms! Add or manage existing alarms.
+ Add Favorites to play history
+ Fix queue not dismissible on iPad slide over.
+ Fix sleep timer showing when its complete.

## Internal
+ Add Audio Broadcast to to ContentType Lookup
+ Improve favorite album art lookup

# 2024.21

## External 

+ Add Sleep Timers!
+ Fix navigation bar disappearing on iPad, add compact mode to iPad.

# 2024.20

## External 

+ Add support for Music Library, you can now search and play songs from your Library!
+ Improved Album Art loading.
+ Fixed an issue with Night Mode and Dialog Mode getting reset.
+ Play History can be filtered now.

## Internal
+ Fixed an issue when album being queued.
+ Add more device information
+ Prioritize ethernet connected IPs

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