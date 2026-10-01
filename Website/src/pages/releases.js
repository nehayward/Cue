import { site } from '../config.js';
import { releases } from '../content/releases.js';
import { html, icon, inline } from '../lib/html.js';
import { page } from '../lib/layout.js';

// "Label: rest" → the part before the colon, when it reads like a label.
const splitLabel = (line) => {
	const match = line.match(/^([^:.]{2,48}):\s+(.+)$/);
	return match ? { label: match[1], text: match[2] } : { label: null, text: line };
};

export { releases };

export const findRelease = (version) => releases.find((r) => r.version === version);

/** The JSON the app's What's New banner reads (LatestReleaseFetcher.swift). */
export const releaseJson = (r) => ({
	version: r.version,
	date: r.date,
	headline: r.headline,
	newFeatures: r.newFeatures,
	bugFixes: r.bugFixes,
});

const formatDate = (iso) =>
	iso && new Date(`${iso}T12:00:00Z`).toLocaleDateString('en-US', { month: 'long', day: 'numeric', year: 'numeric', timeZone: 'UTC' });

const noteList = (items) =>
	html`<ul class="notes">${items.map((line) => {
		const { label, text } = splitLabel(line);
		return html`<li>${label && html`<strong>${label}</strong> `}${inline(text)}</li>`;
	})}</ul>`;

export const releasePage = (r, { embed } = {}) => {
	const isLatest = r === releases[0];
	const media = (slug, ext) => `${site.resources}/releases/${r.version}/${slug}.${ext}`;
	return page({
		path: `/releases/${r.version}`,
		title: `What’s New in ${r.version}`,
		description: r.headline,
		image: r.image,
		embed,
		body: html`
			${!isLatest && html`<p class="old-release container narrow">You’re reading an older release. <a href="/releases/${releases[0].version}">See what’s new in ${releases[0].version} ${icon('arrow-right')}</a></p>`}
			<section class="latest-hero container narrow">
				<p class="eyebrow">Cue ${r.version}${r.date && ` · ${formatDate(r.date)}`}</p>
				<h1 class="display small">What’s new</h1>
				<p class="lede">${r.headline}</p>
			</section>
			${r.reels?.length > 0 && html`
				<section class="container reels">
					${r.reels.map(
						(reel) => html`
							<figure class="reel">
								<video src="${media(reel.slug, 'mp4')}" poster="${media(reel.slug, 'jpg')}" autoplay muted loop playsinline preload="metadata"></video>
								<figcaption><strong>${reel.title}</strong><span>${reel.body}</span></figcaption>
							</figure>`,
					)}
				</section>`}
			<section class="container narrow release-notes">
				${r.newFeatures.length > 0 && html`<h2>${icon('sparkles')} New features</h2>${noteList(r.newFeatures)}`}
				${r.bugFixes.length > 0 && html`<h2>${icon('check')} Fixes and improvements</h2>${noteList(r.bugFixes)}`}
				${!embed && html`<p class="more-link"><a href="/releases">Every release ${icon('arrow-right')}</a></p>`}
			</section>`,
	});
};

export const releasesIndexPage = () =>
	page({
		path: '/releases',
		title: 'Release Notes',
		description: 'Every Cue release, newest first.',
		body: html`
			<section class="section container narrow text-center page-intro">
				<p class="eyebrow">Release notes</p>
				<h1 class="display small">Every release.</h1>
				<p class="lede">What changed in Cue, newest first.</p>
			</section>
			<section class="container narrow">
				<ol class="release-list">
					${releases.map(
						(r) => html`
							<li><a href="/releases/${r.version}">
								<span class="release-version">${r.version}</span>
								<span class="release-headline">${r.headline}</span>
								${icon('arrow-right')}
							</a></li>`,
					)}
				</ol>
			</section>`,
	});
