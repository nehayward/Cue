import { appStoreUrl, footerLinks, nav, site } from '../config.js';
import { html, icon, raw } from './html.js';

// Bumped by hand when styles.css changes in a way that must not mix with a
// cached copy. Static assets are otherwise cached for an hour (public/_headers).
const ASSET_VERSION = '3';

/** The main call to action: an App Store link once Cue is listed, a "coming soon" label until then. */
export const downloadButton = ({ size = 'large' } = {}) =>
	appStoreUrl
		? html`<a class="btn btn-primary btn-${size}" href="${appStoreUrl}" aria-label="Download Cue on the App Store">${icon('download')}<span>Download on the App Store</span></a>`
		: html`<span class="btn btn-soon btn-${size}">${icon('smartphone')}<span>Coming soon to the App Store</span></span>`;

// Shows each `.reveal` element for good the first time it scrolls into view.
const revealScript = `
	const io = new IntersectionObserver((entries) => {
		for (const e of entries) if (e.isIntersecting) { e.target.classList.add('in'); io.unobserve(e.target); }
	}, { rootMargin: '0px 0px -8% 0px' });
	document.querySelectorAll('.reveal').forEach((el) => io.observe(el));
`;

const header = (path) => html`
	<header class="header">
		<div class="container header-inner">
			<a class="brand" href="/" aria-label="${site.name} home">
				<img src="/favicon.png" alt="" width="28" height="28">
				<span>${site.name}</span>
			</a>
			<nav class="nav" aria-label="Main">
				${nav.map(({ href, label }) => html`<a href="${href}" ${path === href ? raw('aria-current="page"') : ''}>${label}</a>`)}
			</nav>
			${appStoreUrl && downloadButton({ size: 'small' })}
			<details class="menu">
				<summary aria-label="Menu">${icon('menu', { className: 'icon menu-open' })}${icon('x', { className: 'icon menu-close' })}</summary>
				<nav class="menu-panel" aria-label="Main">
					${nav.map(({ href, label }) => html`<a href="${href}">${label}</a>`)}
				</nav>
			</details>
		</div>
	</header>`;

const footer = () => html`
	<footer class="footer">
		<div class="container footer-inner">
			<a class="brand" href="/"><img src="/favicon.png" alt="" width="24" height="24"><span>${site.name}</span></a>
			<nav aria-label="Footer">${footerLinks.map(({ href, label }) => html`<a href="${href}">${label}</a>`)}</nav>
			<p>© ${new Date().getUTCFullYear()} ${site.author}. Cue is not affiliated with Sonos, Inc.</p>
		</div>
	</footer>`;

/**
 * Wraps a page body in the shared document: meta tags, header and footer.
 *
 * The iOS app opens /help and /releases/<version> in a web view and hides
 * `header.header`, `footer`, and the intro `main > section.text-center` with
 * injected CSS (HelpWebView.swift, WhatsNewWebView.swift). Keep those
 * selectors stable, or pass `?embed` from the app to drop the chrome here.
 */
export const page = ({ path, title, description = site.description, image, body, head = '', embed = false }) => {
	const fullTitle = title ? `${title} – ${site.name}` : `${site.name} — Your music, here or on Sonos`;
	const url = `${site.origin}${path}`;
	const ogImage = image ?? `${site.origin}/icon-512.png`;
	return `<!DOCTYPE html>${html`
<html lang="en">
<head>
	<meta charset="utf-8">
	<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
	<title>${fullTitle}</title>
	<meta name="description" content="${description}">
	<link rel="canonical" href="${url}">
	<meta name="theme-color" content="#07090a">
	<meta name="color-scheme" content="dark">
	${site.appStoreId && raw(`<meta name="apple-itunes-app" content="app-id=${site.appStoreId}">`)}
	<link rel="icon" type="image/png" href="/favicon.png">
	<link rel="apple-touch-icon" href="/apple-touch-icon.png">
	<script>document.documentElement.classList.add('js')</script>
	<link rel="stylesheet" href="/styles.css?v=${ASSET_VERSION}">
	<meta property="og:type" content="website">
	<meta property="og:site_name" content="${site.name}">
	<meta property="og:url" content="${url}">
	<meta property="og:title" content="${fullTitle}">
	<meta property="og:description" content="${description}">
	<meta property="og:image" content="${ogImage}">
	<meta name="twitter:card" content="${image ? 'summary_large_image' : 'summary'}">
	${raw(head)}
</head>
<body class="${embed ? 'embed' : ''}">
	${!embed && header(path)}
	<main>
		${raw(body)}
	</main>
	${!embed && footer()}
	<script>${raw(revealScript)}</script>
</body>
</html>`}`;
};
