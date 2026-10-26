import { comparison, details, everywhere, faq, intro, plans, reasons, screens, setup, spotlights } from '../content/audiobooks.js';
import { html, icon, inline, raw } from '../lib/html.js';
import { downloadButton, iphone, page } from '../lib/layout.js';

// ── Smart Resume picture ────────────────────────────────────────────────
// A stretch of speech as bars, paused at one point; the playhead glides back
// and settles in the silence at the end of a sentence (`.resume-demo` in
// styles.css). Heights are fixed, so the page renders the same every time.

const BARS = 56;
const PAUSED_AT = 45; // the bar the listener paused on
const SENTENCE_GAP = [27, 28, 29]; // the silence the playhead lands in
const WORD_GAPS = [6, 13, 19, 35, 40, 50];

const barHeight = (i) => {
	if (SENTENCE_GAP.includes(i)) return 0.06;
	if (WORD_GAPS.includes(i)) return 0.14;
	const wave = Math.abs(Math.sin(i * 1.7) * 0.55 + Math.sin(i * 0.43) * 0.45);
	return Math.round((0.28 + wave * 0.72) * 100) / 100;
};
const barCentre = (i) => `${(((i + 0.5) / BARS) * 100).toFixed(2)}%`;

const resumeDemo = () => html`
	<figure class="vignette resume-demo" style="--paused: ${barCentre(PAUSED_AT)}; --land: ${barCentre(SENTENCE_GAP[1])}" aria-label="Smart Resume: after a pause of three hours, the book goes back 11 seconds and starts at the end of a sentence">
		<div class="vignette-head">
			<span class="chip">${icon('pause')}Paused 3 hours ago</span>
			<span class="chip chip-accent resume-result">${icon('rotate-ccw')}Back 11 s</span>
		</div>
		<div class="wave" aria-hidden="true">
			${Array.from({ length: BARS }, (_, i) => raw(`<span class="${i < PAUSED_AT ? 'heard' : ''}" style="--h: ${barHeight(i)}"></span>`))}
			<span class="wave-land"></span>
			<span class="wave-paused"></span>
			<span class="wave-head"></span>
		</div>
		<p class="resume-words" aria-hidden="true">…and the road ran on toward the hills.<span class="caret"></span> By nightfall the wind had turned, and…</p>
		<figcaption>Back by how long you were away, then into the nearest pause between sentences.</figcaption>
	</figure>`;

// ── Read Along picture ──────────────────────────────────────────────────
// The transcript as the app draws it: lines already read, the line being
// read lighting word by word, the lines to come dimmer, and a looked-up word
// with its definition card. Each word gets its own keyframes so they all
// reset together at the end of the loop.

const READ_LOOP = 8; // seconds
const NOW_LINE = 'their sails folded like tired wings,'.split(' ');
const wordStart = (i) => 0.8 + i * 0.85;

const readKeyframes = () => {
	const pct = (s) => `${((s / READ_LOOP) * 100).toFixed(1)}%`;
	const last = wordStart(NOW_LINE.length - 1) + 1;
	return NOW_LINE.map((_, i) => {
		const start = wordStart(i);
		const end = i < NOW_LINE.length - 1 ? wordStart(i + 1) : last;
		return `@keyframes say-${i} {
			0%, ${pct(start - 0.05)} { opacity: 0.5; text-decoration-color: transparent; }
			${pct(start)} { opacity: 1; text-decoration-color: var(--accent); }
			${pct(end - 0.05)} { opacity: 1; text-decoration-color: var(--accent); }
			${pct(end)}, 91% { opacity: 0.8; text-decoration-color: transparent; }
			96%, 100% { opacity: 0.5; text-decoration-color: transparent; }
		}
		.read-now span:nth-child(${i + 1}) { animation-name: say-${i}; }`;
	}).join('\n');
};

const readDemo = () => html`
	<figure class="vignette read-demo" style="--loop: ${READ_LOOP}s" aria-label="Read Along: the line being read lights up word by word, and a tapped word opens its definition">
		<div class="read-text" aria-hidden="true">
			<p class="read-past">The wind had dropped on the water,</p>
			<p class="read-past">and the boats came home in the <mark>gloaming</mark>,</p>
			<p class="read-now">${NOW_LINE.map((word, i) => html`${i > 0 && ' '}<span>${word}</span>`)}</p>
			<p class="read-next">and the lamps along the quay were lit.</p>
		</div>
		<div class="read-card" aria-hidden="true">
			<span class="read-grabber"></span>
			<p class="read-word">gloaming</p>
			<p class="read-kind">noun</p>
			<p class="read-def">Twilight; the soft light that lingers after the sun has set.</p>
		</div>
		<figcaption>Transcribed on your iPhone as you listen. Tap any word to look it up.</figcaption>
	</figure>`;

const demos = { resume: resumeDemo, read: readDemo };

export const audiobooksPage = () =>
	page({
		path: '/audiobooks',
		title: 'Audiobooks from Plex & Audiobookshelf',
		description:
			'Cue plays your Plex and Audiobookshelf audiobooks with chapters, speed, Smart Resume, a history of every place you’ve been and Read Along — beside your music, in CarPlay, on Apple Watch and on Sonos.',
		head: html`<style>${raw(readKeyframes())}</style>`,
		body: html`
			<section class="hero container">
				<div class="hero-copy">
					<p class="eyebrow">${intro.eyebrow}</p>
					<h1 class="display">${intro.title.split('\n').map((line, i) => html`${i > 0 && raw('<br>')}${line}`)}</h1>
					<p class="lede">${intro.lede}</p>
					<div class="actions">
						${downloadButton()}
						<a class="btn btn-ghost btn-large" href="#why">Why Cue ${icon('arrow-right')}</a>
					</div>
					<ul class="fine devices" aria-label="Plays on">${intro.devices.map((d) => html`<li>${icon(d.icon)}${d.name}</li>`)}</ul>
				</div>
				<div class="hero-visual">
					<div class="hero-phones" style="--glow: url('/${screens[0].file}')">
						${screens.map((shot, i) => iphone(shot, { priority: i === 0 }))}
					</div>
				</div>
			</section>

			<section class="section container" id="why">
				<div class="section-head reveal">
					<h2>${reasons.title}</h2>
					<p>${reasons.lede}</p>
				</div>
				<ul class="steps">
					${reasons.list.map(
						(r) => html`
							<li class="card reveal">
								<span class="card-icon">${icon(r.icon)}</span>
								<h3>${r.title}</h3>
								<p>${r.body}</p>
							</li>`,
					)}
				</ul>
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
						${s.demo
							? html`<div class="spotlight-visual demo reveal">${demos[s.demo]()}</div>`
							: html`<div class="spotlight-visual reveal" style="--glow: url('/${s.screen.file}')">${iphone(s.screen)}</div>`}
					</section>`,
			)}

			<section class="section container" id="compare">
				<div class="section-head reveal">
					<h2>${comparison.title}</h2>
					<p>${comparison.lede}</p>
				</div>
				<div class="compare">
					<div class="compare-head" aria-hidden="true"><span></span><span>${comparison.before}</span><span class="after">${comparison.after}</span></div>
					${comparison.rows.map(
						(row) => html`
							<div class="compare-row reveal">
								<h3>${row.topic}</h3>
								<p class="compare-before">${icon('x')}<span><span class="compare-tag">${comparison.before}</span>${row.before}</span></p>
								<p class="compare-after">${icon('check')}<span><span class="compare-tag">${comparison.after}</span>${row.after}</span></p>
							</div>`,
					)}
				</div>
			</section>

			<section class="section container" id="everywhere">
				<div class="section-head reveal">
					<h2>${everywhere.title}</h2>
					<p>${everywhere.lede}</p>
				</div>
				<div class="platforms three">
					${everywhere.list.map(
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

			<section class="section container" id="details">
				<div class="section-head reveal">
					<h2>The details a book needs.</h2>
					<p>Small things, every one of them noticed by the second chapter.</p>
				</div>
				<ul class="feature-grid">
					${details.map(
						(f) => html`
							<li class="feature reveal">
								<span class="card-icon">${icon(f.icon)}</span>
								<div><h3>${f.title}</h3><p>${f.body}</p></div>
							</li>`,
					)}
				</ul>
			</section>

			<section class="section container" id="super">
				<div class="section-head reveal">
					<h2>${plans.title}</h2>
					<p>${plans.lede}</p>
				</div>
				<div class="plans">
					${[plans.free, plans.super].map(
						(plan, i) => html`
							<article class="plan reveal ${i ? 'plan-super' : ''}">
								<h3>${plan.name}</h3>
								<p class="plan-price">${plan.price}</p>
								<ul>${plan.points.map((point) => html`<li>${icon('check')}${point}</li>`)}</ul>
							</article>`,
					)}
				</div>
			</section>

			<section class="section container narrow" id="setup">
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

			<section class="section container narrow" id="faq">
				<div class="section-head reveal"><h2>Questions</h2></div>
				<div class="faq">
					${faq.map((item) => html`<details class="reveal"><summary>${item.q}</summary><p>${inline(item.a)}</p></details>`)}
				</div>
				<p class="more-link"><a href="/help#audiobooks">More in Help ${icon('arrow-right')}</a></p>
			</section>

			<section class="section container narrow">
				<div class="cta-panel reveal">
					<img src="/apple-touch-icon.png" alt="" width="88" height="88" loading="lazy">
					<h2>Your next chapter is waiting.</h2>
					<p>Free to download. Sign in to Plex or Audiobookshelf and pick up right where you left off.</p>
					${downloadButton()}
				</div>
			</section>`,
	});
