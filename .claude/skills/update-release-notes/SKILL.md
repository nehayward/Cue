---
name: update-release-notes
description: >-
  Add or update entries in this project's ReleaseNotes.md changelog. Use this
  skill whenever the user wants to update release notes, add a changelog entry,
  document what changed for a release, record a new feature or bug fix in the
  notes, write "what's new" copy, or mentions "release notes" / "changelog" —
  even if they don't name the file. Also use it after finishing a feature or fix
  when the user asks to note it for the next release.
---

# Update Release Notes

Adds entries to both `Changelog.md` (technical detail, developer-facing) and
`ReleaseNotes.md` (user-facing App Store copy) at the project root, in the right
version section, matching the established style of each file.

`Changelog.md` is the source of truth for what changed and why. `ReleaseNotes.md`
is distilled from it for end users. Always update both.

## File structure

`ReleaseNotes.md` lists versions newest-first. The **topmost** `# YYYY.N`
heading is the version currently in development — new entries almost always go
there.

Each version has up to two categorized subsections, in this order:

```
# 2026.4

–– New Features ––
- ...

–– Bug Fixes & Improvements ––
- ...
```

The subsection-header dashes are EN DASHes (`–`, U+2013) — two of them, a space,
the title, a space, two more. Don't retype them by hand; copy an existing header
so the characters are exact. Older versions are sometimes inconsistent (e.g. one
omits the `–– New Features ––` header) — follow the dominant pattern above, not
the exceptions.

## Workflow

1. **Figure out what changed.**
   - If the user described the change(s), use that.
   - If they just said "update the release notes" with no specifics, inspect the
     work to draft entries: recent `git log`, `git diff`, staged/unstaged
     changes, and what was done earlier in this conversation.
   - When unsure what to include or how to word something, show the user your
     proposed bullets and confirm before writing.

2. **Pick the version section.**
   - Read `Configuration/Version.xcconfig` and extract the `VERSION_NUMBER` value — that is the current in-development version.
   - Find the matching `# VERSION_NUMBER` heading in `ReleaseNotes.md` and the matching `## VERSION_NUMBER` heading in `Changelog.md`. Add entries to both. If a heading doesn't exist yet, create it at the very top.
   - Never assume the topmost heading matches the current version — always verify against the config file.

3. **Classify each entry:**
   - **New Features** — a new capability, screen, command, integration, or
     setting the user can now use.
   - **Bug Fixes & Improvements** — fixes, performance work, and refinements to
     behavior that already existed.

4. **Update `ReleaseNotes.md`** — insert the bullet(s) at the **end** of the
   matching subsection, so entries read oldest-to-newest within a release. A
   subsection runs until the next `––` header or the next `# ` version heading.
   If the target subsection doesn't exist yet, create it (New Features goes
   before Bug Fixes & Improvements).

5. **Update `Changelog.md`** — add a `### Feature name` section under the
   current version heading with technical bullet points explaining the what and
   why (file names, method names, data-flow decisions). Insert it before the
   `---` separator that closes the version block, or after the last existing
   `###` section for that version. Match the existing style: backtick for
   identifiers, dash bullets, concise sentences.

6. **Leave older version sections untouched.**

## Merge behavior

Both files are marked `merge=union` in `.gitattributes`, so parallel branches
appending to the same subsection merge cleanly instead of conflicting — git
keeps both sides' lines. Two rules keep this working:

- **Only append.** Never reflow, reorder, or reword an existing bullet as part
  of adding a new one. Union merge resolves per-line, so a line edited on two
  branches survives twice, as two near-duplicate bullets.
- **Creating a new `# YYYY.N` heading is the one risky edit.** If two branches
  each add the same new version heading, union merge produces a duplicate
  heading with no conflict marker to warn anyone. When step 2 tells you to
  create a heading, check the top of the file after merging `main`.

## Writing style

These entries become the App Store "What's New" text — write for end users, not
developers.

- Describe what the user can now do, or what's fixed — never the implementation.
  "Fixed a rare crash when adjusting room volume", not "Fixed nil unwrap in
  VolumeController".
- One bullet per distinct, user-noticeable change.
- **Skip internal-only work** — refactors, file reorganizations, test changes,
  and code cleanup don't belong in release notes. If the change has no visible
  effect, don't add it.
- New Features often lead with a short name: `Feature Name: what it does`. Use
  it when it helps; a plain sentence is fine too.
- Bug-fix bullets usually start with `Fixed…`, `Improved…`, `Restored…`, or
  `Removed…`.
- Sentence case, one line each, no trailing period.

**Good — New Features:**
- `Mac Dock Menu: Right-click the Cue icon in the Dock for full playback control without opening the app`
- `Sleep Timer: New "End of Song" option stops playback when the current track finishes`

**Good — Bug Fixes & Improvements:**
- `Fixed Custom Sleep Timer not showing`
- `Improved Player screen performance: fewer view updates on foreground and resize`

**Avoid:**
- `Refactored DockMenuRenderer into separate files` — internal, no user-visible effect
- `Fixed bug` — too vague; say what was broken and where the user would have seen it
