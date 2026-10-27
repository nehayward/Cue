// Copy and downloads for /press. Assets live in public/press/; add
// screenshots there and list them in `screenshots` to show them on the page.

export const about = {
	tagline: 'Your music. Here, or everywhere.',
	short: 'Cue is a music and audiobook player for iPhone that plays Apple Music, Plex, Subsonic, Audiobookshelf, radio and your own files, and hands your music to any Sonos speaker.',
	long: [
		'Cue is a complete music player first. It plays Apple Music, Plex, Navidrome and other Subsonic servers, TuneIn radio and your own files right on your iPhone, with universal search, offline downloads, streaming quality settings and live radio transcription.',
		'When you’re home, one tap on the Play On button hands the same queue to any Sonos room or group. Every streaming service in Cue plays both on the phone and on Sonos — Cue leaves out services that only a speaker can play, rather than offer half of one.',
		'Audiobooks get the same care. Books on Plex and Audiobookshelf play with chapters, a speed for each book, Smart Resume that picks up in a pause between words, and a history of every place the listener has been. Read Along shows the words as they’re read, transcribed on the iPhone.',
		'Cue comes along when you leave, too. CarPlay puts your libraries, audiobooks, downloads and radio on the car’s screen, and the Apple Watch app downloads Plex and Subsonic music and audiobooks to the watch, so they play with no iPhone nearby.',
	],
};

export const facts = [
	{ label: 'Platform', value: 'iPhone, Apple Watch, CarPlay' },
	{ label: 'Services', value: 'Apple Music, Plex, Subsonic (Navidrome, Airsonic, Gonic…), TuneIn, your files' },
	{ label: 'Audiobooks', value: 'Plex and Audiobookshelf' },
	{ label: 'Sonos', value: 'Optional. S1 and S2 systems, multiple homes' },
	{ label: 'Developer', value: 'Nick Hayward, independent, Seattle' },
	{ label: 'Availability', value: 'Coming soon to the App Store' },
];

export const highlights = [
	'Plays on the phone and on Sonos, with one tap to hand the queue across',
	'A first-class client for Plex and Subsonic servers, with offline downloads and play reporting',
	'Search across several services at once, in one ranked list',
	'Live, on-device transcription of radio stations',
	'Audiobooks from Plex and Audiobookshelf, with Smart Resume, a place history and Read Along',
	'CarPlay, and an Apple Watch app that plays Plex and Subsonic music and audiobooks with no iPhone nearby',
];

// { file: 'press/<name>.jpg', alt: '…' } — shown as a grid once added.
export const screenshots = [
	{ file: 'press/cue-now-playing.jpg', alt: 'Cue’s Now Playing screen' },
	{ file: 'press/cue-plex-library.jpg', alt: 'Cue showing a Plex library: Artists, Albums, Songs, Downloaded and Playlists' },
	{ file: 'press/cue-albums.jpg', alt: 'Cue’s Albums list from a Plex library' },
	{ file: 'press/cue-radio.jpg', alt: 'Cue’s Radio tab with trending TuneIn stations and Apple Music Radio' },
	{ file: 'press/cue-book-player.jpg', alt: 'Cue playing an audiobook, with the chapter over the title' },
	{ file: 'press/cue-audiobooks.jpg', alt: 'Cue’s Audiobooks tab with Continue Listening' },
	{ file: 'press/cue-book-chapters.jpg', alt: 'A book’s chapters in Cue, the current one filling as it’s heard' },
	{ file: 'press/cue-book-history.jpg', alt: 'A book’s History in Cue: every place the listener has been' },
];

export const downloads = [{ file: 'press/cue-icon-1024.png', label: 'App icon', detail: 'PNG, 1024 × 1024' }];
