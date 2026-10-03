# Logging

Cue logs through `DanceLog`, from the DanceLogger package (`Packages/DanceLogger`, nothing Cue-specific in it; see its README). Every line goes to two places:

- **The system log**, with the app's bundle identifier as the subsystem (`dance.cue` for the app, `dance.cue.watch` on the watch) and the logger's name as the category. That's Xcode's console, Console.app (filter `subsystem:dance.cue`) and `Scripts/iphone-logs.sh`.
- **Log files on the device** (`DanceLogStore`), plain text, kept for a week. They survive crashes and relaunches, and they're what Settings ▸ Report a Problem attaches to an email to support.

DanceLogger is a dynamic framework, so the app, SonosKit, MusicSearchKit and the watch share a single `DanceLogStore.shared` and a single writer per file. Apps that link SonosKit get it embedded the way they get MusicSearchKit; the watch links and embeds it itself, next to MusicSearchKit (without that it would crash at launch, as MusicSearchKit once did).

## Writing a line

```swift
import DanceLogger

private static let log = DanceLog("route")

Self.log.notice("route → \(group.nameWithCount): carrying \(items.count) items")
Self.log.error("replace failed: \(error.localizedDescription)")
```

Make one logger per area, named for it (`route`, `localplayback`, `sonos`, `plex`, `files`, `discovery`, `carplay`…). `DanceLog.app` is for lines that belong to no one area, SonosKit has `DanceLog.sonos` for speaker calls, and the app has `DanceLog.liveTranscription`. Write the message as a sentence someone reading a support email can follow, with the values that explain it: which group, which item, which error.

Interpolation works like `os.Logger`'s, `privacy: .public` included, so existing calls move over unchanged. Unlike `os.Logger`, values are shown by default: what reaches the file is what support needs. `privacy: .private` writes `<private>` instead, for something support never needs, such as a person's name.

Use `DanceLog` instead of `print`: a `print` never reaches a report.

### Levels

| Level | For | Recorded |
| --- | --- | --- |
| `debug` | Detail for chasing one bug: response bodies, per-device discovery | Debug builds, and while Detailed Logging is on. Otherwise the message isn't even built |
| `info` | The normal flow, worth seeing in a report | Always |
| `notice` | A decision or a change of state: a route switch, a scan finished | Always |
| `warning` | Something went wrong and Cue recovered | Always |
| `error` | Something the user will have noticed failed | Always |
| `fault` | A bug in Cue: a state that should never happen | Always |

### Secrets

Every line goes through DanceLogger's `Redactor` before it's written anywhere, which swaps the value of anything that looks like a credential for `<redacted>`: `X-Plex-Token`, Subsonic's `t`, `s` and `p` query items, `Bearer …`, and any `…token`, `…password`, `…secret` or `…apikey` followed by `=` or `:`. That's a safety net, not permission: don't log credentials on purpose.

### Cost

A `DanceLog` line costs more than an `os.Logger` one: `os.Logger` stores its arguments and formats them only when someone reads the log, while `DanceLog` builds the string on the calling thread (it needs the text for the file), checks it for secrets, then hands it to both the system log and the file queue. Measured on Linux, about 1 µs a line on the caller on top of the system log's own cost, and about 10 µs on a background queue to format and write it. A line holding something that looks like a credential runs the redaction patterns too, about 20 µs. A `debug` line that isn't being recorded costs nothing; its message isn't built.

That's nothing for the events Cue logs: a route switch, a failed request, a scan finishing. Keep it out of loops that run many times a second, like progress ticks, audio buffers or a row per list item; there, use `debug` or don't log.

## The files

On the device they're `Library/Logs/DanceLogger/log-<start time>.log` in the app's container (on the Mac, `~/Library/Containers/<bundle id>/Data/Library/Logs/DanceLogger`). A new file starts when the day changes or the current one passes 2 MB; files older than seven days go, and the oldest go while the folder is over 20 MB. The watch keeps far less (256 KB files, 1 MB in all), having no way yet to send a report. The folder is kept out of backups.

A line reads

```
2026-10-03 14:22:05.123 ERROR [route] route → Kitchen: replace failed: The request timed out.
```

with the time in the device's own time zone. A message over several lines keeps its later lines indented under the first, and one longer than 8,000 characters is cut. Each launch of the app opens with a banner (`AppDelegate` calls `DanceLogStore.shared.beginSession(SupportReport.summary)`):

```
──── 2026-10-03 14:20:11.402 · Launched · Cue 2026.6 (412) · TestFlight · iOS 27.0 · iPhone17,1 ────
```

## Report a Problem

Settings ▸ About ▸ Report a Problem (`Cue/Support`):

- **Email Support** opens the Mail sheet to hi@cue.dance with the log attached as one `.txt` file. The file starts with a header from `SupportReport.header()`: the app version and build, the device, the user ID, Cue Super, where playback is, Sonos, the services switched on, Offline Mode and Detailed Logging. Then the last 4 MB of the log, newest at the bottom.
- **Share Log File** shares the same file through the share sheet, for anyone without Mail set up (Gmail, Outlook, AirDrop, Files).
- **View Log** shows the log on the device, newest first, searchable, with a Problems Only filter.
- **Detailed Logging** records `debug` lines too, for 24 hours, then turns itself off. Ask someone to turn it on, make the problem happen again, then send the report.
- **Clear Log** deletes the files.

## Reading logs from your own iPhone

- `Scripts/iphone-logfile.sh [lines]` copies the log files off the phone into `build/device-logfile/` and joins them into `build/device-logfile.log`. It reaches back across launches and crashes. `CUE_LOG_FILTER=<text>` shows only matching lines.
- `Scripts/iphone-logs.sh [seconds]` relaunches Cue and watches its console live.
- Console.app on a Mac with the phone connected: pick the phone, filter `subsystem:dance.cue`.
