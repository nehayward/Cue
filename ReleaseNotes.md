# 2025.12

–– New Features ––
- Added SoundCloud browse library to show Liked Tracks
- Added batch editing functionality to Queue for managing multiple tracks at once
- Added Up Next view to display upcoming items in the queue
- Added Connectivity screen, allowing manual IP address assignment
- Added Recommended Albums section to Apple Music library with personalized album suggestions
- Add Mute Button to Live Activity and Speaker List

–– Bug Fixes & Improvements ––
- Fixed an issue where tracks were not updating correctly when using Spotify Connect
- Fix bug from stopping playback from other apps.
- Improve cell contrasts
- Fixed Radio Station Name not displaying in some cases
- Improved image loading and caching
- Improve Connectivty on Apple Watch
- Improve metadata performance

## ChangeLog
- Fix pagination for Soundcloud, they use cursor pagination
- Added SoundCloud browse library with OAuth token support and secure keychain storage
- Enhanced KeychainTokenRefreshHandler to support multiple music services
- Updated SoundCloud API with dual authentication system (direct OAuth + Sonos service tokens)
- Moved radio station to room, since it doesn't change track-to-track
- Improved queue screen performance and identity handling for better track management
- Add AudioPlayback service
- Add previewURL to spotify
- Add Up Next View
- Extracted TV mode controls into reusable components for better SwiftUI performance
- Fixed icon sizing inconsistency in TV mode controls

# 2025.11

–– New Features ––
- Added support for Sonos Playbase
- Added auto-launch capability for iPad
- Added keyboard shortcuts for quick access:
  - Queue (press "q")
  - Search (press "s") 
  - Library (press "l")
- Added Playback Menubar Controls
  - Play/Pause (press "spacebar")
  - Previous Track (press "⌘←")
  - Next Track (press "⌘→") 
  - Volume Up (press "⌘↑")
  - Volume Down (press "⌘↓")
- Added Dolby or Lossless Icon to AudioInfo Details
- Added Radio Station Name
- Sleep Timer remembers last 3 custom timers for quick access
- Added support for local network option for Plex
- Added comprehensive album support for Plex artists:
  - Studio albums
  - Live albums
  - Singles & Remixes
  - Soundtracks & Compilations
- Mac app now remembers window size and position between launches
- Fixed duplicate items appearing in Apple Music and Plex libraries
- Improved visual contrast in light mode across multiple screens for better readability
- Added highlight state to Search, Queue, and Browse

–– Bug Fixes & Improvements ––
- Enhanced Plex integration for better reliability and performance
- Improved Scene functionality:
  - Faster and more reliable Scene execution
  - Scenes now maintain functionality when device IP addresses change
  - Enhanced device discovery and grouping behavior
- Fixed regression preventing manual activation of groups with disabled Live Activities via Shortcuts, Widgets, or Control Center
- Fixed issues with Live Activities Shortcut toggle functionality
- Fixed crash occurring on iPadOS when opening Queue, Search, or Browse panels
- Fixed a hitch occurring on main player screen
- Fixed rendering glitch in Clic Mini where apostrophes were not displaying correctly
- Large playlists now load more reliably and efficiently

# 2025.10

–– New Features ––
- Enhanced Spotify integration with improved playback reliability and metadata handling
- Added option to hide popular songs section on artist detail pages for a cleaner view

–– Bug Fixes & Improvements ––
- Fixed missing artwork for certain radio stations and live streams
- Significantly improved scrolling performance and responsiveness throughout the app
- Resolved an issue where some favorited content would fail to play
- Added Spotify region override option in settings for international users

## Internal
- Use menu in place of context menu in List view for PlayableCardView

# 2025.9

–– New Features ––
- Added the ability to disable Live Activities for individual speakers.
- Introduced support for Fixed Volume speakers.
- Added library selection for Plex integration.

–– Bug Fixes & Improvements ––
- Fixed an issue where album art would not update correctly.
- Improved efficiency when fetching metadata.
- Resolved an issue where albums were not showing in Plex.
- Fixed playlists not displaying all content in certain cases.
- Fixed a crash that could occur when backgrounding the app.
- Resolved an issue where audio quality was not displayed for Local Library content.
- Queue icon now dynamically scales based on content.
- Volume slider now dynamically sizes for better usability.
- Fix Queue, Search, and Browse not showing in compact Mac Window

# 2025.8

–– New Features ––
- Shows audio quality on player screen: Bit depth (e.g., "24-bit"), Sample rate (e.g., "48kHz"), Lossless status, Immersive audio support.

–– Bug Fixes & Improvements ––
- Fix image flickering on macOS on new window launch
- Fix image flicker on iOS

# 2025.7

–– New Features ––
- Added sorting options on Mac for easier browsing.
- Added service information for Tidal and TuneIn on the Settings screen.
- Added guidance for favoriting content in the Sonos app.
- Introduced TV input support for Amp 2.
- Expanded Plex Browse to include Albums, Artists, and Songs.
- Added Songs section to the Apple Music browse view.

–– Bug Fixes & Improvements ––
- Improved overall performance on Mac.
- Enhanced responsiveness of the Watch app.
- Performance optimizations for Clic Mini.
- Live Activities now update more quickly and reliably.
- Fixed an issue where Live Activity images were not refreshing correctly.
- Reduced memory usage across the app for better efficiency.

- Switch to SonosService shared for better SwiftUI performance 

# 2025.6

––New Features––
- Added Genres in Local Library
- Add support for switching to Line In on supported devices
- Add ability to switch playback to Queue input
- Add new detection method for devices that support Line In (e.g., Amp, Era, Five, Move 2)
- Add release notes to preferences.

––Bug Fixes––
- Fix main list view not updating song titles on change.
- Fix issue with MiniPlayerView not updating selected group properly

# 2025.5

––New Features––
- SoundCloud Integration: Added support for searching tracks and playlists on - SoundCloud.
- Imported Playlists: Introduced the ability to view Imported Playlists in the Sonos Library.
- Priority Device Assignment: Users can now assign a priority device in - settings, prioritizing wired connections, the latest models, and - non-portable Sonos devices.
- Queue Popular Songs: Added functionality to queue popular songs for artists.

––Bug Fixes––
- Spotify Playlist Loading: Resolved an issue where some Spotify playlists were not loading correctly.
- Sonos Device Parsing: Fixed a parsing issue for Sonos devices with "&" in their names.
- Improve animation between TV Mode
- Fix crash on Mac

# 2025.4

––New Features––
- New Sorting Options – Sort speakers by what’s currently playing or alphabetically.
- Marquee Text – Player and mini player now support scrolling text for better readability.
- Launch Preferences – Choose to launch directly to the currently playing group or TV Mode.
- Apple Music Artwork Fix – Resolved an issue where artwork sometimes failed to display.
- Apple Watch Improvement – Changing the volume now automatically unmutes audio.

––Bug Fixes––
- Enhanced MiniPlayer contrast for better visibility.

# 2025.3

––New Features––
- Set preferred color scheme, light, dark or system
- Apple Music - Show latest album for artist and all albums
- Add Login Item to Clic Mini

––Bug Fixes––
- Fix alarms
- Fix memory leak.
- Performance improvements.

# 2025.2

––New Features––
- Add Scene activation for Clic Mini
- Add mute controls in TV Mode.

––Bug Fixes––
- Tidal search results no longer include playlists.
- Fixed Clic Mini not updating in some scenarios
- Refined speaker grouping
- Fixed Up Next not showing on Watch
- Fixed an issue with some Apple Music URLs not being parsed in the Queue action, it also opens Clic after being executed.
- Fix album art not showing on main list view
- Fixed scenes not triggering on Watch in some cases

# 2025.1

––New Features––
- Introducing Clic Mini – a lightweight way to control your music effortlessly from the menu bar.
- Added hover states to the queue list and device list for a more responsive feel.
- Album art now crossfades for smoother transitions.
- Live Activities will now dismiss automatically when paused on app launch.
- Completely rewrote the watch app for better performance and a faster experience.
- Updated volume controls for more precise adjustments.
- Now showing a Line-In icon when available.
- Tidal search results now include playlists.

––Bug Fixes––
- Fixed an issue where Tidal search results wouldn’t appear.
- Fixed queue totals displaying incorrectly when over 1000 items.
- Live Activity on Apple Watch now correctly opens the watch app if installed.
- NowPlaying is now hidden on macOS since it’s not supported.
- Improved music service selection for a smoother experience.
- Various performance improvements for the Mac app.


# 2024.46

––New Features––
- Improved queueing, simple tap a song on a playlist and it'll now replace the queue with the whole playlist. Album now queued and jumps to track that's selected.
- Tap Navigation Title to see all players in group.
- Improve Plex integration
- Swipe to play next.
- Add shuffle to albums and playlists
- Improved resizing on Mac


# 2024.45

BLACK FRIDAY Special $4.99 for the first year.

––New Features––
- Scenes now prioritize grouping to the player that is playing, so that playback is not interrupted.
- Redesigned and improved Play in Clic for Action Sheet.
- Improve Live Activities animations.
- Fix Queue Count not updating in some cases.
- Fixed for Spotify Playlist not loading in some cases.
- Add Radio option for Spotify and Apple Tracks
- Improve volume controls on main screen.

## Internal
- Moved to OrderedKeys

Release Notes
Winter Special: Just $4.99 for the first year! (Until 12/8)

Take advantage of this limited-time offer and explore our newest features and improvements:

New Features
- Seamless Scene Grouping: Scenes now automatically group to the player currently playing, ensuring playback continues uninterrupted.
- Enhanced Action Sheet: Redesigned Play in Clic for a more intuitive and polished experience.
- Radio Options for Your Tracks: Added a Radio option for Spotify and Apple Music tracks, giving you more ways to enjoy your music.

Improvements & Fixes
- Smoother Live Activities Animations: Improved animations for Live Activities, making them more fluid and engaging.
- Reliable Queue Counts: Fixed an issue where the queue count wouldn’t update in some cases.
- Spotify Playlist Reliability: Resolved a bug that prevented certain Spotify playlists from loading.
- Better Volume Controls: Improved volume control responsiveness and usability on the main screen.

Get these exciting updates now and don’t miss the Winter special!

# 2024.44

––New Features––
- New Volume controls for Live Activity and Dynamic Island
- New Volume controls for Widgets
- New Run Scene Control Widgets
- New Alarm launcher for Control Widgets, add alarm setting controls to your lock screen.
- Shortcuts are easier to use and have been categorized.
- Search for speakers in Spotlight
- New shortcut to control Live Activities

# 2024.43

––New Features––
Spotify Playlist Import: Effortlessly import your favorite Spotify playlists and enjoy them here!
New Player Selection UI: Choose any speaker you’d like to play on directly from the search screen.
Play in Another Room…: Easily move your music to a different room with this convenient option.

––Enhancements––
Preference Screen Overhaul: The preference screen has a fresh look with improved layout and functionality.
Long-Press Song Titles: Now you can long-press on a song title in the player screen to view the full title.

––Bug Fixes––
Volume Control: Resolved delays in volume control for Sequoia.
Scene Management: Fixed issues with scenes not unmuting or ungrouping from rooms when running.
Album Sorting: Albums are now sorted by release year (latest first) in the artist view, with LPs removed for a cleaner look.
Live Activity Mute State: Mute states are now clearly indicated in live activities for easier tracking.

# 2024.42

+ Improve Preference Screen
+ Fix volume control delays on Sequoia 
+ Fix scenes not unmuting when running

# 2024.41

+ Add tinting to watch complication
+ Indicate if speaker is muted in Widgets
+ Improve volume controls for multiple speakers
+ Fix tinting on Widgets
+ Fix Plex images not loading on Watch
+ Fix layout issue with settings screen on Sonoma

# 2024.40

+ Added Apple Radio Stations
+ Improved Queue management.
+ Fixed an issue where Plex search wasn't showing results.

# 2024.39

+ Added Large and Extra Large Widget.
+ Fixed watch live activity not showing.
+ Add Lifetime purchase option.

Previous 
New Features:
+ Apple Music Library Search: Added support for searching your local Apple Music library.
+ Apple Watch Live Activity: Interactive controls for playback.
+ Explicit Content Label: Added explicit content labels for easier identification.
+ Remote Control Center Widget: Added a new widget for quick access to remote controls.
+ Launch Control Center Widget: Added a dedicated widget for launching app.
+ New App Icon: Updated the app with a fresh new icon.
+ Play History on Watch App: Added play history view to the Apple Watch app.

# 2024.37

## App Store

New Features:
+ Apple Music Library Search: Added support for searching your local Apple Music library.
+ Apple Watch Live Activity: Interactive controls for playback.
+ Explicit Content Label: Added explicit content labels for easier identification.
+ Remote Control Center Widget: Added a new widget for quick access to remote controls.
+ Launch Control Center Widget: Added a dedicated widget for launching app.
+ New App Icon: Updated the app with a fresh new icon.
+ Play History on Watch App: Added play history view to the Apple Watch app.

Improvements:
• Playlist Fix: Resolved an issue where some songs were not appearing in playlists.
• Enhanced Error Handling: Improved error handling for a smoother and more reliable user experience.

## External

+ Add local apple music library search
+ Add live activity for apple watch.
+ Add explicit label
+ Add Remote Control Center Widget
+ Add Launch Control Center Widget
+ Add new icon.
+ Add play history to watch app.
- Fixed issue where not all songs would show in playlists
- Better error handling

## Internal

- Cache images to disk.

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