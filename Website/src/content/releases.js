// Every release on the site, newest first. Add a new release at the top; its
// notes can be pasted from ReleaseNotes.md in the app repo.
//
// - `version`: the App Store version. It is the URL (/releases/<version>) and
//   what the app asks for (/api/releases/<version>.json); a version missing
//   here hides the app's What's New banner.
// - `date`: 'YYYY-MM-DD', or null until it ships.
// - `headline`: one sentence, ~100 characters. It is the page subtitle, the
//   social card text, and the in-app What's New banner.
// - `newFeatures`, `bugFixes`: one string per line. "Label: text" shows the
//   label in bold. **bold**, *italic* and [links](…) work.
// - `reels` (optional): up to three { slug, title, body }. Each plays
//   `${site.resources}/releases/<version>/<slug>.mp4` with `<slug>.jpg` as its
//   poster (upload them first).
// - `image` (optional): a 1200×630 social card URL.

export const releases = [
	{
		version: '2026.1',
		date: null,
		headline: 'Meet Cue: a music player for iPhone that plays Apple Music, Plex, Subsonic and radio — on your phone, or on Sonos.',
		newFeatures: [
			'Plays on your device: Apple Music, Plex, Subsonic servers like Navidrome, TuneIn radio, and your own files — no speaker needed',
			'Hands off to Sonos: Tap Play On to move the queue to any room or group, right where you left it',
			'Universal Search: Search several services at once and get one ranked list that forgives typos',
			'Offline Mode: Download from Plex and Subsonic and keep listening with no connection',
			'Streaming Quality: Have Plex or Subsonic convert to MP3 or Opus at a bitrate you choose',
			'Plays count on your server: Songs you play show up in Plex and Subsonic play counts, and Navidrome can pass them to Last.fm or ListenBrainz',
			'Live Transcription: Read what a radio station is saying, transcribed live on your device (iOS 26 and later)',
			'Playlists: Create playlists, add songs to several at once, reorder, and undo',
			'Sonos: Group rooms, set volumes and alarms, and switch between S1, S2 and multiple homes',
		],
		bugFixes: [],
	},
];
