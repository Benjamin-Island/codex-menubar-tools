# README Demo Video Refresh Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the outdated README hero demo and add a focused Native Pet usage badge demo using the fully reviewed 2026-07-28 recording.

**Architecture:** Produce two privacy-safe 1280×1080 H.264 masters from fixed source ranges with segment-specific crops, then derive palette-optimized GIFs only from those sanitized masters. Replace the existing hero assets in place, add separate Pet assets, and reference the Pet pair from both language versions of the README.

**Tech Stack:** FFmpeg/ffprobe, H.264, GIF palette generation, Markdown, Git.

## Global Constraints

- Treat `/Users/benjaminz/Desktop/Screen Recording 2026-07-28 at 10.51.31.mov` as immutable.
- Exclude source time `0.0–5.5s`.
- Main demo target duration is approximately 22–26 seconds.
- Pet-specific demo target duration is approximately 10–13 seconds.
- Final MP4 files use H.264, `yuv420p`, 30 fps, 1280×1080, and fast-start metadata.
- Final GIF files are generated only from their corresponding sanitized MP4 files.
- Add no audio, captions, subtitles, instructional overlays, or decorative transitions.
- Hide every real Sessions task/session name and the real Pet-summary project/task title.
- Keep Primary usage, Secondary state, task count, and the Pet visible.
- Crop out the Dock, menu bar, widgets, and Stage Manager thumbnails.
- Modify no application source code or behavior.

---

### Task 1: Render and verify the refreshed main demo

**Files:**
- Modify: `docs/assets/codex-menubar-demo.mp4`
- Modify: `docs/assets/codex-menubar-demo.gif`
- Read: `/Users/benjaminz/Desktop/Screen Recording 2026-07-28 at 10.51.31.mov`
- Temporary: `/tmp/codex-menubar-main-*.mp4`
- Temporary: `/tmp/codex-menubar-main-*.jpg`

**Interfaces:**
- Consumes: the immutable 3840×2160 source recording.
- Produces: a sanitized 1280×1080 MP4 and a matching GIF used by the existing README hero links.

- [ ] **Step 1: Re-probe the source and record its checksum**

Run:

```bash
ffprobe -v error \
  -show_entries format=duration,size:stream=codec_name,codec_type,width,height,avg_frame_rate,pix_fmt \
  -of json \
  "/Users/benjaminz/Desktop/Screen Recording 2026-07-28 at 10.51.31.mov"

shasum -a 256 \
  "/Users/benjaminz/Desktop/Screen Recording 2026-07-28 at 10.51.31.mov"
```

Expected: one H.264 video stream, no audio stream, 3840×2160 dimensions,
approximately 44.615 seconds, and this exact checksum:

```text
f89db78be6c78d22940b4249e19e56e26b77d18ad7030ddf5a62f54963fadba8
```

- [ ] **Step 2: Render four normalized main-demo segments**

Use these fixed source ranges and crops:

| Segment | Source range | Crop | Purpose |
|---|---:|---:|---|
| `main-dashboard` | `9.8–18.8s` | `1280:1080:1220:60` | Open dashboard; show Overview, History, and Sessions |
| `main-control` | `19.2–25.6s` | `1280:1080:1220:60` | Return to Overview and clearly show the Pet usage control |
| `main-follow` | `32.6–37.8s` | `960:810:2880:1200`, scaled to 1280×1080 | Show the usage indicator following the native Pet |
| `main-summary` | `38.5–42.3s` | `960:810:2880:1200`, scaled to 1280×1080 | Show the click and expanded summary without the later closed state |

Render the dashboard segment, enabling strong privacy blurs only after the
Sessions tab becomes visible:

```bash
ffmpeg -hide_banner -y \
  -i "/Users/benjaminz/Desktop/Screen Recording 2026-07-28 at 10.51.31.mov" \
  -filter_complex "\
[0:v]trim=start=9.8:end=18.8,setpts=PTS-STARTPTS,\
crop=1280:1080:1220:60,fps=30,format=yuv420p,split=4[b0][s1][s2][s3];\
[s1]crop=520:390:90:310,gblur=sigma=25:steps=6[m1];\
[b0][m1]overlay=90:310:enable='between(t,7.4,9.0)'[o1];\
[s2]crop=610:135:640:300,gblur=sigma=25:steps=6[m2];\
[o1][m2]overlay=640:300:enable='between(t,7.4,9.0)'[o2];\
[s3]crop=610:115:640:680,gblur=sigma=25:steps=6[m3];\
[o2][m3]overlay=640:680:enable='between(t,7.4,9.0)',setsar=1[out]" \
  -map "[out]" -an -c:v libx264 -preset slow -crf 22 -pix_fmt yuv420p \
  /tmp/codex-menubar-main-dashboard.mp4
```

The three masks cover the left-hand task names, selected task title, and local
path.

Render the control and follow segments:

```bash
ffmpeg -hide_banner -y \
  -i "/Users/benjaminz/Desktop/Screen Recording 2026-07-28 at 10.51.31.mov" \
  -filter_complex "\
[0:v]trim=start=19.2:end=25.6,setpts=PTS-STARTPTS,\
crop=1280:1080:1220:60,fps=30,format=yuv420p,split=4[b0][s1][s2][s3];\
[s1]crop=520:390:90:310,gblur=sigma=25:steps=6[m1];\
[b0][m1]overlay=90:310:enable='between(t,0,2.0)'[o1];\
[s2]crop=610:135:640:300,gblur=sigma=25:steps=6[m2];\
[o1][m2]overlay=640:300:enable='between(t,0,2.0)'[o2];\
[s3]crop=610:115:640:680,gblur=sigma=25:steps=6[m3];\
[o2][m3]overlay=640:680:enable='between(t,0,2.0)',setsar=1[out]" \
  -map "[out]" -an -c:v libx264 -preset slow -crf 22 -pix_fmt yuv420p \
  /tmp/codex-menubar-main-control.mp4

ffmpeg -hide_banner -y \
  -i "/Users/benjaminz/Desktop/Screen Recording 2026-07-28 at 10.51.31.mov" \
  -vf "trim=start=32.6:end=37.8,setpts=PTS-STARTPTS,crop=960:810:2880:1200,scale=1280:1080:flags=lanczos,fps=30,format=yuv420p,setsar=1" \
  -an -c:v libx264 -preset slow -crf 22 -pix_fmt yuv420p \
  /tmp/codex-menubar-main-follow.mp4
```

Render the summary segment with a strong blur over only the real project/task
title:

```bash
ffmpeg -hide_banner -y \
  -i "/Users/benjaminz/Desktop/Screen Recording 2026-07-28 at 10.51.31.mov" \
  -filter_complex "\
[0:v]trim=start=38.5:end=42.3,setpts=PTS-STARTPTS,\
crop=960:810:2880:1200,scale=1280:1080:flags=lanczos,\
fps=30,format=yuv420p,split=2[base][titlesrc];\
[titlesrc]crop=560:70:470:300,gblur=sigma=30:steps=6[titleblur];\
[base][titleblur]overlay=470:300:enable='between(t,1.1,3.8)',setsar=1[out]" \
  -map "[out]" -an -c:v libx264 -preset slow -crf 22 -pix_fmt yuv420p \
  /tmp/codex-menubar-main-summary.mp4
```

Do not cover the Primary, Secondary, or task-count row.

Expected: four playable, silent, 1280×1080, 30 fps H.264 files with no readable
private text.

- [ ] **Step 3: Concatenate the four main segments**

Concatenate the normalized video streams in table order:

```bash
ffmpeg -hide_banner -y \
  -i /tmp/codex-menubar-main-dashboard.mp4 \
  -i /tmp/codex-menubar-main-control.mp4 \
  -i /tmp/codex-menubar-main-follow.mp4 \
  -i /tmp/codex-menubar-main-summary.mp4 \
  -filter_complex "[0:v][1:v][2:v][3:v]concat=n=4:v=1:a=0,format=yuv420p[out]" \
  -map "[out]" \
  -an -c:v libx264 -preset slow -crf 22 -pix_fmt yuv420p \
  -movflags +faststart \
  docs/assets/codex-menubar-demo.mp4
```

Expected duration: 24.4 seconds, allowing ±0.2 seconds for timestamp
normalization.

- [ ] **Step 4: Generate the hero GIF from the sanitized MP4**

Run:

```bash
ffmpeg -hide_banner -y \
  -i docs/assets/codex-menubar-demo.mp4 \
  -filter_complex "\
[0:v]fps=10,scale=900:-2:flags=lanczos,split[gif_a][gif_b];\
[gif_a]palettegen=max_colors=96:stats_mode=diff[palette];\
[gif_b][palette]paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle[out]" \
  -map "[out]" \
  -loop 0 \
  docs/assets/codex-menubar-demo.gif
```

Expected: an animated 900-pixel-wide GIF whose duration matches the MP4 within
0.2 seconds and whose file size is at most 10 MiB.

If the GIF exceeds 10 MiB, rerender with `fps=8`, `scale=800:-2`,
`max_colors=80`, and `bayer_scale=5`, then repeat verification.

- [ ] **Step 5: Verify and visually review the main assets**

Run:

```bash
for media in \
  docs/assets/codex-menubar-demo.mp4 \
  docs/assets/codex-menubar-demo.gif
do
  ffprobe -v error \
    -show_entries format=duration,size:stream=codec_name,codec_type,width,height,r_frame_rate,pix_fmt \
    -of json \
    "$media" || exit 1
done

ffmpeg -v error -i docs/assets/codex-menubar-demo.mp4 -f null -
ffmpeg -v error -i docs/assets/codex-menubar-demo.gif -f null -

ffmpeg -hide_banner -loglevel error -y \
  -i docs/assets/codex-menubar-demo.mp4 \
  -vf "fps=1,scale=320:-2,tile=5x5" \
  -frames:v 1 \
  /tmp/codex-menubar-main-contact-sheet.jpg
```

Also extract frames 0.1 seconds before and after every concatenation boundary.
Visually require that masks fully cover private text, the current interface is
legible, the Pet and indicator remain inside the frame, and no desktop chrome
appears.

If any private glyph remains visible, expand that mask by 20 pixels on every
affected edge, rerender both MP4 and GIF, and repeat the full decode and visual
review.

- [ ] **Step 6: Confirm the source was not changed**

Run `shasum -a 256` on the source again and require:

```text
f89db78be6c78d22940b4249e19e56e26b77d18ad7030ddf5a62f54963fadba8
```

- [ ] **Step 7: Commit the refreshed hero assets**

```bash
git add docs/assets/codex-menubar-demo.mp4 docs/assets/codex-menubar-demo.gif
git commit -m "docs: refresh the README demo"
```

### Task 2: Render and verify the Pet-specific demo

**Files:**
- Create: `docs/assets/codex-pet-usage-demo.mp4`
- Create: `docs/assets/codex-pet-usage-demo.gif`
- Read: `/Users/benjaminz/Desktop/Screen Recording 2026-07-28 at 10.51.31.mov`
- Temporary: `/tmp/codex-pet-usage-*.mp4`
- Temporary: `/tmp/codex-pet-usage-*.jpg`

**Interfaces:**
- Consumes: the immutable source plus the 1280×1080, 30 fps, H.264, `yuv420p`, CRF 22 rendering contract.
- Produces: a focused Pet demo pair referenced from both README language variants.

- [ ] **Step 1: Render three normalized Pet-demo segments**

Use these fixed source ranges and crops:

| Segment | Source range | Crop | Purpose |
|---|---:|---:|---|
| `pet-control` | `21.2–24.8s` | `1280:1080:1220:60` | Clearly show “Show Usage by Codex Pet” |
| `pet-follow` | `33.0–37.2s` | `960:810:2880:1200`, scaled to 1280×1080 | Show the 76% indicator following the Pet |
| `pet-summary` | `38.5–42.3s` | `960:810:2880:1200`, scaled to 1280×1080 | Click the indicator and show its summary |

Render the three segments:

```bash
ffmpeg -hide_banner -y \
  -i "/Users/benjaminz/Desktop/Screen Recording 2026-07-28 at 10.51.31.mov" \
  -vf "trim=start=21.2:end=24.8,setpts=PTS-STARTPTS,crop=1280:1080:1220:60,fps=30,format=yuv420p,setsar=1" \
  -an -c:v libx264 -preset slow -crf 22 -pix_fmt yuv420p \
  /tmp/codex-pet-usage-control.mp4

ffmpeg -hide_banner -y \
  -i "/Users/benjaminz/Desktop/Screen Recording 2026-07-28 at 10.51.31.mov" \
  -vf "trim=start=33.0:end=37.2,setpts=PTS-STARTPTS,crop=960:810:2880:1200,scale=1280:1080:flags=lanczos,fps=30,format=yuv420p,setsar=1" \
  -an -c:v libx264 -preset slow -crf 22 -pix_fmt yuv420p \
  /tmp/codex-pet-usage-follow.mp4

ffmpeg -hide_banner -y \
  -i "/Users/benjaminz/Desktop/Screen Recording 2026-07-28 at 10.51.31.mov" \
  -filter_complex "\
[0:v]trim=start=38.5:end=42.3,setpts=PTS-STARTPTS,\
crop=960:810:2880:1200,scale=1280:1080:flags=lanczos,\
fps=30,format=yuv420p,split=2[base][titlesrc];\
[titlesrc]crop=560:70:470:300,gblur=sigma=30:steps=6[titleblur];\
[base][titleblur]overlay=470:300:enable='between(t,1.1,3.8)',setsar=1[out]" \
  -map "[out]" -an -c:v libx264 -preset slow -crf 22 -pix_fmt yuv420p \
  /tmp/codex-pet-usage-summary.mp4
```

Expected total duration after concatenation: 11.6 seconds, allowing ±0.2
seconds.

- [ ] **Step 2: Concatenate and encode the Pet MP4**

Concatenate the three normalized streams:

```bash
ffmpeg -hide_banner -y \
  -i /tmp/codex-pet-usage-control.mp4 \
  -i /tmp/codex-pet-usage-follow.mp4 \
  -i /tmp/codex-pet-usage-summary.mp4 \
  -filter_complex "[0:v][1:v][2:v]concat=n=3:v=1:a=0,format=yuv420p[out]" \
  -map "[out]" \
  -an -c:v libx264 -preset slow -crf 22 -pix_fmt yuv420p \
  -movflags +faststart \
  docs/assets/codex-pet-usage-demo.mp4
```

- [ ] **Step 3: Generate the Pet GIF only from its sanitized MP4**

Run:

```bash
ffmpeg -hide_banner -y \
  -i docs/assets/codex-pet-usage-demo.mp4 \
  -filter_complex "\
[0:v]fps=10,scale=900:-2:flags=lanczos,split[gif_a][gif_b];\
[gif_a]palettegen=max_colors=96:stats_mode=diff[palette];\
[gif_b][palette]paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle[out]" \
  -map "[out]" \
  -loop 0 \
  docs/assets/codex-pet-usage-demo.gif
```

If the GIF exceeds 10 MiB, rerender with `fps=8`, `scale=800:-2`,
`max_colors=80`, and `bayer_scale=5`, then repeat verification.

- [ ] **Step 4: Verify and visually review the Pet assets**

Probe both outputs, fully decode both outputs, create a 1 fps contact sheet,
and extract frames 0.1 seconds before and after both concatenation boundaries.

Expected:

- MP4 is H.264, 1280×1080, 30 fps, `yuv420p`, silent, and 11.4–11.8 seconds.
- GIF duration matches within 0.2 seconds and size is at most 10 MiB.
- The control, Pet, 76% indicator, and summary metrics are legible.
- The real summary title and all unrelated desktop chrome are absent.

- [ ] **Step 5: Confirm the source checksum remains unchanged**

Run:

```bash
shasum -a 256 \
  "/Users/benjaminz/Desktop/Screen Recording 2026-07-28 at 10.51.31.mov"
```

Require:

```text
f89db78be6c78d22940b4249e19e56e26b77d18ad7030ddf5a62f54963fadba8
```

- [ ] **Step 6: Commit the Pet assets**

```bash
git add docs/assets/codex-pet-usage-demo.mp4 docs/assets/codex-pet-usage-demo.gif
git commit -m "docs: add the native Pet usage demo"
```

### Task 3: Add the Pet demo to both README files

**Files:**
- Modify: `README.md:34`
- Modify: `README.zh-CN.md:34`
- Read: `docs/assets/codex-pet-usage-demo.mp4`
- Read: `docs/assets/codex-pet-usage-demo.gif`

**Interfaces:**
- Consumes: the exact case-sensitive Pet asset paths from Task 2.
- Produces: matching English and Chinese Pet demo embeds while leaving the existing hero links unchanged.

- [ ] **Step 1: Add the English Pet media block**

Immediately after the introductory paragraph under `## Native Pet usage badge`,
add exactly:

```html
<p align="center">
  <a href="docs/assets/codex-pet-usage-demo.mp4">
    <img alt="Native Pet usage badge demo" src="docs/assets/codex-pet-usage-demo.gif">
  </a>
</p>

<p align="center">
  <a href="docs/assets/codex-pet-usage-demo.mp4">Watch the Native Pet usage badge demo in high-quality MP4</a>
</p>
```

- [ ] **Step 2: Add the Chinese Pet media block**

Immediately after the introductory paragraph under `## 原生 Pet 用量徽标`, add
exactly:

```html
<p align="center">
  <a href="docs/assets/codex-pet-usage-demo.mp4">
    <img alt="原生 Pet 用量徽标演示" src="docs/assets/codex-pet-usage-demo.gif">
  </a>
</p>

<p align="center">
  <a href="docs/assets/codex-pet-usage-demo.mp4">观看原生 Pet 用量徽标高清 MP4 视频</a>
</p>
```

- [ ] **Step 3: Validate paths, counts, and Markdown whitespace**

Run:

```bash
test -f docs/assets/codex-menubar-demo.mp4
test -f docs/assets/codex-menubar-demo.gif
test -f docs/assets/codex-pet-usage-demo.mp4
test -f docs/assets/codex-pet-usage-demo.gif

test "$(rg -c 'codex-pet-usage-demo\\.mp4' README.md)" -eq 2
test "$(rg -c 'codex-pet-usage-demo\\.gif' README.md)" -eq 1
test "$(rg -c 'codex-pet-usage-demo\\.mp4' README.zh-CN.md)" -eq 2
test "$(rg -c 'codex-pet-usage-demo\\.gif' README.zh-CN.md)" -eq 1

git diff --check
```

Expected: every command exits 0.

- [ ] **Step 4: Commit both README updates**

```bash
git add README.md README.zh-CN.md
git commit -m "docs: embed the native Pet usage demo"
```

### Task 4: Run complete branch verification and clean intermediates

**Files:**
- Verify: `README.md`
- Verify: `README.zh-CN.md`
- Verify: `docs/assets/codex-menubar-demo.mp4`
- Verify: `docs/assets/codex-menubar-demo.gif`
- Verify: `docs/assets/codex-pet-usage-demo.mp4`
- Verify: `docs/assets/codex-pet-usage-demo.gif`
- Verify: `docs/superpowers/specs/2026-07-28-readme-video-refresh-design.md`
- Verify: `docs/superpowers/plans/2026-07-28-readme-video-refresh.md`

**Interfaces:**
- Consumes: all prior outputs.
- Produces: fresh evidence that the branch is ready for pull-request review.

- [ ] **Step 1: Verify all media metadata in one report**

Probe all four files and require:

- both MP4 files are H.264, 1280×1080, 30 fps, `yuv420p`, silent, and contain
  fast-start metadata;
- both GIF files are animated, match the corresponding MP4 duration within 0.2
  seconds, and are at most 10 MiB;
- hero duration is 24.2–24.6 seconds;
- Pet duration is 11.4–11.8 seconds.

- [ ] **Step 2: Decode every final media file**

Run:

```bash
for media in \
  docs/assets/codex-menubar-demo.mp4 \
  docs/assets/codex-menubar-demo.gif \
  docs/assets/codex-pet-usage-demo.mp4 \
  docs/assets/codex-pet-usage-demo.gif
do
  ffmpeg -v error -i "$media" -f null - || exit 1
done
```

Expected: exit code 0 and no FFmpeg error output.

- [ ] **Step 3: Perform final visual privacy and continuity review**

Generate final contact sheets and boundary frames from both MP4s. Inspect them
at original detail and require:

- no readable real task/session names, project title, or local path;
- no Dock, menu bar, widgets, or Stage Manager thumbnails;
- no frame exposes content outside the approved crops;
- the UI, Pet, indicator, and summary are sharp and not clipped;
- every cut is intentional and understandable;
- GIF content is identical to the corresponding MP4 sequence.

- [ ] **Step 4: Run documentation and repository checks**

Run:

```bash
git diff main...HEAD --check
git status --short
swift test --package-path codex-menubar/macos/CodexMenuBar
```

Expected: no whitespace errors, only intended tracked changes, and the complete
Swift test suite passes.

- [ ] **Step 5: Remove temporary analysis and render files**

Delete only files matching these exact task-owned paths:

```text
/tmp/codex-menubar-v0311-contact-sheet.jpg
/tmp/codex-menubar-v0311-seconds.jpg
/tmp/codex-menubar-v0311-00-16.jpg
/tmp/codex-menubar-v0311-16-32.jpg
/tmp/codex-menubar-v0311-32-45.jpg
/tmp/codex-menubar-v0311-05.png
/tmp/codex-menubar-v0311-08.png
/tmp/codex-menubar-v0311-10.png
/tmp/codex-menubar-v0311-12.png
/tmp/codex-menubar-v0311-14.png
/tmp/codex-menubar-v0311-16.png
/tmp/codex-menubar-v0311-18.png
/tmp/codex-menubar-v0311-20.png
/tmp/codex-menubar-v0311-22.png
/tmp/codex-menubar-v0311-24.png
/tmp/codex-menubar-v0311-26.png
/tmp/codex-menubar-v0311-28.png
/tmp/codex-menubar-v0311-30.png
/tmp/codex-menubar-v0311-32.png
/tmp/codex-menubar-v0311-34.png
/tmp/codex-menubar-v0311-36.png
/tmp/codex-menubar-v0311-38.png
/tmp/codex-menubar-v0311-40.png
/tmp/codex-menubar-v0311-42.png
/tmp/codex-menubar-v0311-44.png
/tmp/codex-menubar-main-*.mp4
/tmp/codex-menubar-main-*.jpg
/tmp/codex-pet-usage-*.mp4
/tmp/codex-pet-usage-*.jpg
```

Do not delete or modify the original source recording.

- [ ] **Step 6: Confirm final branch state**

Run:

```bash
git status --short
git log --oneline --decorate main..HEAD
git diff --stat main...HEAD
```

Expected: clean worktree and only the design, plan, four media assets, and two
README files differ from `main`.
