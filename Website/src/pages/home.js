import { appStoreUrl, site } from '../config.js';
import { beyondPhone, faq, features, handoff, hero, screens, services, spotlights } from '../content/home.js';
import { brandMarks } from '../lib/brand-marks.js';
import { html, icon, inline, raw } from '../lib/html.js';
import { downloadButton, iphone, page } from '../lib/layout.js';
import { releases } from './releases.js';

const structuredData = {
	'@context': 'https://schema.org',
	'@type': 'SoftwareApplication',
	name: site.name,
	description: site.description,
	operatingSystem: 'iOS, watchOS',
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
		<div class="hero-visual">
			<div class="hero-phones" style="--glow: url('/${screens[0].file}')">
				${screens.map((shot, i) => iphone(shot, { priority: i === 0 }))}
			</div>
		</div>
	</section>

	<section class="section container" id="handoff">
		<div class="section-head reveal">
			<h2>${handoff.title}</h2>
			<p>${handoff.lede}</p>
		</div>
		<figure class="handoff reveal" aria-hidden="true">
			<div class="handoff-visual">
				<svg class="handoff-lines" viewBox="0 0 100 62">
					${[19, 31, 43].map(
						(y, i) => html`<g class="link link-${i + 1}">
							${['base', 'out', 'back'].map((kind) => raw(`<path class="${kind}" d="M30 31 C 44 31, 44 ${y}, 58 ${y}" />`))}
						</g>`,
					)}
				</svg>
				<div class="handoff-phone">${iphone(handoff.screen)}</div>
				${handoff.rooms.map((room, i) => html`<span class="room room-${i + 1}">${icon('volume-2')}${room}</span>`)}
			</div>
			<figcaption class="handoff-caption">
				<span class="c1">Playing on ${handoff.device}</span>
				<span class="c2">Playing in ${handoff.rooms[0]}</span>
				<span class="c3">${handoff.rooms[0]} + ${handoff.rooms[1]}</span>
				<span class="c4">Everywhere</span>
				<span class="c5">Back on ${handoff.device}</span>
			</figcaption>
		</figure>
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

	${spotlights.map(
		(s, i) => html`
			<section class="section container spotlight ${i % 2 ? 'flip' : ''}">
				<div class="spotlight-copy reveal">
					<p class="eyebrow">${s.eyebrow}</p>
					<h2>${s.title}</h2>
					<p>${s.body}</p>
					<ul>${s.points.map((p) => html`<li>${icon('check')}${p}</li>`)}</ul>
				</div>
				<div class="spotlight-visual reveal" style="--glow: url('/${s.screen.file}')">${iphone(s.screen)}</div>
			</section>`,
	)}

	<section class="section container" id="carplay-watch">
		<div class="section-head reveal">
			<h2>${beyondPhone.title}</h2>
			<p>${beyondPhone.lede}</p>
		</div>
		<div class="platforms">
			${beyondPhone.list.map(
				(p) => html`
					<article class="platform reveal">
						<span class="card-icon">${icon(p.icon)}</span>
						<h3>${p.name}</h3>
						<p>${p.body}</p>
						<ul>${p.points.map((point) => html`<li>${icon('check')}${point}</li>`)}</ul>
					</article>`,
			)}
		</div>
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
			${services.list.map(
				(s) => html`
					<li class="reveal" data-mark="${s.mark ?? ''}" style="--brand: ${s.mark ? brandMarks[s.mark].color : s.color}">
						<span class="service-mark">${s.mark
							? raw(`<svg viewBox="0 0 24 24" role="img" aria-label="${s.name}"><path fill="currentColor" d="${brandMarks[s.mark].path}"/></svg>`)
							: icon(s.icon)}</span>
						<strong>${s.name}</strong><span>${s.detail}</span>
					</li>`,
			)}
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
			<img src="/apple-touch-icon.png" alt="" width="88" height="88" loading="lazy">
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
