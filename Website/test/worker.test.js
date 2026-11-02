// Runs the Worker's router in Node (`npm test`). Static files in public/ are
// served by Cloudflare before the Worker, so they aren't covered here.

import assert from 'node:assert/strict';
import { test } from 'node:test';
import { html, raw } from '../src/lib/html.js';
import { releases } from '../src/pages/releases.js';
import { film, route } from '../src/worker.js';

const get = (path, init) => route(new Request(`https://cue.dance${path}`, init));

test('every page renders with the shared header and a title', async () => {
	for (const path of ['/', '/help', '/releases', '/privacy', '/terms', '/self-hosted', '/audiobooks', '/press', '/beta', `/releases/${releases[0].version}`]) {
		const response = await get(path);
		assert.equal(response.status, 200, path);
		const body = await response.text();
		assert.match(body, /^<!DOCTYPE html>/, path);
		assert.match(body, /<header class="header">/, path);
		assert.match(body, /<title>[^<]+<\/title>/, path);
	}
});

test('the app’s web views can still hide the chrome they hide today', async () => {
	// HelpWebView.swift hides `main > section.text-center`.
	const help = await (await get('/help')).text();
	assert.match(help, /<main>\s*<section class="[^"]*text-center/);
	// WhatsNewWebView.swift trims `.latest-hero`.
	const release = await (await get(`/releases/${releases[0].version}`)).text();
	assert.match(release, /class="latest-hero/);
});

test('?embed drops the header and footer', async () => {
	const body = await (await get('/help?embed')).text();
	assert.doesNotMatch(body, /<header/);
	assert.doesNotMatch(body, /<footer/);
});

test('release JSON matches what LatestReleaseFetcher decodes', async () => {
	const latest = await (await get('/api/latest.json')).json();
	assert.equal(latest.version, releases[0].version);
	assert.equal(typeof latest.headline, 'string');

	const response = await get(`/api/releases/${releases.at(-1).version}.json`);
	assert.equal(response.status, 200);
	assert.equal((await response.json()).version, releases.at(-1).version);

	assert.equal((await get('/api/releases/1999.1.json')).status, 404);
});

test('redirects: trailing slash, then known aliases', async () => {
	const slash = await get('/help/');
	assert.equal(slash.status, 301);
	assert.equal(slash.headers.get('location'), 'https://cue.dance/help');

	const latest = await get('/latest');
	assert.equal(latest.headers.get('location'), `https://cue.dance/releases/${releases[0].version}`);
});

test('testflight.cue.dance sends every path to the beta invite', async () => {
	for (const path of ['/', '/help', '/anything/else?x=1']) {
		const response = await route(new Request(`https://testflight.cue.dance${path}`));
		assert.equal(response.status, 302, path);
		assert.equal(response.headers.get('location'), 'https://testflight.apple.com/join/6B7QHpsd', path);
	}
	assert.equal((await get('/')).status, 200);
});

test('until the App Store, the calls to action say coming soon, and only the unlisted /beta mentions the beta', async () => {
	const home = await (await get('/')).text();
	assert.match(home, /Coming soon to the App Store/);

	for (const path of ['/', '/help', '/releases', '/privacy', '/terms', '/self-hosted', '/audiobooks', '/press', `/releases/${releases[0].version}`]) {
		const body = await (await get(path)).text();
		assert.doesNotMatch(body, /testflight|\bbeta\b|href="\/beta"/i, path);
	}

	const beta = await (await get('/beta')).text();
	assert.ok(beta.includes('href="https://testflight.apple.com/join/6B7QHpsd"'));
	assert.match(beta, /<meta name="robots" content="noindex/);

	const sitemap = await (await get('/sitemap.xml')).text();
	assert.doesNotMatch(sitemap, /\/beta/);
	assert.doesNotMatch(await (await get('/robots.txt')).text(), /beta/);

	const alias = await get('/testflight');
	assert.equal(alias.status, 301);
	assert.equal(alias.headers.get('location'), 'https://cue.dance/beta');
});

test('unknown paths and versions are 404 pages', async () => {
	assert.equal((await get('/nope')).status, 404);
	assert.equal((await get('/releases/1999.1')).status, 404);
});

test('sitemap lists every release', async () => {
	const body = await (await get('/sitemap.xml')).text();
	for (const r of releases) assert.ok(body.includes(`/releases/${r.version}</loc>`), r.version);
});

test('html escapes values and keeps nested html', () => {
	const inner = html`<b>${'<i>'}</b>`;
	assert.equal(String(html`<p>${inner}${raw('&amp;')}${null}${false}${['a', '<']}</p>`), '<p><b>&lt;i&gt;</b>&amp;a&lt;</p>');
});

test('every release has what the pages need', () => {
	for (const r of releases) {
		assert.match(r.version, /^\d+\.\d+$/);
		assert.ok(r.headline, r.version);
		assert.ok(Array.isArray(r.newFeatures) && Array.isArray(r.bugFixes), r.version);
	}
});

test('films answer byte ranges, as Safari needs', async () => {
	const bytes = new Uint8Array(1000).map((_, i) => i % 256);
	const assets = { fetch: async () => new Response(bytes, { headers: { 'content-type': 'video/mp4' } }) };
	const ask = (range) => film(new Request('https://cue.dance/video/a.mp4', range ? { headers: { range } } : {}), assets);

	const whole = await ask();
	assert.equal(whole.status, 200);
	assert.equal(whole.headers.get('accept-ranges'), 'bytes');

	const first = await ask('bytes=0-1');
	assert.equal(first.status, 206);
	assert.equal(first.headers.get('content-range'), 'bytes 0-1/1000');
	assert.deepEqual([...new Uint8Array(await first.arrayBuffer())], [0, 1]);

	const rest = await ask('bytes=998-');
	assert.equal(rest.headers.get('content-range'), 'bytes 998-999/1000');
	const tail = await ask('bytes=-10');
	assert.equal(tail.headers.get('content-range'), 'bytes 990-999/1000');
	assert.equal((await ask('bytes=2000-')).status, 416);
});
