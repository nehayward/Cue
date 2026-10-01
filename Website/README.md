# cue.dance

The website for Cue. It's a Cloudflare Worker that renders each page to HTML,
plus a `public/` folder of static files. There's no framework and no
client-side JavaScript beyond a few lines on /help. The only dependency is
`wrangler`.

```bash
make install   # once
make dev       # http://localhost:8787, reloads on save
make test      # node --test
make deploy    # tests, then publishes to cue.dance
```

## Where things live

| To change… | Edit |
| --- | --- |
| Name, email, App Store ID | `src/config.js` |
| Home page copy: hero, features, services, FAQ | `src/content/home.js` |
| Help questions | `src/content/help.js` |
| Plex & Subsonic page | `src/content/self-hosted.js` |
| Press kit (copy, facts, screenshots) | `src/content/press.js`, files in `public/press/` |
| Releases: notes, dates, headlines, video reels | `src/content/releases.js` |
| Privacy policy, terms | `src/pages/legal.js` |
| Colours, spacing, every style | `public/styles.css` (tokens at the top) |
| Routes, redirects, headers | `src/worker.js` |

Pages in `src/pages/` only lay out content. Wording changes almost never
touch them.

## How it fits together

- **`src/lib/html.js`**: the `html` tagged template. It escapes every
  interpolated value, so content can't break the markup. Also has
  `icon(name)` for inline Lucide icons (`src/lib/icon-paths.js`) and
  `inline()` for `**bold**`, `*italic*` and `[links](…)` in copy.
- **`src/lib/layout.js`**: `page()` wraps every page in the same `<head>`,
  meta tags, header and footer. A page only supplies its body, title and
  description.
- **`src/lib/markdown.js`**: paragraphs and lists for help answers and legal
  text.
- **`public/`**: served by Cloudflare before the Worker runs. Static file
  cache headers are in `public/_headers`. When a styles change mustn't mix
  with a cached copy, bump `ASSET_VERSION` in `layout.js`.

## Release notes

Releases live in `src/content/releases.js`, newest first. Each one has a
version, date, headline and notes. To publish one, add it at the top (the
notes can be pasted from the app's `ReleaseNotes.md`), then `make deploy`.
That updates `/releases`, `/releases/<version>` and the JSON the app reads.

## Contracts with the app

The app depends on these. Keep them working, or change the app first.

| URL | Used by |
| --- | --- |
| `/help`, `/help#<id>` | `HelpWebView.swift` |
| `/releases/<version>` | `WhatsNewWebView.swift` |
| `/api/releases/<version>.json` → `{ version, headline, … }` | `LatestReleaseFetcher.swift` (any non-200 hides the banner) |

The web views hide the site's chrome with injected CSS that targets
`header.header`, `footer`, `main > section.text-center` and `.latest-hero`.
Both pages also accept `?embed`, which renders them without a header or
footer. Moving the app to `?embed` would remove that coupling.

## Launch checklist

- [ ] Set `appStoreId` in `src/config.js`. "Coming soon to the App Store"
      becomes a download link, the header gets a download button, and the
      Smart App Banner turns on.
- [ ] Add a 1200×630 social card and reference it from `page()`. Until then,
      the app icon is used.
- [ ] Review `src/pages/legal.js` (privacy and terms).
