import { site } from '../config.js';
import { html } from '../lib/html.js';
import { page } from '../lib/layout.js';
import { blocks } from '../lib/markdown.js';

// Privacy policy and terms. Each section is a heading and a Markdown body.
// Update `updated` whenever the wording changes.

const privacy = {
	updated: '2026-10-01',
	summary: 'Cue doesn’t sell or share your data, has no accounts, and keeps your music logins on your device.',
	sections: [
		{
			title: 'What stays on your device',
			body: 'Your music service logins (Plex tokens, Subsonic passwords in the keychain), your library, downloads, play history, queue and settings are stored on your device. Some settings sync between your devices through your own iCloud account.',
		},
		{
			title: 'Music services',
			body: 'Cue talks directly to the services you connect — Apple Music, Plex, your Subsonic server, TuneIn — and to your Sonos speakers on your local network. Those requests go from your device to that service; they don’t pass through us. Songs you play may be reported to your own Plex or Subsonic server so its play counts stay accurate.',
		},
		{
			title: 'Usage analytics',
			body: 'Cue sends anonymous usage events (for example, which screens are opened, which music service is selected, and whether onboarding was finished) to Mixpanel, tied to a random identifier rather than your name or email. They never include the songs you play or what you search for.',
		},
		{
			title: 'Purchases',
			body: 'Purchases are handled by Apple. Cue uses RevenueCat to check which purchases are active on your account, using the same random identifier. We never see your payment details.',
		},
		{
			title: 'Support email',
			body: 'If you email us, we use your message, address and any details you include (such as your app version) only to answer you.',
		},
		{
			title: 'This website',
			body: 'cue.dance sets no cookies and runs no trackers. It is served by Cloudflare, which keeps standard request logs.',
		},
		{
			title: 'Changes',
			body: `If this policy changes, the new version will appear here with a new date. Questions: [${site.email}](mailto:${site.email}).`,
		},
	],
};

const terms = {
	updated: '2026-10-01',
	summary: 'Use Cue for your own listening. Apple handles billing and refunds for anything you buy in the app.',
	sections: [
		{
			title: 'Using Cue',
			body: 'Cue is licensed to you for personal use under Apple’s [Standard End User License Agreement](https://www.apple.com/legal/internet-services/itunes/dev/stdeula/), together with these terms. You need your own access to the music services you connect, and you agree to follow their terms.',
		},
		{
			title: 'Purchases',
			body: 'In-app subscriptions renew automatically until you cancel them in your App Store account settings. A free trial, if offered, converts to a paid subscription when it ends unless you cancel before then. Billing and refunds are handled by Apple.',
		},
		{
			title: 'Not affiliated with Sonos',
			body: 'Cue is an independent app. It is not made, endorsed or supported by Sonos, Inc., Apple, Plex or any music service. Sonos is a trademark of Sonos, Inc.',
		},
		{
			title: 'No warranty',
			body: 'Cue is provided “as is”. We work hard to keep it reliable, but can’t promise it will be free of bugs or that every service or speaker will keep working with it. To the extent the law allows, our liability is limited to what you paid for Cue.',
		},
		{
			title: 'Changes',
			body: `We may update these terms; the new version will appear here with a new date. Questions: [${site.email}](mailto:${site.email}).`,
		},
	],
};

const legalPage = (path, title, doc) =>
	page({
		path,
		title,
		description: doc.summary,
		body: html`
			<section class="section container narrow text-center page-intro">
				<p class="eyebrow">Legal</p>
				<h1 class="display small">${title}</h1>
				<p class="lede">${doc.summary}</p>
			</section>
			<article class="container narrow prose">
				${doc.sections.map((s) => html`<h2>${s.title}</h2>${blocks(s.body)}`)}
				<p class="fine">Last updated ${doc.updated}.</p>
			</article>`,
	});

export const privacyPage = () => legalPage('/privacy', 'Privacy Policy', privacy);
export const termsPage = () => legalPage('/terms', 'Terms of Use', terms);
