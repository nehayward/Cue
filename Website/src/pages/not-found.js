import { html, icon } from '../lib/html.js';
import { page } from '../lib/layout.js';

export const notFoundPage = (path) =>
	page({
		path,
		title: 'Not Found',
		body: html`
			<section class="section container narrow text-center page-intro">
				<p class="eyebrow">404</p>
				<h1 class="display small">This track skipped.</h1>
				<p class="lede">There’s nothing at this address. It may have moved, or never existed.</p>
				<div class="actions center"><a class="btn btn-primary" href="/">Back to Cue ${icon('arrow-right')}</a><a class="btn btn-ghost" href="/help">Help</a></div>
			</section>`,
	});
