# Port to Clic: the Play On sheet and its volume sliders

Cue rebuilt Play On as an AirPlay-style sheet on `claude/speaker-volume-picker`
(PR #5, 2026-10-05): every room its own volume slider, groups that collapse
and open out, a group bar, and a sideways pan that finally made dragging
volume in a list feel right. Clic (`~/Developer/Clic-deezer`, `origin/main`)
had none of it. Its group and volume UI was `GroupScreen`,
`GroupMenuButton`, `GroupVolumeControlView`, `VolumeMultiControlView` and
`VolumeControlRoomView`.

**Status: ported** on Clic branch `claude/port-play-on-clic-fht48n`
(nehayward/Clic), pushed and unmerged. Written without Xcode, so not yet
built; build, deploy and try it against the speakers before merging. Tested
in Cue on an iPhone against seven rooms.

## What Clic got

- **Where it opens.** The player's group button (`LargePlayerView`, phone and
  wide layouts): a tap opens `PlayOnSheet` through the root router
  (`SheetDestination.playOn(groupID:)`), holding it shows `GroupMenuItems`.
  `GroupScreen` stays behind the sidebar's group button, TV mode and
  `clic://group`, since it also holds scenes.
- **The selected group, not a route.** The sheet takes the player's
  coordinator and follows `Router.main.selectedID`. That group is open (a
  row per room, tap to add or drop); every other group of two or more rooms
  is one collapsed `GroupRow`, and a tap selects it so it opens out. A long
  press on a collapsed group adds one of its rooms to the selected group,
  since Clic, unlike Cue on a speaker, doesn't list those rooms one by one.
- **Root sheet, no zoom.** Presented from the root rather than from the
  button, so it survives the player disappearing while a regroup lands
  (SonosKit skips topology reads for 3.5 s after grouping, and a promoted
  coordinator has no group until then). The zoom out of the button is left
  out; it would need a namespace from the root and a source that outlives
  regroups.
- **`SidewaysPan` is in VibesDS**, behind `sidewaysPan(...)`, with a
  `DragGesture` (16 pt dead zone) before iOS 18. Clic's target stays iOS 17;
  `onScrollPhaseChange` is gated the same way. `VibeSlider` keeps its own
  `SliderDragGesture`, which already has a horizontal-pan mode.
- **`GroupMembership.follow`** sets `Router.main.selectedID` and navigates to
  the player, as Clic's `GroupScreen` does.
- Ported as is: the SonosKit mute hold, `SpeakerVolumeWriter`,
  `VolumeHaptics` with `VolumeRouteRow.adjust`, `GroupBar` (Everywhere, All
  Speakers, Sync), the masks and `AppStorageKeys.playOnSheetHeights`.

### Since then, on the same Clic branch

- **It replaced `GroupScreen`.** Every group button opens it (the player's,
  the speaker list's, TV mode's, `clic://group`). The header has a close
  button on a sheet and a ••• menu with Sort By and New Scene, and the saved
  scenes are the last row of the list. At regular width the player shows it
  as a popover; off the iPhone it's a fixed frame at the fitted height,
  since detents are ignored there.
- **`VibeSlider` drags with `SidewaysPan`** on iOS 18, except touch-down
  sliders, and takes an `onLongPress` (held still half a second; the touch
  then never edits). The volume views mute with it. Worth bringing back to
  Cue's VibesDS: it retires `delayDrag` there too.
- **A regroup still landing.** After dropping the coordinator, SonosKit
  holds topology reads for 3.5 s and `smartGroup` keeps the group under its
  old id with the promoted room at its head. The sheet keeps that group open
  meanwhile (found by `coordinatorRoom.id`) with its rooms untoggleable, and
  dedupes row ids. Cue's sheet has the same gap.

## To fix in Cue: the sheet pops in instead of sliding up

**Done in Cue** on `claude/port-play-on-clic-fht48n`, with `SidewaysPan` moved into VibesDS, `VibeSlider`'s sideways pan (list sliders) and long press to mute, and the regroup wait (`GroupMembership.isSettled`). Not yet built.

Seen in Clic, and Cue's `PlayOnSheet.refit()` is the same code. The first
open of a layout (no height remembered for that room count, bar and so on)
comes up at `estimatedSheetHeight`. The rows are measured once they're on
screen, and `refit()` then animates `sheetHeight`, which changes the detent
while the sheet is still sliding (or zooming) up. That cuts the
presentation short and the sheet pops into place. `openingSheetHeight` can
also move under it mid-slide: it reads the remembered height for the
current `layout`, which changes if the groups are still loading or once
`refit()` remembers a new height.

The fix in Clic (`adcb4e4` on `claude/port-play-on-clic-fht48n`):
- Pin the opening height (`sheetHeight = openingSheetHeight` in `onAppear`
  and on the first `refit`).
- Hold any fit the rows ask for until the sheet is up (`isUp`, set by a
  `.task` after 500 ms), then animate to it.
- Remember the measured height at once, so the next open of that layout
  comes up at the right size and doesn't resize at all.

Copy `pinOpeningHeight()`, `resize(to:)` and the `isUp` / `heldHeight`
state from Clic's `PlayOnSheet.swift`. Check it against the zoom
transition, which takes longer than a plain slide.

## What Clic was missing that Cue's sheet assumes

- **No `PlaybackRoute` and no This Device.** Clic only plays on speakers. Drop
  `DeviceRow`, `PlaybackRoute.isSwitching`, the transfer prompt
  (`RouteTransferPrompt`) and `select(.device)`. The sheet becomes a speaker
  and group picker for the selected group. In Cue, `expandedGroup` is
  `route.isSwitching ? nil : route.group`; in Clic it's the selected group.
  Collapsed `GroupRow`s still make sense for the other groups, and so does
  opening one out when it's chosen.
- **Deployment target is iOS 17** (Cue's app target is 26). `SidewaysPan` is
  a `UIGestureRecognizerRepresentable`, which needs iOS 18. Either raise
  Clic's target or put the pan behind `if #available(iOS 18, *)` with the old
  `DragGesture` as the fallback. The glass, `safeAreaBar` and
  `scrollEdgeEffectStyle` bits already have pre-26 fallbacks.
- **`GroupMembership`** (in Cue's `GroupMenuButton.swift`) is the shared regroup
  logic: toggle, Everywhere, Ungroup All, Play Only Here, and following the
  promoted coordinator. Clic's `GroupMenuButton.swift` was the older version.
  Bring Cue's over whole, then swap `follow(from:to:)`'s `PlaybackRoute`
  branch for Clic's router.

## Port these as they are

1. **`Packages/SonosKit`: hold a mute against the poll** (`0931e512`, the
   SonosKit part). `Room.holdMute(_:)` and `GroupRoom.holdMute(_:)` show the
   mute at once and set `muteHeldUntil` 2.5 s out. The poll in
   `SonosService` skips a room or group while `isMuteHeld`. Without it, a
   read that left before the speaker took the change puts the old state back,
   so the slash or icon flickers.
2. **`SidewaysPan`** (in `PlayOnSheet.swift`). See below; worth putting in
   VibesDS rather than the sheet.
3. **`SpeakerVolumeWriter`** (in `PlayOnSheet.swift`). It sends a room's or a
   group's level to the model at once and to the speaker at most every
   `interval`, always the latest and never a repeat. It holds
   `isEditingVolume` until a moment after the last write, then rereads what
   the change moved. This is what keeps the fill under the finger.
4. **`VolumeHaptics`** with `VolumeRouteRow.adjust`. Tick per percent from the
   drag itself, firmer bump at 0 and 100.
5. **`AppStorageKeys.playOnSheetHeights`** (Defaults) for the fitted heights.

## The sideways pan, and why it's the real improvement

SwiftUI's `DragGesture` takes the touch first and decides later. In a
`ScrollView` or a sheet, a slider row either swallows vertical drags (the
list won't scroll, the sheet won't pull down) or needs a dead zone
(`VibeSlider`'s `delayDrag`, 16 pt) that makes it feel late.
`.simultaneousGesture` and `.highPriorityGesture` choose who wins. Neither
lets a gesture decline to start because of its direction.

`SidewaysPan` is a `UIPanGestureRecognizer` brought into SwiftUI with
`UIGestureRecognizerRepresentable` (iOS 18):

- `gestureRecognizerShouldBegin` returns true only when the motion so far is
  more sideways than vertical. An up or down drag fails it at once.
- `shouldBeRequiredToFailBy` makes every other pan (the scroll view's, the
  sheet's dismiss) wait for it. So a sideways drag is never also a scroll, and
  a vertical one goes straight to the list.
- On `.began` it resets the translation to zero, so the few points it took to
  tell the direction don't jump the level.
- The level is `startLevel + translation / rowWidth`, relative to where the
  drag began, not where the finger is. A tap never jumps the volume.

Other places to use it, in Cue and Clic: `VibeSlider` (VibesDS) is used by
`GroupScreen`, `VolumeControlView`, `VolumeControlRoomView`, `RoomVolumeView`,
the player's volume, alarms and scenes. Moving `SidewaysPan` into VibesDS and
using it there on iOS would retire `delayDrag`. The Mac and TV keep
`DragGesture`. (Clic now has it in VibesDS; Cue's is still in the sheet.)

## Lessons that apply to anything on the glass sheet

- **Don't dim with `.opacity` on glass.** A white icon at `.opacity(0.35)`
  still showed full white on the iPhone (the same code rendered faded in a
  Mac `ImageRenderer`). `.foregroundStyle(.tertiary)` dims properly.
- **Cut-outs need masks, not `destinationOut`.** Blends only erase what shares
  their compositing group, and overlays and offsets quietly start a new one.
  The badge's hole is an even-odd `BadgeCut` mask on the speaker. The count is
  a `luminanceToAlpha` mask on the badge. The mute gap is a `SlashCut` mask.
- **Size the sheet from its parts, never from its own height.** Measure the
  header, rows, bar and bottom inset with `onGeometryChange` (it reports the
  first value, unlike `onScrollGeometryChange`) and add them up (`refit()`).
  Using the sheet's current height fails while it's still zooming in, and it
  opened full height.
- **Fire haptics from the gesture, not from watching the value.**
  `sensoryFeedback(trigger:)` waits for the redraw and skips steps on a fast
  drag.
- **Keep the bar out of the list.** Put it in the `VStack` under the
  `ScrollView`, not in a `safeAreaBar`, or the rows show through its circles
  and cut-outs. Fade the list's foot with a mask instead.

## Commits on Cue's branch, oldest first

`9eafb13f` AirPlay-style sheet with a volume per room · `57ff1f2c` fit to
rooms · `d4a57bd6` zoom from the button, All Speakers volume · `10739f53`
pull down to close · `e9b1ee5b` Sync · `0d8ed135` room count on the icon ·
`282a6aee` slide at zero, strike muted icons · `299fa2cf` mute and Play Only
Here per room · `2873a045` redraw only the changed row · `40f6b798` back in a
sheet · `d9c80c40` refit from the first measure · `8c99c443` masks, not
blends · `0931e512` group rows, group bar, haptics, mute hold, final sizing.

The sheet changed shape several times on the way. Copy the final
`PlayOnSheet.swift`, `GroupMenuButton.swift` and the SonosKit changes rather
than replaying the commits. Then cut out the device-route parts listed above.
