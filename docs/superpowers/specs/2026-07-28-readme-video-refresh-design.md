# README Demo Video Refresh Design

**Date:** 2026-07-28
**Status:** Approved direction, pending implementation review

## Goal

Replace the outdated README hero demo with a concise recording of the current
application, and add a separate focused demo to the “Native Pet usage badge /
原生 Pet 用量徽标” section.

The source recording is:

`/Users/benjaminz/Desktop/Screen Recording 2026-07-28 at 10.51.31.mov`

The source is immutable and must not be overwritten.

## Source Analysis

The complete 44.615-second, 3840×2160 recording has been reviewed:

- `0.0–5.5s`: recording startup, QuickTime menus, and idle time; exclude.
- `5.5–18.5s`: dashboard navigation through History, Overview, History, and
  Sessions; useful for the main demo, but real session names must be hidden.
- `18.5–25.8s`: Overview and the “Show Usage by Codex Pet” control; shows the
  native Pet usage indicator at 76%; core content for the main demo.
- `25.8–40.5s`: the dashboard is closed and the Pet moves while the indicator
  follows it; core content for the Pet-specific demo.
- `40.5–44.615s`: clicking the indicator opens the Pet summary; the real
  project/task title must be hidden while usage and task-count information
  remain visible.

The recording has no audio. The edited videos will not add audio, captions, or
instructional overlays.

## Deliverables

### Main README demo

Replace the current files in place so existing links remain stable:

- `docs/assets/codex-menubar-demo.mp4`
- `docs/assets/codex-menubar-demo.gif`

Target duration: approximately 22–26 seconds.

Content:

1. Open the dashboard and show the current Overview.
2. Briefly show History and Sessions.
3. Return to Overview and enable “Show Usage by Codex Pet”.
4. Show the 76% indicator beside the native Pet.
5. Show the indicator following Pet movement.
6. Click the indicator and show the usage summary.

### Pet-specific demo

Add:

- `docs/assets/codex-pet-usage-demo.mp4`
- `docs/assets/codex-pet-usage-demo.gif`

Target duration: approximately 10–13 seconds.

Content:

1. Enable “Show Usage by Codex Pet”.
2. Show the 76% indicator appearing beside the native Pet.
3. Show the indicator following Pet movement.
4. Click the indicator and show the summary.

## Editing and Framing

Use segment-specific reframing instead of shrinking the full 4K desktop:

- Dashboard shots focus on the app window.
- Pet shots focus on the lower-right Pet and indicator.
- Summary shots keep the Pet, indicator, and expanded summary legible.
- Remove the Dock, desktop widgets, menu-bar clutter, and Stage Manager
  thumbnails from the visible frame whenever cropping permits.
- Use clean cuts; avoid decorative transitions.

The final MP4 files use H.264, `yuv420p`, 30 fps, and fast-start metadata. GIFs
are generated from the final sanitized MP4 files so privacy treatment and
content cannot diverge.

## Privacy Treatment

The final assets must not expose unrelated local information:

- Hide real task/session names in the Sessions view.
- Hide the real project/task title in the expanded Pet summary.
- Keep the Primary usage percentage, Secondary state, and task count visible.
- Crop out unrelated desktop content where possible.
- When cropping is insufficient, use a stable opaque or blurred mask that
  fully covers the sensitive text for every affected frame.

## README Changes

Update both `README.md` and `README.zh-CN.md`:

- Keep the existing hero media structure and paths; the replaced hero files
  automatically update the top demo.
- Add the Pet-specific GIF, linked to its MP4, under “Native Pet usage badge”
  in English.
- Add the same media under “原生 Pet 用量徽标” in Chinese.
- Add a direct MP4 link in both languages for users whose Markdown renderer
  does not animate or display the GIF.

## Verification

Before completion:

1. Probe both MP4 files and verify codec, dimensions, frame rate, duration,
   pixel format, and absence of audio.
2. Decode every final MP4 and GIF fully with FFmpeg and require zero errors.
3. Render contact sheets plus boundary frames from all four final assets.
4. Visually confirm:
   - the current UI and Pet indicator are legible;
   - all privacy-sensitive text is covered throughout;
   - no obsolete or duplicated demo content remains;
   - cuts and reframing do not jump unexpectedly;
   - the GIFs match their MP4 sources.
5. Validate that every README media path exists and both language sections
   render the intended links.
6. Run the repository’s relevant documentation or project checks available in
   the current environment.

## Non-goals

- Do not modify application behavior or source code.
- Do not add narration, music, subtitles, or bilingual text overlays.
- Do not overwrite or delete the original source recording.
- Do not publish a release as part of this README/media-only change unless
  separately requested.
