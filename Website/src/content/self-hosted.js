// Copy for /self-hosted, the page for Plex, Navidrome and Subsonic users.
// Every claim here should match what the shipping app does.

export const intro = {
	eyebrow: 'Plex · Navidrome · Subsonic',
	title: 'Your server deserves a real player.',
	lede: 'Cue streams your own music library with the polish of Apple Music: instant search, offline downloads, the quality you choose, and plays counted back on your server. Then it sends the same songs to Sonos.',
};

export const servers = [
	{
		name: 'Plex',
		body: 'Sign in, pick your music library, and Cue finds the fastest way to your server — local at home, remote when you’re away.',
		points: ['Auto, Local or Remote connection', 'Every edition of an album, with format and bitrate', 'Loved tracks and ratings', 'Playlists you can create and edit'],
	},
	{
		name: 'Subsonic',
		body: 'Navidrome, Airsonic, Gonic and any server that speaks the Subsonic API. Add its address and login, and your password stays in the keychain.',
		points: ['Artists, Albums, Songs, Recently Added and Playlists', 'Artist pages with top songs and a playable discography', 'Starred songs', 'Playlists you can create and edit'],
	},
];

export const highlights = [
	{ icon: 'zap', title: 'Your whole library, instantly', body: 'Cue syncs your library once and keeps it on your phone, so Songs opens complete and search filters every track as you type.' },
	{ icon: 'list-music', title: 'Sort it your way', body: 'Title, artist, album, year, play count, date added or favorites — either direction. Each list remembers what you picked.' },
	{ icon: 'wifi-off', title: 'Offline Mode', body: 'Download songs, albums and playlists. On a plane, Cue shows just what’s on your phone and plays it without a hitch.' },
	{ icon: 'audio-waveform', title: 'Streaming quality', body: 'Play the original file, or have your server convert to MP3 or Opus at a bitrate you choose — smaller on cellular.' },
	{ icon: 'server', title: 'Plays count on your server', body: 'Songs you play show up in play counts, Recently Played and Now Playing. Navidrome passes them on to Last.fm or ListenBrainz.' },
	{ icon: 'search', title: 'Search everything together', body: 'Search your server alongside Apple Music and radio, and get one ranked list that forgives typos.' },
	{ icon: 'arrow-left-right', title: 'Mixes with Apple Music', body: 'Queue your server and Apple Music side by side. Cue looks ahead, so there’s barely a pause between them.' },
	{ icon: 'speaker', title: 'Straight to Sonos', body: 'Tap Play On and your speakers stream the same songs straight from your server. Opus is sent as MP3, since Sonos can’t play it.' },
	{ icon: 'watch', title: 'On your Apple Watch', body: 'Put albums, playlists and artists on your watch and go for a run without your iPhone. The watch downloads from your server itself, as MP3 or the original file.' },
	{ icon: 'car', title: 'In the car', body: 'Your library and downloads in CarPlay, with Up Next, shuffle and repeat on the car’s screen.' },
];

export const setup = [
	{
		title: 'Plex',
		steps: ['Open **Settings ▸ Services** and tap Plex.', 'Sign in with your Plex account.', 'Choose your server and music library. Leave the connection on **Auto**.'],
	},
	{
		title: 'Navidrome & Subsonic',
		steps: ['Open **Settings ▸ Services** and tap Subsonic.', 'Enter your server’s address, username and password.', 'Your library syncs in the background — start playing right away.'],
	},
];

export const faq = [
	{ q: 'Does my server need to be reachable from outside my home?', a: 'Only if you want to stream away from home. Plex handles this with remote access; for Navidrome or another Subsonic server, use whatever address you reach it at from outside — or download what you need before you leave.' },
	{ q: 'Where are my login details stored?', a: 'On your iPhone, with Subsonic passwords kept in the keychain. If you use Cue on Apple Watch, your iPhone shares them with the watch so it can download from your server. Cue talks to your server directly — nothing passes through anyone else.' },
	{ q: 'Does streaming quality affect Sonos?', a: 'Yes, for Subsonic: your speakers get the format you pick, except Opus, which Sonos can’t play, so they get MP3 instead.' },
	{ q: 'Which Subsonic servers work?', a: 'Any that implements the Subsonic API, including Navidrome, Airsonic, Airsonic-Advanced, Gonic and Ampache.' },
];
