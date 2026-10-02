import { iconPaths } from './icon-paths.js';

// A tiny HTML templating layer. `html` is a tagged template that escapes every
// interpolated value unless it is already HTML (the result of another `html`
// call, or wrapped in `raw`). Arrays are joined, and null, undefined and false
// render as nothing, so `${cond && html`…`}` and `${items.map(…)}` just work.

const ESCAPES = { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' };

export const escape = (value) => String(value).replace(/[&<>"']/g, (c) => ESCAPES[c]);

class Html {
	constructor(value) {
		this.value = value;
	}
	toString() {
		return this.value;
	}
}

/** Marks a trusted string as HTML so `html` inserts it unescaped. */
export const raw = (value) => new Html(String(value));

const render = (value) => {
	if (value == null || value === false) return '';
	if (Array.isArray(value)) return value.map(render).join('');
	if (value instanceof Html) return value.value;
	return escape(value);
};

export const html = (strings, ...values) =>
	new Html(strings.reduce((out, string, i) => out + string + (i < values.length ? render(values[i]) : ''), ''));

/** An inline Lucide icon. Decorative unless given a label. */
export const icon = (name, { label, className = 'icon' } = {}) => {
	const paths = iconPaths[name];
	if (!paths) throw new Error(`Unknown icon: ${name}`);
	const a11y = label ? `role="img" aria-label="${escape(label)}"` : 'aria-hidden="true"';
	return raw(
		`<svg class="${className}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" ${a11y}>${paths}</svg>`,
	);
};

/**
 * Inline Markdown for short copy: **bold**, *italic*, `code` and [links](…).
 * The input is escaped first, so it can come from any content file.
 */
export const inline = (text) =>
	raw(
		escape(text)
			.replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>')
			.replace(/\*(.+?)\*/g, '<em>$1</em>')
			.replace(/`(.+?)`/g, '<code>$1</code>')
			.replace(/\[(.+?)\]\((.+?)\)/g, '<a href="$2">$1</a>'),
	);
