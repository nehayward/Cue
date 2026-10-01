import { appStoreUrl, site } from '../config.js';
import { faq, features, handoff, hero, services } from '../content/home.js';
import { html, icon, inline, raw } from '../lib/html.js';
import { downloadButton, page } from '../lib/layout.js';
import { releases } from './releases.js';

// A drawn player rather than a screenshot, so the hero never goes stale when
// the app's UI changes. The route pill flips between the device and a speaker
// group to show the hand-off (styles.css, `.route`).
const playerMock = html`
	<div class="player" aria-hidden="true">
		<div class="player-art"><span></span></div>
		<div class="player-meta">
			<strong>Golden Hour Drive</strong>
			<span>The Late Signals — Coastline</span>
		</div>
		<div class="player-progress"><span></span></div>
		<div class="player-controls">
			${icon('shuffle')}
			${icon('skip-back')}
			<span class="player-play">${icon('pause')}</span>
			${icon('skip-forward')}
			${icon('list-music')}
		</div>
		<div class="route">
			<span class="route-option">${icon('smartphone')} This iPhone</span>
			<span class="route-option">${icon('speaker')} Living Room + 2</span>
		</div>
	</div>`;

const structuredData = {
	'@context': 'https://schema.org',
	'@type': 'SoftwareApplication',
	name: site.name,
	description: site.description,
	operatingSystem: 'iOS',
	applicationCategory: 'MultimediaApplication',
	url: site.origin,
	image: `${site.origin}/icon-512.png`,
	author: { '@type': 'Person', name: site.author },
	...(appStoreUrl && { downloadUrl: appStoreUrl }),
	offers: { '@type': 'Offer', price: '0', priceCurrency: 'USD' },
};

const body = html`
	<section class="hero container">
		<div class="hero-copy">
			<p class="eyebrow">${hero.eyebrow}</p>
			<h1 class="display">${hero.title.split('\n').map((line, i) => html`${i > 0 && raw('<br>')}${line}`)}</h1>
			<p class="lede">${hero.lede}</p>
			<div class="actions">
				${downloadButton()}
				<a class="btn btn-ghost btn-large" href="#features">See what it does ${icon('arrow-right')}</a>
			</div>
			<p class="fine">${hero.platforms}</p>
		</div>
		<div class="hero-visual">${playerMock}</div>
	</section>

	<section class="section container" id="handoff">
		<div class="section-head reveal">
			<h2>${handoff.title}</h2>
			<p>${handoff.lede}</p>
		</div>
		<ol class="steps">
			${handoff.steps.map(
				(step, i) => html`
					<li class="card reveal">
						<span class="step-number">${i + 1}</span>
						<span class="card-icon">${icon(step.icon)}</span>
						<h3>${step.title}</h3>
						<p>${step.body}</p>
					</li>`,
			)}
		</ol>
	</section>

	<section class="section container" id="features">
		<div class="section-head reveal">
			<h2>Everything a player should do.</h2>
			<p>And the things you only notice once you have them.</p>
		</div>
		<ul class="feature-grid">
			${features.map(
				(f) => html`
					<li class="feature reveal">
						<span class="card-icon">${icon(f.icon)}</span>
						<div><h3>${f.title}</h3><p>${f.body}</p></div>
					</li>`,
			)}
		</ul>
	</section>

	<section class="section container" id="services">
		<div class="section-head reveal">
			<h2>${services.title}</h2>
			<p>${services.lede}</p>
		</div>
		<ul class="services">
			${services.list.map((s) => html`<li class="reveal"><strong>${s.name}</strong><span>${s.detail}</span></li>`)}
		</ul>
		<p class="more-link"><a href="/self-hosted">Running Plex or Navidrome? See what Cue does for your server ${icon('arrow-right')}</a></p>
	</section>


	<section class="section container narrow" id="faq">
		<div class="section-head reveal"><h2>Questions</h2></div>
		<div class="faq">
			${faq.map((item) => html`<details class="reveal"><summary>${item.q}</summary><p>${inline(item.a)}</p></details>`)}
		</div>
		<p class="more-link"><a href="/help">More in Help ${icon('arrow-right')}</a></p>
	</section>

	<section class="section container narrow" id="get">
		<div class="cta-panel reveal">
			<img src="/icon-512.png" alt="" width="88" height="88" loading="lazy">
			<h2>${appStoreUrl ? 'Ready when you are.' : 'Coming soon to iPhone.'}</h2>
			<p>${appStoreUrl ? 'Free to download, with every service ready to play.' : 'Cue is almost here. Until then, see what’s in the first release.'}</p>
			${appStoreUrl ? downloadButton() : html`<a class="btn btn-ghost" href="/releases/${releases[0].version}">What’s in ${releases[0].version} ${icon('arrow-right')}</a>`}
		</div>
	</section>`;

export const homePage = () =>
	page({
		path: '/',
		body,
		head: html`<script type="application/ld+json">${raw(JSON.stringify(structuredData))}</script>`,
	});
