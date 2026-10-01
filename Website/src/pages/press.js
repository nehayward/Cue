import { site } from '../config.js';
import { about, downloads, facts, highlights, screenshots } from '../content/press.js';
import { html, icon } from '../lib/html.js';
import { page } from '../lib/layout.js';

export const pressPage = () =>
	page({
		path: '/press',
		title: 'Press Kit',
		description: about.short,
		body: html`
			<section class="section container narrow text-center page-intro">
				<p class="eyebrow">Press kit</p>
				<h1 class="display small">${about.tagline}</h1>
				<p class="lede">${about.short}</p>
			</section>

			<section class="container narrow press">
				<h2>About Cue</h2>
				${about.long.map((p) => html`<p>${p}</p>`)}

				<h2>At a glance</h2>
				<dl class="facts">
					${facts.map((f) => html`<div><dt>${f.label}</dt><dd>${f.value}</dd></div>`)}
				</dl>

				<h2>Highlights</h2>
				<ul class="notes">${highlights.map((h) => html`<li>${h}</li>`)}</ul>

				<h2>Assets</h2>
				${screenshots.length > 0 && html`
					<div class="shots">
						${screenshots.map((s) => html`<a href="/${s.file}"><img src="/${s.file}" alt="${s.alt}" loading="lazy"></a>`)}
					</div>`}
				<ul class="downloads">
					${downloads.map(
						(d) => html`
							<li><a href="/${d.file}" download>
								<img src="/${d.file}" alt="" width="56" height="56" loading="lazy">
								<span><strong>${d.label}</strong>${d.detail}</span>
								${icon('download')}
							</a></li>`,
					)}
				</ul>
				${screenshots.length === 0 && html`<p class="fine">Screenshots are on the way. Need them sooner? Just ask.</p>`}

				<div class="cta-panel compact">
					<h2>Writing about Cue?</h2>
					<p>Email <a href="mailto:${site.email}">${site.email}</a> for a review build, screenshots or questions. Cue is independent and not affiliated with Sonos, Inc.</p>
				</div>
			</section>`,
	});
