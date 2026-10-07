import { site } from '../config.js';
import { faq, intro, ready, steps } from '../content/testflight.js';
import { html, icon, inline } from '../lib/html.js';
import { page } from '../lib/layout.js';
import { releases } from './releases.js';

const joinButton = () =>
	html`<a class="btn btn-primary btn-large" href="${site.testflight}">${icon('download')}<span>Join the Beta on TestFlight</span></a>`;

export const testflightPage = () =>
	page({
		path: '/testflight',
		title: 'Beta',
		description: 'Join the Cue beta on TestFlight: new builds as they’re made, with every feature unlocked.',
		body: html`
			<section class="section container narrow text-center page-intro">
				<p class="eyebrow">${intro.eyebrow}</p>
				<h1 class="display small">${intro.title}</h1>
				<p class="lede">${intro.lede}</p>
				<div class="actions center">
					${joinButton()}
					<a class="btn btn-ghost btn-large" href="/releases/${releases[0].version}">What’s in ${releases[0].version} ${icon('arrow-right')}</a>
				</div>
				<ul class="fine devices" aria-label="Works on">${intro.devices.map((d) => html`<li>${icon(d.icon)}${d.name}</li>`)}</ul>
				<p class="fine">${intro.requirement}</p>
				<div class="qr">
					<img src="/testflight-qr.svg" alt="QR code for the Cue beta on TestFlight" width="104" height="104">
					<p>${intro.scan}</p>
				</div>
			</section>

			<section class="section container">
				<div class="section-head reveal"><h2>Three steps in.</h2></div>
				<ol class="steps">
					${steps.map(
						(step, i) => html`
							<li class="card reveal">
								<span class="step-number">${i + 1}</span>
								<span class="card-icon">${icon(step.icon)}</span>
								<h3>${step.title}</h3>
								<p>${inline(step.body)}</p>
							</li>`,
					)}
				</ol>
			</section>

			<section class="section container narrow">
				<div class="section-head reveal"><h2>Questions</h2></div>
				<div class="faq">
					${faq.map((item) => html`<details class="reveal"><summary>${item.q}</summary><p>${inline(item.a)}</p></details>`)}
				</div>
			</section>

			<section class="section container narrow">
				<div class="cta-panel reveal">
					<img src="/apple-touch-icon.png" alt="" width="88" height="88" loading="lazy">
					<h2>${ready.title}</h2>
					<p>${ready.body}</p>
					${joinButton()}
				</div>
			</section>`,
	});
