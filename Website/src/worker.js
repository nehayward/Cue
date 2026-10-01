import { site } from './config.js';
import { helpPage } from './pages/help.js';
import { homePage } from './pages/home.js';
import { privacyPage, termsPage } from './pages/legal.js';
import { notFoundPage } from './pages/not-found.js';
import { pressPage } from './pages/press.js';
import { findRelease, releaseJson, releasePage, releases, releasesIndexPage } from './pages/releases.js';
import { selfHostedPage } from './pages/self-hosted.js';

// Files in public/ (styles, icons) are served by Cloudflare before this Worker
// runs; everything else lands here.

// Short so a deploy shows up within a minute.
const CACHE = 'public, max-age=60, s-maxage=300';

const SECURITY_HEADERS = {
	'x-content-type-options': 'nosniff',
	'referrer-policy': 'strict-origin-when-cross-origin',
	'permissions-policy': 'camera=(), microphone=(), geolocation=()',
};

const htmlResponse = (body, status = 200) =>
	new Response(body, {
		status,
		headers: { 'content-type': 'text/html; charset=utf-8', 'cache-control': CACHE, ...SECURITY_HEADERS },
	});

const jsonResponse = (data, status = 200) =>
	new Response(JSON.stringify(data), {
		status,
		headers: { 'content-type': 'application/json; charset=utf-8', 'cache-control': CACHE, 'access-control-allow-origin': '*', ...SECURITY_HEADERS },
	});

const textResponse = (body, type = 'text/plain') =>
	new Response(body, { headers: { 'content-type': `${type}; charset=utf-8`, 'cache-control': CACHE } });

// Old or guessable paths that point somewhere else.
const REDIRECTS = {
	'/latest': () => `/releases/${releases[0].version}`,
	'/whats-new': () => `/releases/${releases[0].version}`,
	'/support': () => '/help',
	'/faq': () => '/help',
	'/privacy-policy': () => '/privacy',
	'/plex': () => '/self-hosted',
	'/navidrome': () => '/self-hosted',
	'/subsonic': () => '/self-hosted',
};

// Exact paths → page. `query` is the request's URLSearchParams.
const PAGES = {
	'/': () => homePage(),
	'/help': (query) => helpPage({ embed: query.has('embed') }),
	'/self-hosted': () => selfHostedPage(),
	'/releases': () => releasesIndexPage(),
	'/press': () => pressPage(),
	'/privacy': () => privacyPage(),
	'/terms': () => termsPage(),
};

const sitemap = () => {
	const paths = [...Object.keys(PAGES), ...releases.map((r) => `/releases/${r.version}`)];
	return `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n${paths
		.map((p) => `\t<url><loc>${site.origin}${p === '/' ? '' : p}</loc></url>`)
		.join('\n')}\n</urlset>\n`;
};

export const route = async (request) => {
	const url = new URL(request.url);
	// One canonical form per page: /help/ → /help.
	const path = url.pathname.replace(/\/+$/, '') || '/';
	if (path !== url.pathname) return Response.redirect(`${url.origin}${path}${url.search}`, 301);

	if (REDIRECTS[path]) return Response.redirect(`${url.origin}${REDIRECTS[path]()}`, 301);

	if (request.method !== 'GET' && request.method !== 'HEAD') return new Response('Method Not Allowed', { status: 405, headers: { allow: 'GET, HEAD' } });

	if (PAGES[path]) return htmlResponse(PAGES[path](url.searchParams));

	const release = path.match(/^\/releases\/([\w.]+)$/);
	if (release) {
		const r = findRelease(release[1]);
		return r ? htmlResponse(releasePage(r, { embed: url.searchParams.has('embed') })) : htmlResponse(notFoundPage(path), 404);
	}

	// Release JSON for the in-app What's New banner (LatestReleaseFetcher.swift).
	if (path === '/api/latest.json') return jsonResponse(releaseJson(releases[0]));
	const releaseApi = path.match(/^\/api\/releases\/([\w.]+)\.json$/);
	if (releaseApi) {
		const r = findRelease(releaseApi[1]);
		return r ? jsonResponse(releaseJson(r)) : jsonResponse({ error: 'not_found', version: releaseApi[1] }, 404);
	}

	if (path === '/sitemap.xml') return textResponse(sitemap(), 'application/xml');
	if (path === '/robots.txt') return textResponse(`User-agent: *\nAllow: /\nSitemap: ${site.origin}/sitemap.xml\n`);

	return htmlResponse(notFoundPage(path), 404);
};

export default { fetch: route };
