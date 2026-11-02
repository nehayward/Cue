import { site } from '../config.js';
import { faq, feedback, highlights, intro, requirements, steps } from '../content/beta.js';
import { html, icon, inline } from '../lib/html.js';
import { page, testFlightButton } from '../lib/layout.js';

export const betaPage = () =>
	page({
		path: '/beta',
		title: 'Public Beta',
		description: 'Try Cue before it reaches the App Store: join the free public beta on TestFlight, with every feature unlocked.',
		// Unlisted: only people given the link should find it.
		head: html`<meta name="robots" content="noindex, nofollow">`,
		body: html`
			<section class="section container narrow text-center page-intro">
				<p class="eyebrow">${intro.eyebrow}</p>
				<h1 class="display small">${intro.title}</h1>
				<p class="lede">${intro.lede}</p>
				<div class="actions center">
					${testFlightButton()}
					<a class="btn btn-ghost btn-large" href="/releases">What’s new ${icon('arrow-right')}</a>
				</div>
				<p class="fine">On a computer? Open <strong>${site.testFlightHost}</strong> on your iPhone.</p>
			</section>

			<section class="section container">
				<div class="section-head reveal"><h2>Join in a minute.</h2></div>
				<ol class="steps">
					${steps.map(
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

			<section class="section container">
				<div class="section-head reveal">
					<h2>What’s in the beta.</h2>
					<p>Everything in Cue, Cue Super included.</p>
				</div>
				<ul class="feature-grid">
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
				<div class="section-head reveal"><h2>What you need.</h2></div>
				<dl class="facts reveal">
					${requirements.map((r) => html`<div><dt>${r.label}</dt><dd>${r.value}</dd></div>`)}
				</dl>
			</section>

			<section class="section container narrow">
				<div class="section-head reveal">
					<h2>Tell us what you find.</h2>
					<p>A beta is for finding what’s broken before everyone else does.</p>
				</div>
				<ul class="notes reveal">${feedback.map((step) => html`<li>${inline(step)}</li>`)}</ul>
			</section>

			<section class="section container narrow">
				<div class="section-head reveal"><h2>Questions</h2></div>
				<div class="faq">
					${faq.map((item) => html`<details class="reveal"><summary>${item.q}</summary><p>${inline(item.a)}</p></details>`)}
				</div>
				<p class="more-link"><a href="/help">More in Help ${icon('arrow-right')}</a></p>
			</section>`,
	});
