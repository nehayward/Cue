# StoreShots

App Store screenshots and App Preview videos from simulator captures, for any
app. Each screenshot is drawn into its device (iPhone, iPhone Duo, iPad, Apple
Watch), captioned in SF Pro Rounded, over a dark backdrop lit softly in the
app's colour, at the exact size App Store Connect takes, with no alpha. The
previews are the app's own screen recordings, captioned, panning from scene to
scene. Everything is SwiftUI and Core Image on the Mac: no browser, no Rotato,
no templates. Rotato's CLI needs its premium plan; nothing here depends on it.

Everything app-specific is in one JSON project file, so Cue and Clic share the
tool: Cue's is `Marketing/AppStore/storeshots.json`.

```bash
swift build -c release --package-path Tools/StoreShots
Tools/StoreShots/.build/release/storeshots <command> <project.json>
```

`Scripts/app-store-art.sh <command>` does both for Cue's project.

## Commands

| Command | What it does |
| --- | --- |
| `shoot <project> <device> <shot> [--launch]` | Saves the device's simulator screen as `<raw>/<device>/<shot>.png`, status bar at 9:41. Navigate there yourself (or with the simulator tool), or pass `--launch` to relaunch the app with the project's and the shot's launch arguments first. |
| `record <project> <device> <clip> [--seconds 20]` | Records the simulator's screen to `<clips>/<device>/<clip>.mov` (H.264) while you use the app. |
| `render <project> [--device d]… [--shot s]…` | Frames and captions every raw screenshot: `<output>/<device>/NN-<shot>.png`. |
| `preview <project> [--name p]` | Renders the previews: `<output>/previews/<name>.mp4`, plus `<name>.frames.png`, a frame every two seconds to look over. |
| `banner <project> [--name b]…` | The product page header and search results art: `<output>/banners/<name>.png`. |
| `sheet <project>` | `<output>/sheet-<device>.png`: each device's set side by side, as the store shows it. |
| `devices` | The device models, their App Store sizes and slots. |

## The project file

```jsonc
{
  "app": "Cue",
  "bundleID": "dance.cue",
  "launch": ["-dance.cue.blurArtwork", "YES"],   // every `shoot --launch`
  "icon": "icon.png",                             // the hero's icon, with its own corners
  "raw": "raw", "clips": "clips", "output": "output",  // relative to this file
  "theme": {
    "base": "#050706",                            // the backdrop
    "palette": ["#059669"],                       // its light, behind the device; several take turns by shot
    "accent": "#34D399",                          // *words* in titles
    "titleWeight": "bold", "design": "rounded", "finish": "graphite"
  },
  "devices": {
    "iphone": { "model": "iphone-6.3", "simulator": "iPhone 18 Pro" },
    "duo":    { "model": "iphone-duo", "simulator": "iPhone Duo", "display": "primary-1", "landscape": true },
    "ipad":   { "model": "ipad-13", "simulator": "iPad Pro 13-inch (M5)", "deviceWidth": 0.88, "bleed": true },
    "watch":  { "model": "watch-46", "simulator": "Apple Watch Series 12 (46mm)", "bare": true }
  },
  "shots": [
    { "name": "player", "layout": "hero", "title": "All your music. *One player.*", "subtitle": "…" },
    { "name": "radio", "title": "Radio from *everywhere*", "launch": ["-dance.cue.selectedTab", "<…>"], "wait": 9 },
    { "name": "watch", "layout": "pair", "companion": { "device": "watch", "screen": "now-playing" }, "title": "…" }
  ],
  "previews": [
    { "name": "app-preview", "device": "iphone", "scenes": [
      { "clip": "player", "from": 1.0, "duration": 4.0, "title": "…" },
      { "still": "search", "duration": 2.5, "title": "…" }
    ] }
  ],
  "banners": [
    { "name": "universal", "size": [5244, 2950], "safe": [4425, 2247], "title": "…", "subtitle": "…",
      "devices": [{ "device": "iphone", "screen": "radio" }, { "device": "iphone", "screen": "player" }, { "device": "iphone", "screen": "search" }],
      "companion": { "device": "watch", "screen": "now-playing" } }
  ]
}
```

- A device gets a shot when its raw folder has a screenshot by that name.
  `devices` limits a shot to some devices, `overrides.<device>` changes its
  title, subtitle, layout or raw screenshot (`screen`) on one.
- Layouts: `standard` (caption over an upright device, the default), `hero`
  (the icon and a big title, the device large and running off the canvas;
  upright, or turned in 3D with its edge showing when the shot has a `tilt`),
  `pair` (the device with a companion, the iPhone
  with its watch app).
- `bare` devices get the raw screenshot as it is (Apple Watch: the store draws
  the watch round it). `bleed`, on a device or a shot (or a shot's override),
  lets the device run off the bottom at `deviceWidth` instead of shrinking to
  fit (an iPad screen with empty space below).
- A title's lines are balanced, so no word sits alone; a ` ` keeps two
  words together.
- Banners are the product page header (21:9, 3840×1646) and search
  results (3:2, up to 3840×2560) art, or one universal 16:9 asset
  (5244×2950, PNG) that fills both: the caption centred over a row of
  upright devices running off the bottom, the middle one largest, with a
  `companion` in front. `safe` keeps the caption
  and the screens inside a centred box: for the universal asset, the 21:9
  band the header crops to and the 3:2 one search results crop to.
- Previews: scenes play a recording from `from` for `duration` seconds
  (`rate` to speed it up) or hold a still; the camera pans between them.
  `tiltIn` swings the first in, `frame` puts the recording on the device in 3D
  (SceneKit: a metal body, glass front and Dynamic Island in a soft studio,
  `Phone3D`)
  and `float` sways it. Apple's guidance is that previews show the app's own
  screen; Cue's App Preview uses `frame` anyway (its choice, made knowing that).

## Rules it follows

- Sizes (October 2026): header 3840×1646, search results 3:2 from
  1920×1280 to 3840×2560, universal 5244×2950 (PNG), iPhone 6.3" 1206×2622, iPhone Duo inner 2853×2007 (or
  2007×2853), outer 1398×2034, iPad 13" 2064×2752, Watch Series 10–12 416×496,
  Ultra 422×514. App Previews 886×1920 for every iPhone (Duo too), 1200×1600
  for iPad, 15–30 s, ≤30 fps, H.264 High ≤4.0 with a stereo AAC track (silent
  is fine), all of which `preview` writes.
- PNGs have no alpha channel, and `render` checks each is exactly its slot's size.
- The backdrop is drawn in 16-bit float and dithered down to 8 bits, so its
  falloff neither bands nor shows grain. Keep it to plain colours and
  linear, radial or elliptical gradients: SwiftUI linearises a
  `MeshGradient`'s colours twice in that mode.
- Blur covers that aren't yours (Cue: `-dance.cue.blurArtwork YES`, Clic:
  `-screenshotArtwork YES`), and keep lyrics, films and other brands out of
  what's on screen: review has turned Clic down for each.

## For Clic

Write `Scripts/app-store-screenshots/clic.json` in the Clic repo with Clic's
launch arguments (`-screenshotRoom`, `-screenshotScreen`, `-screenshotArtwork
YES`) in `launch`, then

```bash
swift run -c release --package-path ~/Developer/Cue/Tools/StoreShots storeshots shoot clic.json iphone player --launch
swift run -c release --package-path ~/Developer/Cue/Tools/StoreShots storeshots render clic.json
```

The package has no Cue code in it, so it can move to a repository of its own.
