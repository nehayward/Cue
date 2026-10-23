// Copy for the home page. Pages only lay this out, so edits to wording,
// order, or which features are listed happen here. Icons are Lucide names
// from src/lib/icon-paths.js.

export const hero = {
	eyebrow: 'Music player · Sonos controller',
	title: 'Your music.\nHere, or everywhere.',
	lede: 'Cue plays Apple Music, Plex, Subsonic, radio and your own files on your iPhone — then hands the same queue to any Sonos speaker with one tap.',
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
		{ icon: 'speaker', title: 'Controls the whole house', body: 'Group rooms, set volumes and alarms — on every speaker you own.' },
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
// `screen` for a closer match when there's a screenshot of that feature.
export const spotlights = [
	{
		eyebrow: 'Library',
		title: 'Your whole library, instantly.',
		body: 'Cue syncs your Plex or Subsonic library once and keeps it on your phone. Songs opens complete, search filters every track as you type, and every list sorts the way you like.',
		points: ['Title, artist, album, year, play count or date added', 'Plex editions labelled with format and bitrate', 'Plays counted back on your server'],
		screen: { file: 'shots/albums.jpg', alt: 'Albums from a Plex library in Cue' },
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
			body: 'Your libraries, downloads and radio stations on the car’s screen. In the car, Cue always plays from your iPhone.',
			points: ['Recents, Library, Downloads and Radio', 'Up Next, shuffle and repeat in Now Playing', 'Downloads that play with no signal'],
		},
		{
			icon: 'apple-watch',
			name: 'Apple Watch',
			body: 'Put Plex and Subsonic music on your watch and leave your iPhone at home. Browse and search your server right from your wrist.',
			points: ['Add to Apple Watch from any album, playlist or song', 'Plays from the watch, with no iPhone nearby', 'Siri, Shortcuts, widgets and double tap'],
		},
	],
};

export const features = [
	{ icon: 'search', title: 'Universal Search', body: 'Search several services at once and get one ranked list that forgives typos.' },
	{ icon: 'wifi-off', title: 'Offline Mode', body: 'Download from Plex and Subsonic and keep listening on a plane or in a tunnel.' },
	{ icon: 'server', title: 'Your Own Server', body: 'Plex, Navidrome and any Subsonic server, with plays counted back on the server.' },
	{ icon: 'audio-waveform', title: 'Streaming Quality', body: 'Stream lossless at home, or MP3 and Opus at a bitrate you pick on cellular.' },
	{ icon: 'captions', title: 'Live Transcription', body: 'Read what a radio station is saying, transcribed live and entirely on your device.' },
	{ icon: 'list-music', title: 'Playlists, Edited', body: 'Create playlists, add songs to several at once, reorder, and undo.' },
	{ icon: 'shuffle', title: 'A Queue That Remembers', body: 'Shuffle keeps the real order behind it, through edits and relaunches.' },
	{ icon: 'lock-keyhole', title: 'Lock Screen Controls', body: 'Your speaker in the Lock Screen player, with the volume buttons to match.' },
	{ icon: 'play', title: 'Song Previews', body: 'Hear a quick clip of any Apple Music song before you play it.' },
	{ icon: 'alarm-clock', title: 'Alarms & Sleep Timer', body: 'Wake up to any station or playlist, and fall asleep to one.' },
	{ icon: 'house', title: 'Every Home', body: 'S1 and S2 systems, and more than one house, a tap apart.' },
	{ icon: 'tv', title: 'Home Theater', body: 'Night mode, speech enhancement and lip sync for Sonos soundbars.' },
];

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
		q: 'Which music services does Cue support?',
		a: 'Apple Music, Plex, Subsonic-compatible servers (Navidrome, Airsonic, Gonic and more), TuneIn radio, and music files on your device or in iCloud Drive.',
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
		a: 'Cue is for iPhone, and works with CarPlay. It also has an Apple Watch app that plays Plex and Subsonic music downloaded to the watch, with no iPhone needed.',
	},
];
