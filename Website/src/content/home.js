// Copy for the home page. Pages only lay this out, so edits to wording,
// order, or which features are listed happen here. Icons are Lucide names
// from src/lib/icon-paths.js.

export const hero = {
	eyebrow: 'Music player · Sonos controller',
	title: 'Your music.\nHere, or everywhere.',
	lede: 'Cue plays Apple Music, Plex, Subsonic, radio and your own files on your iPhone — then hands the same queue to any Sonos speaker with one tap.',
	platforms: 'For iPhone',
};

// "One queue, two places" — the idea that makes Cue different.
export const handoff = {
	title: 'One queue. Wherever you are.',
	lede: 'Cue is a complete music player on its own. Sonos is where it goes next, not what it needs.',
	steps: [
		{ icon: 'smartphone', title: 'Plays on your device', body: 'Every song, album and station plays right here — no speaker, no network, no problem.' },
		{ icon: 'arrow-left-right', title: 'Hands off to Sonos', body: 'Tap Play On and the queue moves to any room or group, right where you left it.' },
		{ icon: 'speaker', title: 'Controls the whole house', body: 'Group rooms, set volumes and alarms — on every speaker you own.' },
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
		{ name: 'Apple Music', detail: 'Catalog, library and live radio' },
		{ name: 'Plex', detail: 'Your server, at home or away' },
		{ name: 'Subsonic', detail: 'Navidrome, Airsonic, Gonic and more' },
		{ name: 'TuneIn', detail: 'Thousands of live stations' },
		{ name: 'Your Files', detail: 'A folder on your device or in iCloud' },
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
		a: 'Cue is for iPhone.',
	},
];
