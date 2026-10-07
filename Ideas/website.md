# Website (cue.dance)

What's left for the site in `Website/`, as of October 2026. How the site works
is in `Website/README.md`; this note is the to-do list.

## Before going live

- [x] **Deploy.** `cd Website && make install && make deploy`. `wrangler.toml`
  makes cue.dance a Workers custom domain, so Cloudflare creates the DNS
  record and certificate on the first deploy (the apex had no record, so a
  plain route would never have answered). Afterwards check `/`, `/help`,
  `/api/releases/2026.1.json`, and Help and What's New inside the app.
- [ ] **Review the legal pages** in `Website/src/pages/legal.js`. They were
  drafted from the code: Mixpanel (anonymous ID, no songs or searches),
  RevenueCat, Cloudflare logs, no cookies on the site.
- [ ] **Confirm `hi@cue.dance` receives mail.** It's the only contact on the
  site, in Help, the press kit and the footer. Email Routing is on for
  cue.dance and forwards it to the same inbox as hi@clic.dance; send it a
  test message.
- [ ] **Delete the duplicate screenshots** in `Website/public/press/`
  (`Screenshot … 3.42.05 PM.png`, `… 3.42.42 PM.png`). They're near-copies of
  Radio and Plex Library and get uploaded with every deploy.
- [ ] **Check the logo rules.** The services section shows the Apple Music
  and Plex marks (Simple Icons, `Website/src/lib/brand-marks.js`). Apple's
  identity guidelines are strict; if in doubt, swap the mark for an icon.
- [ ] **Album art.** The screenshots, and so the hero and the social card,
  show real Dua Lipa and Lady Gaga covers. Fine for App Store-style shots;
  consider re-capturing with artwork you have rights to before marketing
  pushes.

## On launch day

- [ ] Set `appStoreId` in `Website/src/config.js`. "Coming soon to the App
  Store" becomes a download button everywhere, the header gets one, and the
  Smart App Banner turns on.
- [ ] Add the release date to 2026.1 in `Website/src/content/releases.js`.
- [ ] Ship the app as **2026.1**. `Configuration/Version.xcconfig` says
  2026.8; the What's New banner asks the site for the app's own version and
  stays hidden when the site doesn't have it.

## Screenshots wanted

Each is a one-line swap in `Website/src/content/home.js`. Save the original
to `public/press/`, a ~1150px-tall JPEG to `public/shots/`, and re-run
`make og` if the social card should change.

- [ ] **Play On picker** with rooms listed: `handoff.screen`, for the
  phone-and-rooms animation.
- [ ] **Offline Mode** in use: the "Downloads for the road" spotlight
  (currently Plex Library).
- [ ] **Live Transcription** on a station: the "Live radio, word for word"
  spotlight (currently Radio).

## In the app

- [ ] `CueIconGlass` (onboarding, Settings header, sidebar) is still the
  green *outline* play; the real icon, `Cue/Icon.icon`, renders as a solid
  play. `AppIcon.appiconset` still holds the old teal bars. The site uses a
  render of `Icon.icon` (Icon Composer's `ictool`).
- [ ] Have `HelpWebView` and `WhatsNewWebView` load their pages with
  `?embed` instead of injecting CSS that hides `header.header`, `footer`,
  `main > section.text-center` and `.latest-hero`. Until then, keep those
  selectors on the site.

## Later

- **Newsletter.** Removed from the site until it's set up. The app's
  `NewsletterKit` already posts to `api.cue.dance/newsletter/subscribe`; an
  earlier version of the site had a no-JavaScript form that forwarded to it
  through the Worker (see git history for `Website/src/pages/newsletter.js`).
- **Cue Super.** Left off the site on purpose. When it's ready, the plans
  section in git history listed the free/Super split from
  `GatedFeature.requirement`.
- **iPad, Mac, Apple TV, Scenes, Cue Mini.** The first release is iPhone
  only; add them back to the copy as they ship.
- **A short hero video** (5–8 s: browse, tap Play On) and **TestFlight
  quotes** for social proof.
