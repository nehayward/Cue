// Copy and downloads for /press. Assets live in public/press/; add
// screenshots there and list them in `screenshots` to show them on the page.

export const about = {
	tagline: 'Your music. Here, or everywhere.',
	short: 'Cue is a music player for iPhone that plays Apple Music, Plex, Subsonic, radio and your own files — on your phone, or on any Sonos speaker.',
	long: [
		'Cue is a complete music player first. It plays Apple Music, Plex, Navidrome and other Subsonic servers, TuneIn radio and your own files right on your iPhone, with universal search, offline downloads, streaming quality settings and live radio transcription.',
		'When you’re home, one tap on Play On hands the same queue to any Sonos room or group. Every service in Cue plays both on the phone and on Sonos — Cue leaves out services that only a speaker can play, rather than offer half of one.',
		'Cue comes along when you leave, too. CarPlay puts your libraries, downloads and radio on the car’s screen, and the Apple Watch app downloads Plex and Subsonic music to the watch, so it plays with no iPhone nearby.',
	],
};

export const facts = [
	{ label: 'Platform', value: 'iPhone, Apple Watch, CarPlay' },
	{ label: 'Services', value: 'Apple Music, Plex, Subsonic (Navidrome, Airsonic, Gonic…), TuneIn, your files' },
	{ label: 'Sonos', value: 'Optional. S1 and S2 systems, multiple homes' },
	{ label: 'Developer', value: 'Nick Hayward, independent, Seattle' },
	{ label: 'Availability', value: 'Coming soon to the App Store' },
];

export const highlights = [
	'Plays on the phone and on Sonos, with one tap to hand the queue across',
	'A first-class client for Plex and Subsonic servers, with offline downloads and play reporting',
	'Search across several services at once, in one ranked list',
	'Live, on-device transcription of radio stations',
	'CarPlay, and an Apple Watch app that plays Plex and Subsonic music with no iPhone nearby',
];

// { file: 'press/<name>.jpg', alt: '…' } — shown as a grid once added.
export const screenshots = [
	{ file: 'press/cue-now-playing.jpg', alt: 'Cue’s Now Playing screen' },
	{ file: 'press/cue-plex-library.jpg', alt: 'Cue showing a Plex library: Artists, Albums, Songs, Downloaded and Playlists' },
	{ file: 'press/cue-albums.jpg', alt: 'Cue’s Albums list from a Plex library' },
	{ file: 'press/cue-radio.jpg', alt: 'Cue’s Radio tab with trending TuneIn stations and Apple Music Radio' },
];

export const downloads = [{ file: 'press/cue-icon-1024.png', label: 'App icon', detail: 'PNG, 1024 × 1024' }];
