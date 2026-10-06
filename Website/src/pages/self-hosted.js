import { faq, highlights, intro, servers, setup } from '../content/self-hosted.js';
import { html, icon, inline } from '../lib/html.js';
import { downloadButton, page } from '../lib/layout.js';

export const selfHostedPage = () =>
	page({
		path: '/self-hosted',
		title: 'Plex, Navidrome & Subsonic',
		description: 'Cue is a music player for your own server: Plex, Navidrome and any Subsonic server, with offline downloads, streaming quality, play reporting and Sonos.',
		body: html`
			<section class="section container narrow text-center page-intro">
				<p class="eyebrow">${intro.eyebrow}</p>
				<h1 class="display small">${intro.title}</h1>
				<p class="lede">${intro.lede}</p>
				<div class="actions center">${downloadButton()}</div>
			</section>

			<section class="container">
				<div class="servers">
					${servers.map(
						(s) => html`
							<article class="server reveal">
								<span class="card-icon">${icon('server')}</span>
								<h2>${s.name}</h2>
								<p>${s.body}</p>
								<ul>${s.points.map((p) => html`<li>${icon('check')}${p}</li>`)}</ul>
							</article>`,
					)}
				</div>
			</section>

			<section class="section container">
				<div class="section-head reveal">
					<h2>Built for big libraries.</h2>
					<p>The things a self-hoster checks in the first ten minutes.</p>
				</div>
				<ul class="feature-grid two">
					${highlights.map(
						(h) => html`
							<li class="feature reveal">
								<span class="card-icon">${icon(h.icon)}</span>
								<div><h3>${h.title}</h3><p>${h.body}</p></div>
							</li>`,
					)}
				</ul>
			</section>

			<section class="section container narrow">
				<div class="section-head reveal"><h2>Set up in a minute.</h2></div>
				<div class="setup">
					${setup.map(
						(s) => html`
							<div class="card reveal">
								<h3>${s.title}</h3>
								<ol>${s.steps.map((step) => html`<li>${inline(step)}</li>`)}</ol>
							</div>`,
					)}
				</div>
			</section>

			<section class="section container narrow">
				<div class="section-head reveal"><h2>Questions</h2></div>
				<div class="faq">
					${faq.map((item) => html`<details class="reveal"><summary>${item.q}</summary><p>${inline(item.a)}</p></details>`)}
				</div>
				<p class="more-link"><a href="/help">More in Help ${icon('arrow-right')}</a></p>
			</section>`,
	});
