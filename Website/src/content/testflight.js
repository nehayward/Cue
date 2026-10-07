// Copy for /testflight, the beta's landing page (testflight.cue.dance lands
// here). The Join button and QR code go to site.testflight in config.js.

import { site } from '../config.js';

export const intro = {
	eyebrow: 'Public beta',
	title: 'Try the next Cue first.',
	lede: 'Cue’s beta is open on TestFlight. Join for new builds as they’re made, with every feature unlocked, and help shape what ships.',
	requirement: 'Needs an iPhone with iOS 26 or later.',
	// Shown under the buttons, each with its device glyph from src/lib/icon-paths.js.
	devices: [
		{ icon: 'iphone', name: 'iPhone' },
		{ icon: 'apple-watch', name: 'Apple Watch' },
		{ icon: 'carplay', name: 'CarPlay' },
	],
	scan: 'On a computer? Scan this with your iPhone’s camera to open the beta in TestFlight.',
};

export const steps = [
	{
		icon: 'download',
		title: 'Get TestFlight',
		body: 'TestFlight is Apple’s free app for trying betas. [Install it from the App Store](https://apps.apple.com/app/testflight/id899247664).',
	},
	{
		icon: 'iphone',
		title: 'Join the beta',
		body: 'Tap **Join the Beta** on your iPhone. TestFlight opens with Cue, ready to install.',
	},
	{
		icon: 'mail',
		title: 'Tell us what you think',
		body: `Take a screenshot in Cue to send it with a note through TestFlight, or email [${site.email}](mailto:${site.email}). Every message is read.`,
	},
];

export const ready = {
	title: 'Ready to try it?',
	body: 'Free on TestFlight, for iPhone with iOS 26 or later.',
};

export const faq = [
	{ q: 'Does the beta cost anything?', a: 'No. Every feature is unlocked in TestFlight builds, and nothing you do in the beta is charged.' },
	{ q: 'Do I need Sonos?', a: 'No. Cue is a complete music player on its own, and Sonos is optional. [More in Help](/help#without-sonos).' },
	{ q: 'How do updates work?', a: 'TestFlight tells you when a new build is ready, and installs it for you if Automatic Updates is on. Each build stops working after 90 days, so keep up to date.' },
	{ q: 'How do I leave the beta?', a: 'Open Cue in TestFlight and tap **Stop Testing**, or delete the app.' },
];
