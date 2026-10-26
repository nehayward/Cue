// Copy for the home page. Pages only lay this out, so edits to wording,
// order, or which features are listed happen here. Icons are Lucide names
// from src/lib/icon-paths.js.

export const hero = {
	eyebrow: 'Music player · Sonos controller',
	title: 'Your music.\nHere, or everywhere.',
	lede: 'Cue plays Apple Music, Plex, Subsonic, radio, audiobooks and your own files on your iPhone — then hands the same queue to any Sonos speaker with one tap.',
	// Shown under the buttons, each with its device glyph from src/lib/icon-paths.js.
	devices: [
		{ icon: 'iphone', name: 'iPhone' },
		{ icon: 'apple-watch', name: 'Apple Watch' },
		{ icon: 'carplay', name: 'CarPlay' },
	],
};

// "One queue, two places" — the idea that makes Cue different.
export const handoff = {
	title: 'One queue. Wherever you are.',
	lede: 'Cue is a complete music player on its own. Sonos is where it goes next, not what it needs.',
	// The hand-off picture: the phone, and rooms that join one by one. The animation is timed for exactly three rooms.
	screen: { file: 'shots/now-playing.jpg', alt: 'Cue’s Now Playing screen' },
	device: 'This iPhone',
	rooms: ['Living Room', 'Kitchen', 'Bedroom'],
	steps: [
		{ icon: 'smartphone', title: 'Plays on your device', body: 'Every song, album and station plays right here — no speaker, no network, no problem.' },
		{ icon: 'arrow-left-right', title: 'Hands off to Sonos', body: 'Tap Play On and the queue moves to any room or group, right where you left it.' },
		{ icon: 'speaker', title: 'Controls the whole house', body: 'Group rooms, set each one’s volume, play any speaker’s line-in and set alarms — on every speaker you own.' },
	],
};

// The hero's fanned phones, front one first. `finish` picks the frame colour:
// 'orange' (Cosmic Orange) or leave it out for dark titanium. Web-sized JPEGs live in
// public/shots/; the full-resolution originals are in public/press/.
export const screens = [
	{ file: 'shots/now-playing.jpg', finish: 'orange', alt: 'Cue’s Now Playing screen, with playback controls and speaker volume' },
	{ file: 'shots/plex-library.jpg', alt: 'Cue showing a Plex library: Artists, Albums, Songs, Downloaded and Playlists' },
	{ file: 'shots/radio.jpg', alt: 'Live radio from TuneIn and Apple Music in Cue' },
];

// Big alternating sections between the hand-off and the feature grid. Swap a
// `screen` for a closer match when there's a screenshot of that feature. A
// `link` adds a "more" line under the points.
export const spotlights = [
	{
		eyebrow: 'Library',
		title: 'Your whole library, instantly.',
		body: 'Cue syncs your Plex or Subsonic library once and keeps it on your phone. Songs opens complete, search filters every track as you type, and every list sorts the way you like.',
		points: ['Title, artist, album, year, play count or date added', 'Plex editions labelled with format and bitrate', 'Plays counted back on your server'],
		screen: { file: 'shots/albums.jpg', alt: 'Albums from a Plex library in Cue' },
	},
	{
		eyebrow: 'Audiobooks',
		title: 'Built for books, not just songs.',
		body: 'Your Plex and Audiobookshelf books play as books: chapters, speed for each one, Smart Resume that picks up between words, and a history of every place you’ve been. Start a chapter, then Back to Music picks your playlist up where it was.',
		points: ['Plex and Audiobookshelf, side by side', 'Read Along: each word lit as it’s read', 'In CarPlay, on Apple Watch and on Sonos'],
		screen: { file: 'shots/book-player.jpg', alt: 'Cue playing an audiobook, with the chapter over the title and 15 and 30 second skips' },
		link: { href: '/audiobooks', label: 'Everything Cue does for audiobooks' },
	},
	{
		eyebrow: 'Offline',
		title: 'Downloads for the road.',
		body: 'Download songs, albums and playlists from Plex and Subsonic. With no signal, Cue shows just what’s on your phone and keeps playing.',
		points: ['Offline Mode for planes and tunnels', 'Streaming quality you choose, MP3 or Opus', 'Smooth hand-off between your server and Apple Music'],
		screen: { file: 'shots/plex-library.jpg', alt: 'A Plex library in Cue, with a Downloaded section', finish: 'orange' },
	},
	{
		eyebrow: 'Radio',
		title: 'Live radio, word for word.',
		body: 'Thousands of TuneIn stations and Apple Music’s live radio. Tap captions to read what’s being said, transcribed live and entirely on your iPhone.',
		points: ['Trending stations and browse by genre or place', 'Apple Music 1, Hits, Country and more', 'Live Transcription on iOS 26 and later'],
		screen: { file: 'shots/radio.jpg', alt: 'Live radio from TuneIn and Apple Music in Cue' },
	},
];

// Cue beyond the phone: two cards between the spotlights and the feature grid.
// Both play on the device, never on Sonos.
export const beyondPhone = {
	title: 'In the car. On your wrist.',
	lede: 'The same player goes where you go, with no speaker needed.',
	list: [
		{
			icon: 'carplay',
			name: 'CarPlay',
			body: 'Your libraries, audiobooks, downloads and radio stations on the car’s screen. In the car, Cue always plays from your iPhone.',
			points: ['Home, Audiobooks, Downloads and Radio', 'Up Next, shuffle and repeat in Now Playing', 'A book’s chapters and speed, right in Now Playing'],
		},
		{
			icon: 'apple-watch',
			name: 'Apple Watch',
			body: 'Put Plex and Subsonic music, and your audiobooks, on your watch and leave your iPhone at home. Browse and search your server right from your wrist.',
			points: ['Add to Apple Watch from any album, playlist, song or book', 'Plays from the watch, with your book’s place synced back', 'Controls your iPhone’s music too, Up Next included'],
		},
	],
};

export const features = [
	{ icon: 'search', title: 'Universal Search', body: 'Search several services at once and get one ranked list that forgives typos.' },
	{ icon: 'wifi-off', title: 'Offline Mode', body: 'Download from Plex and Subsonic and keep listening on a plane or in a tunnel.' },
	{ icon: 'server', title: 'Your Own Server', body: 'Plex, Navidrome and any Subsonic server, with plays counted back on the server.' },
	{ icon: 'audio-waveform', title: 'Streaming Quality', body: 'Stream lossless at home, or MP3 and Opus at a bitrate you pick on cellular.' },
	{ icon: 'mic-vocal', title: 'Lyrics', body: 'Sing along line by line, from your server’s own lyrics, your files, or LRCLIB.' },
	{ icon: 'captions', title: 'Read Along', body: 'See a book’s words as they’re read, transcribed on your iPhone. Tap a word to look it up.' },
	{ icon: 'radio', title: 'Live Transcription', body: 'Read what a radio station is saying, transcribed live and entirely on your device.' },
	{ icon: 'list-music', title: 'Playlists, Edited', body: 'Create playlists, add songs to several at once, reorder, and undo.' },
	{ icon: 'shuffle', title: 'A Queue You Can Edit', body: 'Drag, remove or play next any song, played ones too. Shuffle keeps the real order behind it.' },
	{ icon: 'lock-keyhole', title: 'Lock Screen Controls', body: 'Your speaker in the Lock Screen player, with the volume buttons to match.' },
	{ icon: 'play', title: 'Song Previews', body: 'Hear a quick clip of any Apple Music song before you play it.' },
	{ icon: 'alarm-clock', title: 'Sleep Timer & Sonos Alarms', body: 'Fall asleep to a book or playlist on your iPhone, and wake up to music on your Sonos speakers.' },
	{ icon: 'cable', title: 'Line In, Anywhere', body: 'Play the turntable on one speaker in any room or group of the house.' },
	{ icon: 'house', title: 'Every Home', body: 'S1 and S2 systems, and more than one house, a tap apart.' },
	{ icon: 'tv', title: 'Home Theater', body: 'Night mode, speech enhancement and lip sync for Sonos soundbars.' },
];

// Free and Cue Super, side by side. Keep the Super list in step with the
// app's paywall (CuePaywall.comparisonRows): what's listed here is what
// Super unlocks. No prices until the products are on the App Store.
export const plans = {
	title: 'Free to start. Super for more.',
	lede: 'Cue is free to download and plays every service. Cue Super lifts the limits and adds a few extras.',
	free: {
		name: 'Free',
		price: '$0',
		points: ['Every service, on your iPhone', 'CarPlay and Apple Watch', '50 downloads, shared with your watch', 'One Sonos room'],
	},
	super: {
		name: 'Cue Super',
		price: 'Free trial',
		points: ['Unlimited downloads on iPhone and Apple Watch', 'Audiobook downloads', 'Read along with any book', 'Every Sonos room, grouped any way'],
	},
};

// Only services that play both on the device and on Sonos belong here
// (see Ideas/device-first-services.md in the app repo).
export const services = {
	title: 'Every service plays on both.',
	lede: 'If Cue can play it on your device, it can play it on Sonos — no exceptions, no “speaker only” fine print.',
	list: [
		// `mark` is a logo from src/lib/brand-marks.js; `icon` a Lucide icon
		// for services without a usable mark.
		{ name: 'Apple Music', detail: 'Catalog, library and live radio', mark: 'applemusic' },
		{ name: 'Plex', detail: 'Your server, at home or away', mark: 'plex' },
		{ name: 'Subsonic', detail: 'Navidrome, Airsonic, Gonic and more', icon: 'server', color: '#60a5fa' },
		{ name: 'Audiobookshelf', detail: 'Your audiobooks, from your own server', icon: 'book-open', color: '#fbbf24' },
		{ name: 'TuneIn', detail: 'Thousands of live stations', icon: 'radio', color: '#2dd4bf' },
		{ name: 'Your Files', detail: 'A folder on your device or in iCloud', icon: 'music', color: '#a1a1aa' },
	],
};


export const faq = [
	{
		q: 'Do I need Sonos speakers?',
		a: 'No. Cue is a complete music player on its own. If you have Sonos, switch it on in onboarding or later in Settings ▸ Sonos, and every song can move to a speaker.',
	},
	{
		q: 'Which services does Cue support?',
		a: 'Apple Music, Plex, Subsonic-compatible servers (Navidrome, Airsonic, Gonic and more), Audiobookshelf, TuneIn radio, and music files on your device or in iCloud Drive. Audiobooks play from Plex and Audiobookshelf.',
	},
	{
		q: 'Does Cue play audiobooks?',
		a: 'Yes, from Plex and Audiobookshelf, with chapters, a speed for each book, Smart Resume and a history of every place you’ve been. Books play beside your music, in CarPlay, on Apple Watch and on Sonos. [See what Cue does for audiobooks](/audiobooks).',
	},
	{
		q: 'Does Cue work with Audiobookshelf?',
		a: 'Yes. Connect your server under **Settings ▸ Services ▸ Audiobookshelf** with its address, username and password, and your books, series and authors appear in the Audiobooks tab. Your place syncs with the server both ways, and books play on your iPhone, in CarPlay, on Apple Watch and on Sonos.',
	},
	{
		q: 'What does Cue Super add?',
		a: 'Unlimited downloads on your iPhone and Apple Watch (free downloads are 50 songs, shared between the two), downloading audiobooks, reading along with a book as it plays, and every Sonos room. Free, Cue plays on one Sonos room. One purchase covers every Cue app.',
	},
	{
		q: 'How does Read Along work?',
		a: 'While a book plays, tap the quote button to see its words as they’re read, transcribed privately on your iPhone with nothing sent anywhere. It’s read a few minutes ahead of you, downloaded or streamed from Plex or Audiobookshelf, so each word lights up as it’s said. It needs iOS 26 or later and Cue Super.',
	},
	{
		q: 'Why isn’t Spotify supported?',
		a: 'Every service in Cue has to play on your device as well as on a speaker. Spotify doesn’t let other apps play its music, so it could only ever work while a Sonos speaker is around.',
	},
	{
		q: 'Which Sonos systems work?',
		a: 'S1 and S2, including homes that run both, and more than one household. Cue finds your speakers on the network automatically.',
	},
	{
		q: 'Which devices does Cue run on?',
		a: 'Cue is for iPhone, and works with CarPlay. It also has an Apple Watch app that plays Plex and Subsonic music and audiobooks downloaded to the watch, with no iPhone needed.',
	},
];
