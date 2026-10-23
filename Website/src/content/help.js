// Questions on /help. Each `id` is a permalink (/help#<id>); the app links to
// some of them, so don't rename an id without checking the app for links.
// Answers are Markdown paragraphs (blank line between them) with **bold**,
// *italic* and [links](…); a line starting with "1. " or "- " starts a list.

export const requirements = [
	{ title: 'Device', body: 'iPhone. Cue also works with CarPlay, and has an Apple Watch app for watchOS 10 or later.' },
	{ title: 'Music', body: 'Apple Music, Plex, a Subsonic server, TuneIn, or your own files.' },
	{ title: 'Sonos (optional)', body: 'Any S1 or S2 system, on the same network as your device.' },
	{ title: 'Apple Music', body: 'Playing the Apple Music catalog needs an Apple Music subscription.' },
];

export const sections = [
	{
		title: 'Getting started',
		items: [
			{
				id: 'without-sonos',
				q: 'Can I use Cue without Sonos?',
				a: 'Yes. Cue is a music player first: search, library, queue and Now Playing all work on your device alone. Sonos is optional — turn it on in **Settings ▸ Sonos ▸ Use Sonos Speakers** whenever you like.',
			},
			{
				id: 'services',
				q: 'Which music services are supported?',
				a: '- **Apple Music** — the catalog, your library, and Apple’s live radio stations\n- **Plex** — your server, at home or remotely\n- **Subsonic** — Navidrome, Airsonic, Gonic and any Subsonic-compatible server\n- **TuneIn** — live radio\n- **Files** — a folder of music on your device or in iCloud Drive',
			},
			{
				id: 'spotify',
				q: 'Why isn’t Spotify (or Tidal, Deezer…) supported?',
				a: 'Every service in Cue must play on your device *and* on a speaker. Spotify, Tidal, Deezer, SoundCloud, Pandora and Sonos Radio only let a Sonos speaker play their music, so they could never work on your iPhone. Rather than offer half a service, Cue leaves them out.',
			},
			{
				id: 'subsonic',
				q: 'How do I connect a Subsonic or Navidrome server?',
				a: 'Open **Settings ▸ Services**, choose Subsonic, and enter your server’s address, username and password. Your password stays in your device’s keychain. Songs play straight from your server, on your device or on Sonos.',
			},
		],
	},
	{
		title: 'Sonos',
		items: [
			{
				id: 'connection',
				q: 'Cue can’t find my speakers.',
				a: '1. Make sure your device is on the same Wi-Fi network as your Sonos system.\n2. Allow **Local Network** access for Cue in **Settings ▸ Privacy & Security ▸ Local Network**.\n3. Open **Settings ▸ Sonos ▸ Connectivity** in Cue. Under *Can’t find your speakers?*, enter a speaker’s IP address (shown in the Sonos app under **Settings ▸ System ▸ About My System**) and tap Connect.',
			},
			{
				id: 'households',
				q: 'I have more than one Sonos system.',
				a: 'Cue remembers every system it has connected to, S1 and S2 alike. Switch between them under **Settings ▸ Sonos ▸ Households**.',
			},
		],
	},
	{
		title: 'CarPlay & Apple Watch',
		items: [
			{
				id: 'carplay',
				q: 'Does Cue work with CarPlay?',
				a: 'Yes. Connect your iPhone to your car and open Cue on the car’s screen.\n- **Recents** — what you played last\n- **Library** — Apple Music, Plex, Subsonic and your files, starting with your playlists\n- **Downloads** — what’s on your iPhone, ready with no signal\n- **Radio** — local and trending TuneIn stations, and Apple Music radio\n\nNow Playing has Up Next, shuffle and repeat. In the car, music always plays from your iPhone, never on Sonos.',
			},
			{
				id: 'apple-watch',
				q: 'How do I put music on my Apple Watch?',
				a: 'Cue on Apple Watch plays Plex and Subsonic songs downloaded to the watch, so you can leave your iPhone at home. Sign in to Plex or Subsonic in Cue on your iPhone first; the watch uses the same sign-ins.\n- **On your iPhone**, choose **Add to Apple Watch** from an album, playlist, artist or song’s menu.\n- **On your watch**, browse or search your library in Cue and add it there.\n\nThe watch downloads the songs from your server itself. To see or remove what’s on it, open **Settings ▸ Storage ▸ Apple Watch** on your iPhone. If Cue isn’t on your watch yet, open the Watch app on your iPhone and install it under **Available Apps**.\n\nApple Music doesn’t let other apps play its music on Apple Watch, so it stays on your iPhone.',
			},
			{
				id: 'watch-downloads',
				q: 'Downloads to my watch are slow.',
				a: 'While your watch is connected to your iPhone over Bluetooth, watchOS sends its downloads through the phone, which is slow.\n1. Open **Downloads ▸ Fast Download** in Cue on your watch.\n2. Turn off Bluetooth in your iPhone’s **Settings** app. Control Center leaves the watch connected, so it has to be Settings.\n3. Keep Cue open on your watch. It downloads over its own Wi-Fi, and tells you if it’s still going through your iPhone.\n\nIf you leave the app, the rest of the songs keep downloading in the background, more slowly.',
			},
		],
	},
	{
		title: 'Troubleshooting',
		items: [
			{
				id: 'applemusic',
				q: 'My Apple Music library is empty.',
				a: 'Cue needs the **Media & Apple Music** permission, which iOS sometimes resets after an update.\n1. Open **Settings ▸ Privacy & Security ▸ Media & Apple Music**.\n2. Turn Cue on — or off and on again if it already is.\n3. Quit Cue fully and open it again.',
			},
			{
				id: 'logs',
				q: 'How do I send a bug report?',
				a: `Email [hi@cue.dance](mailto:hi@cue.dance) with the Support link at the bottom of Cue’s Settings — it fills in your app version for you. A screen recording of the problem helps more than anything.`,
			},
		],
	},
];
