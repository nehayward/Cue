# DanceLogger

A logger for Apple apps that writes every line to the system log *and* to plain-text log files on the device, so a bug report can carry what happened before it, across relaunches and crashes.

```swift
import DanceLogger

private static let log = DanceLog("route")

Self.log.notice("route → \(group.name): carrying \(items.count) items")
Self.log.error("replace failed: \(error.localizedDescription)")
```

- **System log**: subsystem is the app's bundle identifier (or pass `subsystem:`), category is the logger's name. Shows in Xcode's console and Console.app.
- **Log files**: `Library/Logs/DanceLogger/log-<start time>.log`, kept a week and 20 MB at most (1 MB on watchOS), out of backups. Each line is written straight to disk on a background queue.
- **Interpolation** is `os.Logger`'s, `privacy: .public` included. Values are shown by default; `privacy: .private` writes `<private>`.
- **Credentials are redacted** from every line before it's written anywhere: `X-Plex-Token`, Subsonic-style `t`/`s`/`p` query items, `Bearer …`, and any `…token`, `…password`, `…secret` or `…apikey` followed by `=` or `:`.

## Levels

`debug`, `info`, `notice`, `warning`, `error`, `fault`. `debug` is only recorded in Debug builds or while Detailed Logging is on (`DanceLogStore.shared.isDetailed`, which turns itself off after 24 hours); otherwise its message isn't built.

## Reading the log back

```swift
let store = DanceLogStore.shared

store.beginSession("MyApp 1.2 (34) · iOS 27.0 · iPhone17,1")   // a banner at launch
let url = try store.exportFile(header: "Problem report…")       // header + last 4 MB, as a .txt
let entries = DanceLogStore.entries(in: store.recentText())     // parsed, for an in-app viewer
store.clear()
```

`recentText` and `exportFile` wait for pending lines to be written, so call them off the main thread.

## Cost

On the calling thread, about 1 µs a line on top of the system log's own cost (measured on Linux); writing to the file happens on a background queue. A line that looks like it holds a credential also runs the redaction patterns (about 20 µs). Keep it out of loops that run many times a second.

## Linking

The library is **dynamic** on purpose: a process must hold one copy of `DanceLogStore.shared`, or two writers fight over the same file. Xcode embeds it in an app that gets it through another package; a target that links it (or a framework that depends on it) directly may need it added to its Embed Frameworks phase.

## Tests

`swift test` (pure Foundation; runs on Linux too).
