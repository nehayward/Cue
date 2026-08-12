# 2026.7

–– New Features ––
- Lock Screen Controls (Super): Preferences ▸ Lock Screen now lets you pick what shows while a speaker is playing — Live Activity, Now Playing, or Off. Now Playing puts what's on Sonos into your device's own player on the Lock Screen and in Control Center: artwork, song, and the speaker it's playing on, with play/pause, skip, and scrubbing. Turn on Use iPhone Volume Buttons and the volume buttons control that speaker too — including changes made on the speaker or in the Sonos app. With several rooms playing, the card follows whichever one is playing while your device is locked, and stays on the speaker you're viewing while you're in the app. It all keeps working with the app closed. It's the default with Clic Super, and it replaces Live Activities while it's on — switch back and they return. Note that Clic takes over your device's audio once a speaker starts playing
- Sonos Radio: Search Sonos Radio stations and browse them by genre, then play any station on any room or group — the SONOS badge appears on the artwork, and the station's artwork is shown during ad breaks
- Smarter Services settings: the Services screen now shows what's actually on your Sonos — services you've authorized get show/hide toggles, ones you haven't set up yet link straight to the Sonos app to sign in, and services Clic doesn't support yet are listed too. Pull down to refresh after adding one
- Pandora: Browse your Pandora stations, search for new ones, and play any station on any room or group — sign in through the Sonos app and it works in Clic automatically
- Pandora Thumbs: Thumb a song up or down right from the player to tune what the station plays next — and set any Pandora station as an alarm

–– Bug Fixes & Improvements ––
- Song changes now show up right away instead of a beat later — Clic listens to your speakers directly for track and play/pause changes
- Fixed album artwork stuttering the player during song changes — the crossfade is now one smooth dissolve
- Fixed the player staying stuck on a radio station after playing a song from the queue — playback switches reliably, the progress bar appears again, and the station caption clears right away
- Services you remove in the Sonos app no longer linger in Clic — they're hidden from search and browse automatically
- Plex sign-in now lives right on its row in Services — tap the row to manage your account
- Fixed square corners showing around the Clic Mini notification and menu bar window in light mode
- Clic Mini: The notification and menu bar window now use Liquid Glass on macOS 26
- Fixed older S1 Sonos players (like the ZP100 or ZP80) never being found — a home running S1 now shows up in Households alongside your S2 system, so a split S1/S2 setup can switch between the two with a tap. This applies on Apple Watch and in Clic Mini too, where S1 systems were missing from the household list entirely
- Clic Mini and Apple Watch now follow the speaker you pick on the Connectivity screen, instead of whichever speaker happened to answer first
- Redesigned the Connectivity screen around a single choice — which speaker Clic connects through. It's set to Automatic out of the box, or tap any speaker to use that one instead; a LAN badge marks the speakers wired to your router, and a tick shows what's in use
- Entering an address by hand has moved into a "Can't find your speakers?" section that opens on its own when nothing is found — and once a speaker answers at that address, a Connect button appears so you can actually switch to it. Previously the screen could only verify the address
- Fixed the Connectivity screen sometimes showing "No Sonos system found at this IP address" right after the address was verified with a green check
- The IP address field no longer marks an address wrong while you're still typing it, and shows a spinner while it checks. A wrong address now tints the field red instead of adding an error icon that looked like a second clear button
- Fixed the speaker you pick on the Connectivity screen not sticking — the tick would flash onto it and jump back to another speaker. Your choice now persists, and Clic genuinely uses that speaker for album artwork, your library and favorites
- Clic's automatic speaker pick now prefers a speaker wired to your router, as it always said it did — previously the wired preference was applied and then discarded, so it could settle on a speaker over Wi-Fi
- Refreshed the bottom controls on the player and the speaker list with a glass toolbar look — earlier iOS versions get a matching frosted style
- The player's ••• menu now sits at the end of the toolbar on iPad and Mac, after Search, Browse, and Queue
- Fixed the queue button's ring briefly showing as full when opening or closing the queue
- Scenes now play on the speakers that are available — if a speaker is unplugged or offline, the scene runs on the rest instead of doing nothing
- Redesigned the empty queue and Up Next screens — instead of a bare "Nothing up next", they now show your recent play history so you can tap to start something playing right away
- Playing a long playlist no longer feels like the tap was dropped — if Sonos needs more than a moment, the banner shows a spinner with what's loading, then confirms once it's ready
- The play button now pulses while your speaker is getting a song ready — in the mini player, the player, the speaker list, and on Apple TV
- Fixed the Live Activity vanishing when you set the volume from it while in another app — and a speaker that's briefly unreachable no longer dismisses your other rooms' Live Activities along with it
- Your volume buttons and the Lock Screen slider now control the speaker by default — Use iPhone Volume Buttons has moved to Preferences ▸ Lock Screen, sitting with the Now Playing setting it belongs to, and it now covers the sliders as well as the buttons. Previously the switch had no effect on the Lock Screen at all. If you'd turned it off, it stays off
- Clic now hands the Lock Screen player, its controls, and your volume straight back whenever your device's audio moves to Bluetooth, CarPlay, or headphones — so an automation that turns the volume up and presses play when you get in the car reaches your car, not the speakers at home. Everything returns when you disconnect
- Your speakers can no longer be jumped to a new volume in one step by something you didn't touch — a shortcut, an accessory, or a device connecting. Volume changes you make by hand work exactly as before
- Much lighter on battery while your phone is locked with Lock Screen Controls showing — Clic was still doing a screen's worth of work behind the Lock Screen, and now goes quiet until something actually happens on your speakers
- Fixed the Lock Screen volume slider nudging your speaker a point or two off where you set it, just from showing the card

# 2026.6

–– New Features ––
- Multiple Homes: Clic now remembers every Sonos system you connect to. Manage them under Preferences ▸ Households — each home shows its speakers and whether it's an S1 or S2 system so they're easy to tell apart. Switch systems with a tap, and long-press or swipe to rename or remove a home. Open the screen anywhere and Clic scans for new systems on that network (like a friend's house) and adds them automatically
- Playlist Management: Add any song to your Apple Music, Spotify, Plex, or Deezer playlists — not just Sonos. The new Add to Playlist sheet lets you pick several playlists at once, create a new one, search, and jump to a recently-used playlist; tap the confirmation to open the playlist you added to
- Edit Playlists: Open a Spotify, Plex, Deezer, or Sonos playlist you own and tap Edit to remove tracks (swipe, menu, or multi-select), drag to reorder, or delete the playlist — with Undo (⌘Z on Mac)
- Create Playlists: Make a new playlist for Apple Music, Spotify, Deezer, Plex, or Sonos from its browse screen — including an empty one you fill in later
- Add to Last Playlist: A one-tap shortcut — in the track menu and the Mac File menu — to drop the current song into the playlist you used last
- Song Previews: Long-press an Apple Music or Spotify track and tap Preview Song to hear a quick clip — or swipe right on a track in a list. A progress bar fills as the clip plays, and you can tap the track to stop it
- Library Song Actions: Long-press a song in your Apple Music library to open its Apple Album or Apple Artist, or start a Song Radio — Clic resolves the matching catalog track behind the scenes
- Universal Search: Search several services at once — pick up to three in the search service menu (like your Library alongside Apple Music) and get one combined, ranked list of results. Note: the selected search service resets once with this update — just re-pick it in the search menu
- Plex Setup in Onboarding: If you use Plex, setup now walks you through signing in and choosing your music library right away — with artist artwork previews so libraries are easy to tell apart
- Automatic Plex Connection: A new Auto connection type uses your fast local network at home and switches to remote access when you're away — pick it, Remote, or Local from the redesigned connection switch in Plex settings
- Arc Ultra Speech Enhancement: Control speech enhancement level (Off, Low, Medium, High, Max) on Sonos Arc Ultra from the player, Shortcuts, Clic Mini, and Apple Watch — the level is shown on the button and updates immediately after changing
- TV Dialog Sync: Fine-tune audio delay (lip sync) on Sonos soundbars from the Home Theater section of speaker settings

–– Bug Fixes & Improvements ––
- Faster reconnect on a new network: when you move between Wi-Fi networks — or return to the app at a different location — Clic now finds your speakers right away instead of waiting through a timeout. Once a home is known, switching to it is instant
- Fixed the app briefly stalling on the last-used speaker after switching networks, before falling back to discovery
- Fixed removing one track from a Spotify playlist also deleting other copies of the same song — only the track you remove is removed now
- Fixed adding a large album (more than 50 tracks) to a Spotify playlist only adding the first batch — every track is added now
- Fixed the Deezer "Add to Playlist" list showing playlists you follow but don't own — only your own playlists are offered now, so the add no longer silently fails
- Fixed some alarms not appearing in the Alarms list — alarms for speakers that are grouped, part of a stereo pair, or temporarily offline are now always shown, and music alarms (Apple Music, Spotify, radio stations) no longer occasionally go missing. Pull down to refresh the list
- Fixed "Switch to Line In" appearing on speakers that don't support line-in
- Fixed the library Albums list stopping partway through the alphabet — albums, songs, and artists now load your entire library as you scroll
- Fixed Genres, Imported Playlists, and folder contents being cut off in large libraries — these now load fully as you scroll
- Smarter search: results now rank like Spotify and Apple Music — the artist you're looking for lands on top with their albums and hits right below, popular and new releases rank higher, songs you play often get a boost, and close matches beat loose ones
- Search now forgives typos and punctuation — "beyonse" finds Beyoncé, "dont stop me now" finds Don't Stop Me Now
- Plex tracks you've loved now show their heart in search results
- Search now shows a "No Results" screen when nothing matches instead of a blank list
- Fixed Plex songs missing from search — tracks are no longer dropped when the server omits optional details like media info or artwork from search responses
- Search results now stay put when you open a song or album and come back — the list no longer reshuffles or reloads behind you
- Multi-service search results now appear all at once instead of shifting around as each service finishes loading
- If your Plex library has the same album in more than one quality, each copy now shows its own artwork, albums show their track count, and songs show their format and bitrate (like "FLAC • 1411 kbps"), so it's easy to tell editions apart
- Album rows in search now show the number of songs across Apple Music, Spotify, Tidal, Deezer, and Plex — handy for telling a deluxe edition from the standard one
- The Plex library filter now works during a combined multi-service search too — filter your Plex results by library while other services' results stay put
- Turning a service off in Settings now removes it from the search selection right away — previously a disabled service could stay selected in the search menu
- Spotify search now includes artist radio — start a station from the top artist matches right in the results
- Search filters now cover every service you're searching — with Apple Music as an extra service, the Radio and Library filters show up like they should
- The search start screen now shows each selected service's sections (like Spotify's browse or Apple Music playlists) even when that service isn't the primary one
- Spotify albums now rank by popularity, so searching an album like Frozen surfaces it near the top instead of below every song — and albums containing explicit tracks now show the explicit badge
- Apple Music search now uses Apple's own Top Results to rank its hits higher, matching the ordering you see in the Music app
- Improved Plex speed and reliability — Clic picks the fastest way to reach your server, automatically switches connection when you change networks, and no longer hangs on an unreachable server
- The Refresh Sonos Library button in Preferences now shows your music library's shared folder location underneath, so you can see where Sonos is reading your music from
- Improved Spotify responsiveness — albums and playlists load noticeably faster and start showing results sooner
- Fixed Spotify albums with more than 50 tracks not showing every track, and an album sometimes showing the previous album's tracks when navigating back and forth
- Fixed the Spotify Albums library list shrinking and reshuffling each time you reopened it — it now loads your full library and stays put
- Fixed sheets like Add to Playlist unexpectedly closing on iPad and Mac when the Queue was open in the side panel; the Queue now also stays with the speaker you have selected as you resize or rotate
- Fixed the now-playing track not being highlighted in Plex albums and playlists
- Fixed opening a Plex artist from a song's "View Artist" showing no albums
- Shuffling the queue now animates tracks sliding into their new order instead of jumping
- Fixed the Queue inspector needing two clicks to open on Mac
- Improved streaming service reliability — fixed a token-refresh timing issue that could make requests fail as "signed out" even when your session was still valid

# 2026.5

–– New Features ––
- Deezer: Full Deezer integration — search tracks, albums, artists, and playlists, browse Deezer charts, view album and artist pages, start a Mix from any track or artist, and open content directly in the Deezer app
- Listen with Clic: A second share sheet action that appears in the Actions row — share any song, album, or playlist link and queue it to any room without leaving your current app
- Queue Position: Choose how a shared link is queued — Play Now, Play Next, Add to Last, or Replace Queue — right from the share sheet; playlists default to Replace
- TV Mode Controls: Night mode, speech enhancement, and mute buttons now appear in the mini player when a Sonos soundbar is in TV mode — artwork swaps to a TV icon and the audio input format is shown in place of the track name
- Favorite Albums: Save a Spotify album or love an Apple Music album directly from search results or the album detail page
- Volume Buttons: Use the iPhone's physical volume buttons to control your Sonos speaker volume on the player screen — enable the toggle in Playback preferences
- Plex Track Ratings: Rate Plex tracks with a heart from the player or the track menu — the heart fills based on your 1–5 star rating and a badge appears on rated tracks in your library
- Popular Tracks: Artist pages for Plex and library artists now show a Popular Tracks section ordered by global popularity, sourced from Last.fm and powered by Audioscrobbler
- Start Live Activity Shortcut: New shortcut and Control Center widget (iOS 18+) to start a Live Activity for any speaker — configure a speaker once and tap to get Now Playing on your Lock Screen instantly

–– Bug Fixes & Improvements ––
- Mac Dock Menu: Reordered menu items — transport controls and Now Playing are at the bottom (closest to the Dock icon), with Sleep Timer at the top; Repeat, Shuffle, and Crossfade grouped under a "Playback" section; Favorite moved into the Now Playing group
- Fixed speaker discovery incorrectly reporting "On Cellular" and refusing to connect when Wi-Fi Assist is enabled — the app now connects whenever Wi-Fi or Ethernet is available
- Apple Music artwork now loads as a square crop instead of a letterboxed image with white padding
- Play Folder: Playing an Apple Music playlist folder now queues all playlists in order — first replaces the queue, the rest append automatically
- Fixed a crash that could occur when play history or queue data stored by a different app version contained an unrecognized music service
- Fixed artwork flickering when skipping between tracks on the same Spotify album, including albums with featured artists
- Right-clicking or long-pressing a single queue track now offers the full set of actions — Add to Playlist, View Album, View Artist, and Play Next — in both Up Next and Full Queue on iPhone, iPad, and Mac
- Fixed the music service icon in the search and library menus being hard to tap on iOS 26, and restored its brand color and size
- Search and library results now lay out in a two-column grid, so you see more at a glance
- SoundCloud Library: Liked Songs and Playlists now lay out in a two-column grid with a filter button to reorder or hide sections, matching the Apple Music and Spotify libraries

# 2026.4

–– New Features ––
- Share Sheet: Completely rebuilt the "Play on Clic" share extension. Share song, album, playlist, or artist links from Apple Music or Spotify on iPhone, iPad, and Mac and queue to any room or group instantly
- Artist Sharing: Sharing an artist link offers Play Radio (starts that artist's radio on selected rooms) and Show (jumps to the artist page in Clic)
- Apple Music Stations: Share any Apple Music station link (including personalized stations) to queue and play it on Sonos
- Tap the artwork header in the share sheet to open that album/playlist/artist in Clic
- Mac Dock Menu: Right-click the Clic icon in the Dock for full playback control without opening the app — Now Playing, play/pause, skip, volume, mute, and Repeat / Shuffle / Crossfade
- Dock Menu: Switch the active speaker or group, favorite the current song, and set a sleep timer (15/30/45 minutes or 1 hour) — all from the Dock
- Tap the now-playing track in the Dock menu to jump straight to that speaker in Clic
- Sleep Timer: New "End of Song" option ends playback when the current track finishes — available in the app's Sleep Timer menu and the Mac Dock menu
- Shortcuts: "Play Link on Clic" with a clearer "Add to Queue" parameter and a new "Automatic" default that matches the share sheet behavior (playlists replace the queue, everything else plays now)
- Playback Control Widget (iOS 18+): New Control Center widget for per-speaker play/pause with live transport state
- Welcome: Brand-new first-launch onboarding — guided Local Network setup, live speaker discovery with per-speaker haptics, a music services review showing what's ready to play, and an optional newsletter signup
- Households: Redesigned system switcher shows each household's speakers and an S1/S2 badge, with a clearer "Switch system" hint
- Newsletter: Sign up for product updates from a new row in Preferences (also available during onboarding)

–– Bug Fixes & Improvements ––
- Restored Live Activity to its former glory with 5 volume steps
- Dock Menu: Volume Up / Down now adjusts by 2% by default; hold Option for a 5% jump
- Clic Mini: Menu bar window now smoothly grows and shrinks when expanding a group's per-speaker volume controls
- Improved Player screen performance: reduced unnecessary view updates on foreground, inspector toggle, hover, and resize for smoother behavior on Mac
- Fixed Custom Sleep Timer not showing
- Fixed Apple Music links without a slug (e.g. `music.apple.com/us/album/<id>`) failing to open
- Fixed Apple Music station links not parsing in the share sheet, Shortcuts, or "Open in Clic" — station name is now derived from the URL when richer metadata isn't available
- Open in Clic now falls back gracefully when the share extension can't resolve a link, letting the main app handle lookup
- New "View in Clic" routes auto-detect artist vs album/playlist content and open the right detail screen; stations open the room picker since they have no detail page
- Spotify Library: Playlists now navigate to playlist detail instead of playing immediately
- Spotify Library: Albums and Liked Songs lists no longer show unnecessary alphabetical section index
- Spotify Library: "See All" for Playlists now navigates to the full playlist browser
- Improved list pagination: next page loads earlier as you scroll, instead of waiting until the very last item
- Removed loading overlay on playable lists for smoother, faster navigation
- Plex Search: Playlists now appear in search results when a library filter is active
- Fixed a rare crash that could occur when adjusting room volume, using filters, or deleting alarms
- Fixed a long-standing crash that could occur during background speaker updates, especially when groups changed while the app was loading status
- Fixed Song Radio and Artist Radio not starting
- Fixed Clic Mini reordering on playback buffering.
- Fixed sleeping speakers (like Move and Move 2) not appearing in the room list, which also prevented them from being woken automatically
- Speaker row now always shows the battery icon with the right level glyph, plus a warmer tint when low or charging — not just when plugged in
- Sleeping/off speakers now display the sleep icon, status, and a relative "last seen" time on the row
- Local Network permission is now requested only after you start onboarding, not on first launch
- Speaker Settings list now uses the speaker icon and shows the model name as a subtitle
- Queue header now shows the count inline as "Queue (50)"; Up Next reports how many tracks are left instead of the full queue size
- Clic Mini: Redesigned the keyboard-shortcut notification — a cleaner now-playing card with larger artwork, song, and artist, plus a brief skip indicator when you change tracks
- Clic Mini: Volume and track-skip notifications now appear instantly when you press the shortcut instead of lagging behind
- Clic Mini: Tap the notification to dismiss it
- Fixed the Clic Mini notification sometimes disappearing abruptly instead of fading out

# 2026.3

- Apple Live Radio: Play Apple Music live radio stations (Apple Music 1, Apple Music Hits, Apple Music Country) directly on your Sonos speakers, with a new Radio filter in search
- Favorite Songs: Favorite songs on Apple Music, Spotify, and SoundCloud from the player screen or any track's context menu. Apple Music favorites are added to your Favorite Songs playlist and work on both iOS and Mac
- Share to Watch: Easily connect any Apple Watch to your Sonos system by generating a pairing code on your iPhone. Works with guest watches or when troubleshooting connection issues
- Sleep Timer in Scenes: Add a sleep timer when creating a scene so playback automatically stops after a set duration
- Mini player now hides automatically when editing a playlist, sliding back in when done
- Fixed Clic Mini not scrolling when many speakers exceed screen height
- Improved Mac performance: reduced CPU usage during window resizing, especially with the queue open
- Clic Mini: Individual speaker volume controls and grouping/ungrouping directly from the menu bar

–– Bug Fixes & Improvements ––
- Fixed Clic Mini losing real-time updates when speakers are grouped or ungrouped
- Fixed tracks not playing in the correct order when selecting a specific track from an album or playlist in shuffle mode
- Play Next when swiping now only queues tracks

# 2026.2

–– New Features ––
- Redesigned Artist Page: Full-bleed hero artwork with blur effect, stretchy parallax scrolling, artist name and actions overlaid on artwork, collapsible Popular and Albums sections, and Open in Service button
- Popular Tracks: Library artists now show popular tracks ordered by Apple Music popularity instead of arbitrary order
- New Artist Action Buttons: Radio, Popular, and Discography buttons now appear below artist name with glass styling
- Artist Actions Menu: Ellipsis menu provides Play Next, Add to Queue, Replace Queue options for both Popular tracks and Discography
- Add Popular to Playlist: Add all popular tracks to a new or existing Sonos playlist directly from the artist page
- Queue feedback now shows track/album counts (e.g., "Playing 10 songs next", "Added 5 albums to queue")
- Redesigned Album & Playlist Page: Full-bleed hero artwork with blur effect, stretchy parallax scrolling, album info (year, song count, duration) overlaid on artwork, tappable artist name to navigate to artist, and glass-style Play/Shuffle buttons
- Navigation titles on artist and album pages now fade in as you scroll past the artwork
- Quick Add to Playlist: Tap the alert after adding a song to a playlist to navigate directly to that playlist
- Add to Last Playlist: Quickly add the current song to your most recently used playlist from the menu or with ⌘S on Mac
- New Playlist command in File menu (⌘N) for quick playlist creation
- Add to Playlist submenu in File menu for Mac users
- "Add to [Playlist Name]" appears in context menus throughout the app when you have a recent playlist
- Previous button now restarts the current song if more than 3 seconds in, matching Sonos app behavior
- Added Sleep Timer shortcuts for quick access to common durations
- Added fallback album art for TuneIn stations
- Added shuffle and repeat indicators to queue icon on iPad and Mac
- Artwork now hides gracefully in compact window sizes for better layout
- Added cellular network detection: App now shows "Connect to Wi-Fi" message when on cellular and automatically resumes discovery when returning to Wi-Fi
- Redesigned speaker selection screen with improved layout and real-time updates
- Song title now shown below speaker name with accent color when playing
- Volume displayed on far right for cleaner look
- Tap to select, long-press for menu options (Only This Speaker, Mute/Unmute)
- "Everywhere" toggles to "Deselect All" when all speakers selected
- Playing speakers automatically sorted to top
- Content stays fixed at top while scrolling speaker list
- New keyboard shortcuts on Mac: Seek Forward/Backward (⌥→/⌥←), Shuffle (⌘S), Repeat (⌘R), Open Album (⇧⌘I), Open Artist (⌘I)
- Keyboard navigation in Search: Use arrow keys to navigate suggestions and results, Enter to play or open details, Escape to clear selection. Hold arrow keys to repeat.
- Unplayable Apple Music tracks now shown as disabled on album pages
- Recent Searches: Horizontal scroll bar on search screen shows recently visited artists and albums as tappable artwork for quick access
- Recent Search Queries: Last 3 search queries appear as keyboard suggestions when opening search
- Move Next in Queue: Move any track to play next directly from the queue menu, with animated reordering

–– Bug Fixes & Improvements ––
- Fixed Intents prompting twice
- Fixed duplicate tracks appearing in Popular section on library artist pages
- Apple Music catalog artists now prioritized over library artists in search results
- Popular section now shows loading spinner while fetching tracks and "No tracks found" when unavailable
- Fixed scene music content being lost after navigating to the speaker selection screen and returning
- Add Sonos created playlists not showing in search
- Fixed adding Spotify and Apple Music tracks to Sonos playlists
- Added Clear Image Cache option in Settings to free up storage space
- Added position numbers to queue list for easier track navigation
- Fixed album name missing from metadata in search results
- Improved scroll performance throughout the app
- Fixed Volume slider animation
- Fix missing albums on some plex artists, i.e. soundtracks
- Albums and playlists now show a "No Tracks" empty state instead of an infinite spinner when content is unavailable
- Fixed shuffle not being applied correctly when queueing albums and playlists
- Navigation within album and artist detail sheets now works (e.g. tapping artist name from an album)

# 2026.1

–– New Features ––
- Fullscreen artwork mode: Toggle with Shift+Command+F or via the Player Screen menu
- State is now restored for the selected group upon app relaunch
- Queue selection is preserved and restored on app restart
- Added option in settings to set default behavior for Replace Queue playback
- Browse now persists its location
- Tappable song and artist names on the Player Screen with hover effects to quickly navigate to album and artist details
- Added letter sections to Sonos Library Artists and Albums
- Added Playlists to SoundCloud
- Added Help section

–– Bug Fixes & Improvements ––
- Fixed title parsing
- Fixed an issue where artwork wasn't updating for TuneIn
- Fixed an issue where the Live Activity volume stepper value would not appear in Preferences
- Fixed an issue with prioritizing the Plex Server remote access URL
- Fixed an issue where the Spotify Library would not refresh correctly
- Fixed missing artwork for Apple Library Artists


# 2025.18

–– New Features ––
-

–– Bug Fixes & Improvements ––
- Fix Port not showing in Line In
- Fix Alarm not working with Apple Music
- Fix queuing Top Songs for Artist
- Fix flickering on Mac

# 2025.17

–– New Features ––
- "End All Live Activities" intent for Sonos speakers (Shortcuts & Control Center)
- Customize sections in Apple Music and Spotify
- Album artwork added to recently played metadata
- Shortcuts for fast speaker group/ungroup actions
- Playlist and album info now shown on Player Screen
- Mute rooms via Shortcuts
- "Play All" for Liked/Loved songs (Spotify, SoundCloud)
- Adjustable Live Activity volume step

–– Bug Fixes & Improvements ––
- Fixed Live Activity crash
- Restored missing icons (SoundCloud, TuneIn)
- Improved Sonos Library metadata accuracy
- Fixed SoundCloud playlist loading
- Improved Tidal playback and album art reliability
- Fixed iPad Mini widget layouts
- Added "Clear All" to text fields
- Added user playlist endpoint for Apple and Plex

# 2025.16

–– New Features ––
- Shortcuts now support custom tint colors for better visual organization
- Enhanced Plex integration with library selection in search results
- Queue total now displays in Clic Mini for better playback visibility
- Added library filtering capabilities for Plex content

–– Bug Fixes & Improvements ––
- Enhanced audio metadata lookup for more accurate track information
- Resolved stability issue causing crashes in Clic Mini
- Fixed song change notifications not updating correctly in Clic Mini
- Optimized caching performance in Clic Mini for faster response times

## Store

# 2025.15

–– New Features ––
- Introduced speaker grouping in Clic Mini: Easily group and ungroup speakers directly from the menu bar, with instant feedback and improved reliability. Grouping actions now update in real time and are accessible via the context menu for each device.
- Clic Mini Updated for os 26 with HotKeys
- Clic Mini has been completely rebuilt for a faster, more reliable, and more responsive experience. Enjoy smoother performance, improved stability, and a more intuitive interface throughout the app.
- Playback icon now accented when playing
- Pin Speaker Feature: Pin any speaker to prioritize it for menu bar display and keyboard shortcuts
- Menu Bar Song Title Toggle: Option to hide/show song titles in the menu bar
- Enhanced Global Media Controls: Keyboard shortcuts now prioritize pinned speakers
- Improved Pin Button: Larger tap target for easier interaction
- Add open artist in Music Service
- Add show alarms in View iPad menu bar
- Add sound quality info to Clic Mini

–– Bug Fixes & Improvements ––
- Improved error messages for playback failures: Users now receive clearer, more actionable feedback when content cannot be played due to service issues.
- Fix layout issues on Album details view
- More improvements for os 26
- Resolved issue with oversized icons on Mac Catalyst
- Corrected album details display on OS 26
- Restored missing music service icons
- Update MarqueeText for better performance
- Improved Clic Mini Performance
- Fix EQ number formatting on speaker settings
- Enhanced Settings View: Added pinned speaker management and clearer keyboard shortcut descriptions
- Visual Feedback: Pinned speakers now show subtle accent border for better identification
- Persistent Settings: Pin preferences and menu bar display options saved between app launches
- Improve Alarms

## Store

2025.15
–– New Features ––
Clic Mini: Redesigned and Rebuilt
Clic Mini has been completely reimagined for macOS 26, delivering a faster, more reliable experience with improved stability and an intuitive interface.
Speaker Grouping Made Easy
Group and ungroup your speakers directly from the menu bar with instant feedback. All grouping actions update in real time and are accessible via the context menu for each device.
Pinned Speakers
Take control of your workflow by pinning your favorite speakers. Pinned speakers are prioritized in menu bar displays and keyboard shortcuts, ensuring your most-used devices are always within reach. Visual indicators with subtle accent borders make pinned speakers easy to identify.
Enhanced Controls and Customization

HotKeys Support: Navigate and control playback faster with new keyboard shortcuts
Menu Bar Customization: Toggle song title visibility in the menu bar to match your preferences
Visual Feedback: Active playback is now indicated with an accented icon
Improved Touch Targets: Enlarged pin button for easier interaction

Additional Features

Open currently playing artist directly in your music service
View alarms from the iPad menu bar
Check sound quality information at a glance

–– Bug Fixes and Improvements ––
Reliability and Performance

Enhanced error messaging provides clearer, actionable feedback when content fails to play
Improved MarqueeText rendering for smoother performance
Fixed EQ number formatting in speaker settings
Optimized overall Clic Mini performance

Visual Refinements

Resolved oversized icon issues on Mac Catalyst
Fixed layout problems on album details view
Restored missing music service icons
Corrected album details display for macOS 26

Settings and Preferences

Pin preferences and menu bar display options now persist between app launches
Improved settings view with clearer keyboard shortcut descriptions
Enhanced alarm management

# 2025.14

–– New Features ––
- Add grouped speakers to speaker selection screen
- Add popover for room speakers
- New design for iOS 26:
  - MiniPlayer Updated

–– Bug Fixes & Improvements ––
- Improve volume controls
- Fix Line In support for Connect
- Fix Tidal not showing search results
- Fix Play Action not showing Spotify
- Fix Tidal Results not showing

# 2025.13

–– New Features ––
- Add music to scenes
- Create scenes from music
- Rearrange and edit scenes
- Add ability to like and remove SoundCloud songs
- Add support to add, remove, and reorder songs in Sonos playlists
- Add discography button to artist pages

–– Bug Fixes & Improvements ––
- Fixed issue where "Open In Music Service" would disappear
- Fixed issue where duplicates were not shown in playlists
- Fixed Now Playing sorting on Mac and iPad
- Fixed "Replace Queue" not appearing for library albums
- Fixed swipe to delete in queue not removing the correct item
- Fixed Play Popular Songs not switching to the queue
- Fixed issue where "All" in local library was not displayed
- Improved overall speed and performance
- Improved drag and drop for playing tracks from Spotify and Apple Music
- Fixed a case where Plex server could not be discovered
- Fixed issue with blank album art line


## ChangeLog

# 2025.12

–– New Features ––
- Added SoundCloud browse library to show Liked Tracks
- Added batch editing functionality to Queue for managing multiple tracks at once
- Added Up Next view to display upcoming items in the queue
- Added Connectivity screen, allowing manual IP address assignment
- Added Recommended Albums section to Apple Music library with personalized album suggestions
- Add Mute Button to Live Activity, Speaker List, and Widgets
- Add pull to refresh Local Sonos Library
- Add Apple Music Playlist folders
- Add Library Folders
- Support multiple Apple accounts.

–– Bug Fixes & Improvements ––
- Fixed an issue where some speakers would be hidden on Watch and Clic Mini with radio playback
- Resolved an issue where artwork was not displayed for library artists
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
- Add Library Folder support.

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
