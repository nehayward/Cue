// Copy for /audiobooks, the page for people who keep books on Plex or
// Audiobookshelf. Every claim here should match what the shipping app does
// (CLAUDE.md ▸ Audiobooks, Book transcripts). Competitors aren't named: the
// comparison is with the usual setup, a book app beside a music app.

export const intro = {
	eyebrow: 'Audiobooks · Plex · Audiobookshelf',
	title: 'Built for books,\nnot just songs.',
	lede: 'Cue plays the audiobooks on your Plex or Audiobookshelf server with everything a book needs: chapters, speed, Smart Resume and a history of every place you’ve been. In the same app as your music, on your iPhone, in the car, on your wrist or on Sonos.',
	devices: [
		{ icon: 'iphone', name: 'iPhone' },
		{ icon: 'carplay', name: 'CarPlay' },
		{ icon: 'apple-watch', name: 'Apple Watch' },
		{ icon: 'speaker', name: 'Sonos' },
	],
};

// The hero's fanned phones, front one first. Covers are blurred on purpose
// (-dance.cue.blurArtwork): the books aren't ours to show.
export const screens = [
	{ file: 'shots/book-player.jpg', alt: 'Cue playing an audiobook, with the chapter over the title and 15 and 30 second skips' },
	{ file: 'shots/audiobooks.jpg', alt: 'Cue’s Audiobooks tab: Continue Listening, then downloaded books' },
	{ file: 'shots/book-page.jpg', alt: 'A book’s page in Cue, with its narrator, the chapter you’re in, Resume and From Start' },
];

// What a book app on its own can't do: the three reasons to listen in Cue.
export const reasons = {
	title: 'One app, not three.',
	lede: 'A book app, a music app and the Sonos app, folded into one player that keeps your place in all of it.',
	list: [
		{
			icon: 'arrow-left-right',
			title: 'Books and music, together',
			body: 'Start a chapter on the drive in, then tap Back to Music and your playlist picks up exactly where it stopped. Back to Book goes the other way.',
		},
		{
			icon: 'speaker',
			title: 'On any Sonos speaker',
			body: 'Play On sends the book to any room or group, chapters and all. Your place keeps syncing to your server while it plays there.',
		},
		{
			icon: 'apple-watch',
			title: 'Leave the phone at home',
			body: 'Take a book on a run with your Apple Watch. Your place is waiting on your iPhone when you’re back, through iCloud if the two never met.',
		},
	],
};

// Big alternating sections. `demo` draws one of the page's illustrations
// (pages/audiobooks.js) in place of a phone.
export const spotlights = [
	{
		eyebrow: 'Smart Resume',
		title: 'Pick up mid-thought, never mid-word.',
		body: 'Press play after a pause and Cue goes back just far enough to catch the thread: a second after a quick pause, up to 15 seconds after a day away. Then it listens for a pause in the speech and starts there — at the end of a sentence after a longer break.',
		points: ['Never goes back past the start of the chapter', 'No rewind when you moved the place yourself', 'On your iPhone, in the car and on Apple Watch'],
		demo: 'resume',
	},
	{
		eyebrow: 'Read Along · Cue Super',
		title: 'See every word as it’s read.',
		body: 'Open the transcript and the narration appears line by line, each word lighting up as it’s spoken. It’s written out on your iPhone, a few minutes ahead of you, from the book you’re streaming or the one you downloaded. Nothing is uploaded anywhere.',
		points: ['Tap a word to look it up in the dictionary', 'Hold a line to play from there, copy, share or translate', 'Your choice of typeface, size and spacing', 'Try it free for 30 seconds a day'],
		demo: 'read',
	},
	{
		eyebrow: 'History',
		title: 'Every place you’ve been, one tap away.',
		body: 'Fell asleep? Tapped the wrong chapter? Cue keeps a timeline of each book: where you started, paused and left off, every jump and scrub, and the moment another device took over. Tap any moment to go back to it.',
		points: ['Grouped by day, with how long you listened', 'Says whose place took over: your watch, Plex or Audiobookshelf', 'A swipe away from the chapters'],
		screen: { file: 'shots/book-history.jpg', alt: 'A book’s History in Cue: a timeline of plays and pauses, grouped by day' },
	},
	{
		eyebrow: 'Library',
		title: 'Both servers, one shelf.',
		body: 'Continue Listening gathers every book you’re partway through, from Plex and Audiobookshelf alike, newest first, each with its own Play button. Book pages show the narrator, the series and where you are; author pages add a photo, a biography and every book of theirs on your servers.',
		points: ['Series and narrators', 'Author pages, filled in from Audible’s catalog when your server has nothing', 'Whole books downloaded for flights, with Cue Super'],
		screen: { file: 'shots/audiobooks.jpg', alt: 'Cue’s Audiobooks tab: Continue Listening, then downloaded books' },
	},
];

// Cue against the usual setup, not against named apps: claims about other
// apps go stale, and every row here should stay true of the setup it names.
export const comparison = {
	title: 'Why not just a book app?',
	lede: 'Book apps are good at books. Cue is good at books and everything around them.',
	before: 'The usual way',
	after: 'In Cue',
	rows: [
		{ topic: 'Your music', before: 'A second app, with its own queue', after: 'The same player. Back to Music picks up your playlist where it was' },
		{ topic: 'Sonos', before: 'AirPlay from your phone, or the Sonos app', after: 'Play On sends the book to any room, with your place kept in sync' },
		{ topic: 'After a pause', before: 'Back a few seconds, wherever that lands', after: 'Back by how long you were away, landing between words' },
		{ topic: 'Reading along', before: 'Buy the ebook as well', after: 'Read Along, transcribed on your iPhone as you listen' },
		{ topic: 'A skip you didn’t mean', before: 'Scrub around until it sounds familiar', after: 'History has every place you’ve been, one tap back' },
	],
};

export const everywhere = {
	title: 'Wherever you listen.',
	lede: 'The same book and the same place, on every screen Cue runs on.',
	list: [
		{
			icon: 'carplay',
			name: 'CarPlay',
			body: 'An Audiobooks tab on the car’s screen: the books you’re partway through with their progress, then every server’s shelves.',
			points: ['The chapters still to come, the one playing filling up', 'Playback speed right in Now Playing', 'Smart Resume after every stop'],
		},
		{
			icon: 'apple-watch',
			name: 'Apple Watch',
			body: 'Download books to your watch with Cue Super and leave your iPhone behind. Chapters come down in the order you’ll hear them.',
			points: ['The chapter, and where you are in it, in Now Playing', 'Your speed, and 15 and 30 second skips', 'Your place synced back to your iPhone and server'],
		},
		{
			icon: 'speaker',
			name: 'Sonos',
			body: 'Play a book on any room or group, and bring it back to your iPhone with a tap when you head out.',
			points: ['Chapters and your place come along', 'Your place syncs to Plex or Audiobookshelf as it plays', 'The rest of the house can keep its music'],
		},
	],
};

export const details = [
	{ icon: 'gauge', title: 'Speed, per book', body: '0.75× to 3×, remembered for each book, with the narrator’s voice kept natural.' },
	{ icon: 'bookmark', title: 'Real chapters', body: 'From your files’ own marks, or Audible’s chapter list when a Plex book has none.' },
	{ icon: 'moon', title: 'End of Chapter', body: 'A sleep timer that stops at the end of the chapter, at whatever speed you’re listening.' },
	{ icon: 'rotate-ccw', title: '15 back, 30 forward', body: 'In the player, the mini player and on the Lock Screen, in place of previous and next.' },
	{ icon: 'refresh-cw', title: 'Your place, everywhere', body: 'Synced with Plex and Audiobookshelf both ways. Moves made offline catch up next time.' },
	{ icon: 'download', title: 'Whole-book downloads', body: 'Files kept just as your server has them, for planes and tunnels. With Cue Super.' },
	{ icon: 'user-round', title: 'Author pages', body: 'A photo, a biography and every book of theirs on both servers, oldest first.' },
	{ icon: 'library', title: 'Series & narrators', body: 'See who reads each book, and open a series to find what comes next.' },
	{ icon: 'circle-check', title: 'Kept tidy', body: 'Mark a book finished, or take it off Continue Listening until you play it again.' },
];

export const plans = {
	title: 'Free to listen. Super to keep.',
	lede: 'Every book on your server plays free. Cue Super adds downloads, your watch and the full Read Along.',
	free: {
		name: 'Free',
		price: '$0',
		points: ['Stream from Plex and Audiobookshelf', 'Smart Resume, chapters, speed and History', 'CarPlay and Sonos', 'Read Along for 30 seconds a day'],
	},
	super: {
		name: 'Cue Super',
		price: 'Free trial',
		points: ['Download whole books', 'Books on your Apple Watch', 'Read Along with every book', 'Everything else Super adds to music and Sonos'],
	},
};

export const setup = [
	{
		title: 'Plex',
		steps: [
			'Open **Settings ▸ Services ▸ Plex** and sign in.',
			'Under **Audiobooks**, switch on the libraries that hold your books. Albums with the genre Audiobook show up too.',
			'On your server, turn on **Store Track Progress** in the library’s advanced settings, so your place follows you between Plex apps.',
		],
	},
	{
		title: 'Audiobookshelf',
		steps: [
			'Open **Settings ▸ Services ▸ Audiobookshelf** and tap **Connect**.',
			'Enter your server’s address, username and password.',
			'Your books appear in the **Audiobooks** tab, with the ones you’re partway through first.',
		],
	},
];

export const faq = [
	{
		q: 'Which servers work?',
		a: 'Plex and Audiobookshelf, on their own or both at once. Plex has no audiobook library type, so Cue reads books from Music libraries you keep for books, and from albums tagged with the genre Audiobook.',
	},
	{
		q: 'Will my place match my other apps?',
		a: 'Yes. Cue reads your place from the server when you open a book and sends it back as you listen, so the Audiobookshelf web app or another Plex app picks up where Cue left off. When the two disagree, the newer place wins. For Plex, turn on **Store Track Progress** in the library’s settings.',
	},
	{
		q: 'Do books get mixed in with my music?',
		a: 'No. Starting a book sets your music aside rather than adding the book to your queue, and books stay out of your downloaded songs and Shuffle. **Back to Music** in the player’s menu brings the music back where it was.',
	},
	{
		q: 'What does Read Along need?',
		a: 'iOS 26 or later, and Cue Super after a free 30 seconds a day. The transcript is written on your iPhone by Apple’s on-device speech model, so nothing about the book is uploaded.',
	},
	{
		q: 'Can Cue play Audible or Apple Books?',
		a: 'No. Audible and Apple Books only let their own apps play their books. Cue plays the books on your own server, the files you own.',
	},
];
