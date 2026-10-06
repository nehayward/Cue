import { html, inline } from './html.js';

/**
 * Renders short Markdown: paragraphs, "- " and "1. " lists, and the inline
 * styles `inline` knows. Enough for help answers and release notes, and
 * nothing a content file could use to inject HTML.
 */
export const blocks = (text) => {
	const out = [];
	let list = null;
	const flush = () => {
		if (list) out.push(list.ordered ? html`<ol>${list.items}</ol>` : html`<ul>${list.items}</ul>`);
		list = null;
	};
	for (const line of text.split('\n').map((l) => l.trim())) {
		const item = line.match(/^(-|\d+\.)\s+(.*)$/);
		if (item) {
			const ordered = item[1] !== '-';
			if (list && list.ordered !== ordered) flush();
			list ??= { ordered, items: [] };
			list.items.push(html`<li>${inline(item[2])}</li>`);
		} else {
			flush();
			if (line) out.push(html`<p>${inline(line)}</p>`);
		}
	}
	flush();
	return out;
};
