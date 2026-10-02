import { site } from '../config.js';
import { requirements, sections } from '../content/help.js';
import { html } from '../lib/html.js';
import { page } from '../lib/layout.js';
import { blocks } from '../lib/markdown.js';

export const helpPage = ({ embed } = {}) =>
	page({
		path: '/help',
		title: 'Help',
		description: 'Help and answers for Cue: supported services, Sonos setup, purchases and troubleshooting.',
		embed,
		body: html`
			<section class="section container narrow text-center page-intro">
				<p class="eyebrow">Support</p>
				<h1 class="display small">How can we help?</h1>
				<p class="lede">Quick answers, and a real person at <a href="mailto:${site.email}">${site.email}</a>.</p>
			</section>

			<section class="container narrow">
				<ul class="requirements">
					${requirements.map((r) => html`<li><strong>${r.title}</strong><span>${r.body}</span></li>`)}
				</ul>
				<nav class="toc" aria-label="Topics">
					${sections.map((s) => html`<a href="#${slug(s.title)}">${s.title}</a>`)}
				</nav>
				${sections.map(
					(s) => html`
						<h2 class="help-heading" id="${slug(s.title)}">${s.title}</h2>
						<div class="faq">
							${s.items.map((item) => html`<details id="${item.id}"><summary>${item.q}</summary><div class="answer">${blocks(item.a)}</div></details>`)}
						</div>`,
				)}
				<div class="cta-panel compact">
					<h2>Still stuck?</h2>
					<p>Email <a href="mailto:${site.email}">${site.email}</a>. Every message is read and answered personally.</p>
				</div>
			</section>
			<script>
				// Open the answer a /help#<id> link points at.
				const open = () => document.getElementById(location.hash.slice(1))?.setAttribute('open', '');
				open();
				addEventListener('hashchange', open);
			</script>`,
	});

const slug = (text) => text.toLowerCase().replace(/[^a-z0-9]+/g, '-');
