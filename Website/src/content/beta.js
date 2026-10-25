// Copy for /beta, the way into the public beta on TestFlight. Every claim
// here should match what the beta builds do.

export const intro = {
	eyebrow: 'Public beta',
	title: 'Play it before it’s out.',
	lede: 'Cue is in public beta on TestFlight, Apple’s app for trying apps before they’re released. It’s free to join, every feature is unlocked, and each new build comes to you as soon as it’s ready.',
};

export const steps = [
	{ icon: 'smartphone', title: 'Open the invite', body: 'On your iPhone, tap Join on TestFlight, or go to testflight.cue.dance.' },
	{ icon: 'download', title: 'Get TestFlight', body: 'If you don’t have Apple’s TestFlight app yet, install it from the App Store, then open the invite again and tap Accept.' },
	{ icon: 'play', title: 'Install Cue', body: 'Tap Install, and you’re in. TestFlight brings you each new build as it comes out.' },
];

export const highlights = [
	{ icon: 'captions', title: 'Read Along', body: 'New: a book’s words light up as they’re said, transcribed on your iPhone with nothing sent anywhere.' },
	{ icon: 'book-open', title: 'Audiobooks', body: 'Plex and Audiobookshelf books with chapters, speed, Smart Resume and a history of where you’ve been.' },
	{ icon: 'list-music', title: 'Your whole library', body: 'Apple Music, Plex, Navidrome, radio and your own files in one queue, with one search.' },
	{ icon: 'speaker', title: 'Sonos', body: 'Send what’s playing to any Sonos room, and bring it back to your iPhone.' },
	{ icon: 'apple-watch', title: 'Apple Watch', body: 'Put songs and books on your watch and leave your iPhone at home.' },
	{ icon: 'carplay', title: 'CarPlay', body: 'Your library, books and radio on the car’s screen.' },
];

export const requirements = [
	{ label: 'iPhone', value: 'iOS 26 or later' },
	{ label: 'Apple Watch', value: 'watchOS 10 or later. The watch app comes with the iPhone app.' },
	{ label: 'Music', value: 'Apple Music, Plex, Navidrome or another Subsonic server, radio, or files of your own' },
	{ label: 'Audiobooks', value: 'Plex or Audiobookshelf' },
	{ label: 'Sonos', value: 'Optional. Cue plays on your iPhone with no speakers at all.' },
	{ label: 'Price', value: 'Free. Beta builds include Cue Super.' },
];

export const feedback = [
	'Take a screenshot in Cue, tap its thumbnail, and choose **Share Beta Feedback**.',
	'Or open **TestFlight**, tap Cue, and tap **Send Beta Feedback**.',
	'If Cue crashes, TestFlight asks whether to send us the report. Please say yes.',
	'Anything else, email [hi@cue.dance](mailto:hi@cue.dance).',
];

export const faq = [
	{ q: 'Does the beta cost anything?', a: 'No. It’s free, and it includes Cue Super, so every feature is unlocked while you test.' },
	{ q: 'What changes in each build?', a: 'TestFlight shows notes with every build, and each version’s release notes are on [What’s New](/releases).' },
	{ q: 'What happens when Cue reaches the App Store?', a: 'Install it from the App Store and it replaces the beta, keeping your sign-ins, downloads and settings.' },
	{ q: 'How long does a build last?', a: 'Each one works for 90 days, and new ones come far more often than that.' },
	{ q: 'How do I leave the beta?', a: 'Open TestFlight, tap Cue and tap **Stop Testing**, or just delete Cue.' },
];
