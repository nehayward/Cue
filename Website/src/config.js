// Every fact about Cue that more than one page needs lives here. Change it
// once and the header, footer, meta tags and calls to action follow.

export const site = {
	name: 'Cue',
	origin: 'https://cue.dance',
	description:
		'A music player for iPhone that plays Apple Music, Plex, Subsonic, radio and your own files — on your device, or on any Sonos speaker.',
	email: 'hi@cue.dance',
	author: 'Nick Hayward',

	// Media too large for the Worker (videos, hero art) is served from R2.
	resources: 'https://resource.cue.dance',

	// Set once Cue is live on the App Store. While it is null, every
	// call to action reads "Coming soon to the App Store" instead of linking.
	appStoreId: null,

	// The public beta, joined from /testflight (testflight.cue.dance lands
	// there). After changing it, run `make qr` to redraw the page's QR code.
	testflight: 'https://testflight.apple.com/join/6B7QHpsd',
};

export const appStoreUrl = site.appStoreId ? `https://apps.apple.com/app/id${site.appStoreId}` : null;

// Header and footer links, in order.
export const nav = [
	{ href: '/#features', label: 'Features' },
	{ href: '/self-hosted', label: 'Plex & Navidrome' },
	{ href: '/releases', label: "What's New" },
	{ href: '/help', label: 'Help' },
	{ href: '/testflight', label: 'Beta' },
];

export const footerLinks = [
	{ href: '/help', label: 'Help' },
	{ href: '/releases', label: 'Release Notes' },
	{ href: '/self-hosted', label: 'Plex & Navidrome' },
	{ href: '/testflight', label: 'Beta' },
	{ href: '/press', label: 'Press' },
	{ href: '/privacy', label: 'Privacy' },
	{ href: '/terms', label: 'Terms' },
	{ href: `mailto:${site.email}`, label: 'Contact' },
];
