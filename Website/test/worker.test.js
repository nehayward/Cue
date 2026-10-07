// Runs the Worker's router in Node (`npm test`). Static files in public/ are
// served by Cloudflare before the Worker, so they aren't covered here.

import assert from 'node:assert/strict';
import { test } from 'node:test';
import { html, raw } from '../src/lib/html.js';
import { releases } from '../src/pages/releases.js';
import { route } from '../src/worker.js';

const get = (path, init) => route(new Request(`https://cue.dance${path}`, init));

test('every page renders with the shared header and a title', async () => {
	for (const path of ['/', '/help', '/releases', '/privacy', '/terms', '/self-hosted', '/press', `/releases/${releases[0].version}`]) {
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

test('testflight.cue.dance goes to the TestFlight beta, whatever the path', async () => {
	for (const path of ['/', '/join']) {
		const response = await route(new Request(`https://testflight.cue.dance${path}`));
		assert.equal(response.status, 302, path);
		assert.match(response.headers.get('location'), /^https:\/\/testflight\.apple\.com\/join\/\w+$/, path);
	}
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
