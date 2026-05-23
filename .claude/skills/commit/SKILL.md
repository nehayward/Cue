---
name: commit
description: >-
  Draft a git commit message for the current changes and show it for approval
  before committing. Use this whenever the user wants to commit, asks to "commit
  this" / "commit my changes" / "make a commit", or finishes a chunk of work and
  wants it recorded. Always previews the message and waits for the user's OK —
  it never commits without showing the message first.
---

# Commit

Drafts a commit message in this project's style, shows it to the user, and
commits only after they approve.

## The one rule

**Never run `git commit` before the user has seen the message and approved it.**
The whole point of this skill is the preview step — show, wait, then commit.

## Workflow

1. **See what's changed.** Run `git status`, `git diff`, and `git diff
   --staged`.
   - If changes are already staged, the commit covers exactly those — don't
     stage more.
   - If nothing is staged, the commit covers the modified/new files. List them
     in the preview so the user knows what's included, and stage them as part
     of committing.

2. **Draft the message** (format below). Read the diff and base the subject and
   body on what it actually does — don't guess from filenames.

3. **Show the preview** — print the file list and the full message in a code
   block, then STOP. Ask the user to approve or say what to change. Do not
   commit in this turn.

4. **On approval, commit.** Use a HEREDOC so the body and footer survive intact:
   ```
   git commit -m "$(cat <<'EOF'
   Subject line here

   Body paragraph here.

   Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
   EOF
   )"
   ```
   If the user asked for edits, revise and show the preview again — still don't
   commit until they're happy.

## Message format

```
<imperative subject — what the commit does>

<body: why the change was needed and what it does; wrap ~72 chars.
Use "- " bullets when there are several distinct changes.>

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
```

- **Subject** — imperative mood ("Fix…", "Add…", "Reduce…", not "Fixed" /
  "Adds"), capitalized, no trailing period, ≤ ~72 chars.
- **Body** — explain the *why*; the diff already shows the *what*. Skip the body
  only for genuinely trivial commits. Wrap lines at ~72 chars.
- **Footer** — always end with the `Co-Authored-By` line above.

## Examples (from this repo)

**Single focused change:**
```
Restore Live Activity to its former glory with 5 volume steps

iOS 26.2 lifted the Live Activity button-count limit, so route that
version range to a new Pre27 view that brings back the volume step and
mute controls. Step count is configurable via the LiveActivityStep
defaults key (default 5), and the iOS 26 limitation notice in
Preferences is removed.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
```

**Several related changes — use bullets:**
```
Reduce LargePlayerView body re-evaluations

Foregrounding the Mac app or toggling the inspector re-rendered the
player heavily because its body depended on scenePhase, size class, a
parent-fabricated binding, and refreshID.

- Switch group from @Binding to @Bindable so the parent stops
  fabricating a fresh Binding every eval
- Move scenePhase/refreshID observation into dedicated modifiers
- Extract PlaybackView / MediaControlsView / SongTitleButton so hover
  and toolbar state invalidate only the subview that owns it

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
```
