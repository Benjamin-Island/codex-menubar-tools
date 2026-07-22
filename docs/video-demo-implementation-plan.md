# README Demo Video Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a privacy-safe animated README preview that links to a compact high-quality MP4 demo of Codex Menu Bar.

**Architecture:** Process the existing screen recording into one cropped MP4 with time-bounded privacy masks, then derive a palette-optimized GIF from that sanitized MP4. Store both media files under `docs/assets/` and replace the README placeholder with a clickable preview and direct MP4 link.

**Tech Stack:** FFmpeg/ffprobe, H.264, GIF palette generation, Markdown, Swift Package Manager, GitHub CLI.

## Global Constraints

- Keep only the application window; remove the desktop and macOS menu bar.
- Preserve the visible Overview, History, Sessions, and final Overview interaction flow.
- No session title or local filesystem path may be readable on any page.
- Keep Token totals and non-personal interface labels visible where the privacy mask does not overlap them.
- MP4 output uses H.264, 30 FPS, and a maximum width of 1280 pixels.
- GIF output is approximately 900 pixels wide and 10–12 FPS.
- Do not create or commit `docs/superpowers`.
- Work only on `docs/add-readme-demo-video`, merge through a pull request, and delete the feature branch and temporary processing files afterward.

---

### Task 1: Produce the sanitized MP4

**Files:**
- Create: `docs/assets/codex-menubar-demo.mp4`
- Source: `~/Desktop/Screen Recording 2026-07-22 at 07.42.14.mov`
- Temporary: `/tmp/codex-menubar-demo-*.png`

**Interfaces:**
- Consumes: the original H.264 screen recording.
- Produces: a privacy-safe H.264 MP4 used as the source for Task 2 and the high-quality README link in Task 3.

- [ ] **Step 1: Recheck the source before rendering**

Run:

```bash
ffprobe -v error \
  -show_entries format=duration,size:stream=codec_name,codec_type,width,height,r_frame_rate,pix_fmt \
  -of json \
  "$HOME/Desktop/Screen Recording 2026-07-22 at 07.42.14.mov"
```

Expected: one H.264 video stream, 1706 × 1186, no audio stream, and approximately 22.95 seconds duration.

- [ ] **Step 2: Render the cropped and privacy-masked MP4**

Create the destination directory:

```bash
mkdir -p docs/assets
```

Render two source segments. The gap from 19.05 to 19.67 seconds removes the brief unintended History flash before the final Overview. Coordinates are relative to the 1252 × 1068 crop at source position 300,54.

```bash
ffmpeg -hide_banner -y \
  -i "$HOME/Desktop/Screen Recording 2026-07-22 at 07.42.14.mov" \
  -filter_complex "\
[0:v]split=2[src_a][src_b];\
[src_a]trim=start=1.55:end=19.05,setpts=PTS-STARTPTS,crop=1252:1068:300:54,fps=30,\
delogo=x=90:y=910:w=760:h=74:enable='between(t,0,5.05)',\
delogo=x=90:y=685:w=1070:h=315:enable='between(t,6.45,8.95)',\
delogo=x=90:y=270:w=430:h=360:enable='between(t,15.45,17.50)',\
delogo=x=640:y=250:w=575:h=125:enable='between(t,15.45,17.50)',\
delogo=x=640:y=615:w=465:h=70:enable='between(t,15.45,17.50)'[a];\
[src_b]trim=start=19.67:end=22.70,setpts=PTS-STARTPTS,crop=1252:1068:300:54,fps=30,\
delogo=x=90:y=675:w=1070:h=280[b];\
[a][b]concat=n=2:v=1:a=0,format=yuv420p[out]" \
  -map "[out]" \
  -an \
  -c:v libx264 \
  -preset slow \
  -crf 22 \
  -movflags +faststart \
  docs/assets/codex-menubar-demo.mp4
```

Expected: exit code 0 and a playable MP4 of approximately 20.53 seconds.

- [ ] **Step 3: Verify media properties and privacy**

Run:

```bash
ffprobe -v error \
  -show_entries format=duration,size:stream=codec_name,width,height,r_frame_rate,pix_fmt \
  -of json \
  docs/assets/codex-menubar-demo.mp4

ffmpeg -hide_banner -loglevel error \
  -i docs/assets/codex-menubar-demo.mp4 \
  -vf "fps=1,scale=360:-1,tile=5x5" \
  -frames:v 1 \
  /tmp/codex-menubar-demo-sanitized-contact-sheet.jpg
```

Expected:

- codec `h264`;
- dimensions `1252x1068`;
- frame rate `30/1`;
- pixel format `yuv420p`;
- duration between 20.4 and 20.7 seconds;
- file size below 8 MiB;
- the contact sheet shows no readable session title or local filesystem path;
- the crop includes the complete popover and excludes the desktop and macOS menu bar.

- [ ] **Step 4: Commit the sanitized MP4**

```bash
git add docs/assets/codex-menubar-demo.mp4
git commit -m "docs: add sanitized menu bar demo video"
```

### Task 2: Produce the inline animated GIF

**Files:**
- Create: `docs/assets/codex-menubar-demo.gif`
- Consume: `docs/assets/codex-menubar-demo.mp4`

**Interfaces:**
- Consumes: the sanitized MP4 from Task 1 so privacy masking cannot diverge between formats.
- Produces: the inline animated preview referenced by Task 3.

- [ ] **Step 1: Render a palette-optimized GIF**

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

Expected: exit code 0 and an animated GIF with the same visible sequence as the MP4.

- [ ] **Step 2: Verify the GIF**

```bash
ffprobe -v error \
  -show_entries format=duration,size:stream=codec_name,width,height,r_frame_rate \
  -of json \
  docs/assets/codex-menubar-demo.gif

du -h docs/assets/codex-menubar-demo.gif
```

Expected:

- codec `gif`;
- width `900`;
- frame rate `10/1`;
- duration within 0.2 seconds of the MP4;
- file size at or below 10 MiB.

If the GIF exceeds 10 MiB, rerender it with the exact fallback settings below and repeat the checks:

```bash
ffmpeg -hide_banner -y \
  -i docs/assets/codex-menubar-demo.mp4 \
  -filter_complex "\
[0:v]fps=8,scale=800:-2:flags=lanczos,split[gif_a][gif_b];\
[gif_a]palettegen=max_colors=80:stats_mode=diff[palette];\
[gif_b][palette]paletteuse=dither=bayer:bayer_scale=5:diff_mode=rectangle[out]" \
  -map "[out]" \
  -loop 0 \
  docs/assets/codex-menubar-demo.gif
```

- [ ] **Step 3: Commit the GIF**

```bash
git add docs/assets/codex-menubar-demo.gif
git commit -m "docs: add animated README demo"
```

### Task 3: Replace the README demo placeholder

**Files:**
- Modify: `README.md`
- Consume: `docs/assets/codex-menubar-demo.gif`
- Consume: `docs/assets/codex-menubar-demo.mp4`

**Interfaces:**
- Consumes: exact case-sensitive media paths from Tasks 1 and 2.
- Produces: an inline preview and accessible direct link in the public README.

- [ ] **Step 1: Replace the existing Demo video section**

Replace the current placeholder paragraph under `## Demo video` with exactly:

```markdown
See Codex Menu Bar move through usage limits, the 60-day Token history, daily details, and live interactive sessions.

[![Codex Menu Bar demo](docs/assets/codex-menubar-demo.gif)](docs/assets/codex-menubar-demo.mp4)

[Watch the high-quality MP4](docs/assets/codex-menubar-demo.mp4)
```

- [ ] **Step 2: Verify the README paths and diff**

```bash
test -f docs/assets/codex-menubar-demo.gif
test -f docs/assets/codex-menubar-demo.mp4
rg -n "codex-menubar-demo\\.(gif|mp4)" README.md
git diff --check
git diff -- README.md
```

Expected: both files exist, README contains one GIF reference and two MP4 references, and `git diff --check` exits 0.

- [ ] **Step 3: Commit the README**

```bash
git add README.md
git commit -m "docs: embed the Codex Menu Bar demo"
```

### Task 4: Run complete verification

**Files:**
- Verify: `README.md`
- Verify: `docs/assets/codex-menubar-demo.mp4`
- Verify: `docs/assets/codex-menubar-demo.gif`
- Verify: `docs/video-demo-design.md`
- Verify: `docs/video-demo-implementation-plan.md`

**Interfaces:**
- Consumes: all prior task outputs.
- Produces: fresh evidence that the branch is ready for review.

- [ ] **Step 1: Run the full Swift test suite**

```bash
swift test --package-path codex-menubar/macos/CodexMenuBar
```

Expected: all tests pass with zero failures.

- [ ] **Step 2: Revalidate both media files**

```bash
ffprobe -v error -show_entries format=duration,size:stream=codec_name,width,height,r_frame_rate,pix_fmt -of json docs/assets/codex-menubar-demo.mp4
ffprobe -v error -show_entries format=duration,size:stream=codec_name,width,height,r_frame_rate -of json docs/assets/codex-menubar-demo.gif
shasum -a 256 docs/assets/codex-menubar-demo.mp4 docs/assets/codex-menubar-demo.gif
```

Expected: MP4 and GIF properties still match Tasks 1 and 2, and both SHA-256 values are printed.

- [ ] **Step 3: Audit the branch**

```bash
git diff --check main...HEAD
git status --short --branch
git ls-files docs/superpowers
git log --oneline main..HEAD
```

Expected:

- no whitespace errors;
- only intended commits are ahead of `main`;
- `git ls-files docs/superpowers` prints nothing;
- no build directory, rendered contact sheet, or other temporary file is tracked.

### Task 5: Publish through a pull request and clean up

**Files:**
- No new files.

**Interfaces:**
- Consumes: the verified feature branch.
- Produces: a merged `main`, deleted feature branch, and clean local workspace.

- [ ] **Step 1: Push and open the pull request**

```bash
git push -u origin docs/add-readme-demo-video
gh pr create \
  --base main \
  --head docs/add-readme-demo-video \
  --title "docs: add README demo video" \
  --body "Adds a cropped and privacy-sanitized demo MP4, an inline animated GIF preview, and README links. Full Swift tests and media validation completed."
```

Expected: GitHub returns a pull-request URL.

- [ ] **Step 2: Confirm the pull request diff and merge**

```bash
gh pr diff --name-only
gh pr view --json files,commits,mergeStateStatus,state,url
gh pr checks
gh pr merge --merge
```

Expected: required checks pass and the pull request reaches `MERGED`.

- [ ] **Step 3: Return to main and remove temporary files**

```bash
git switch main
git pull --ff-only origin main
git push origin --delete docs/add-readme-demo-video
git branch -d docs/add-readme-demo-video
rm -f /tmp/codex-menubar-demo-contact-sheet.jpg
rm -f /tmp/codex-menubar-demo-seconds.jpg
rm -f /tmp/codex-menubar-demo-sessions.png
rm -f /tmp/codex-menubar-demo-overview-start.png
rm -f /tmp/codex-menubar-demo-overview-end.png
rm -f /tmp/codex-menubar-demo-history.png
rm -f /tmp/codex-menubar-demo-sanitized-contact-sheet.jpg
rm -rf codex-menubar/macos/CodexMenuBar/.build
```

Expected: the exact feature branch and temporary analysis/build artifacts are absent.

- [ ] **Step 4: Final repository audit**

```bash
git status --short --branch
git rev-parse HEAD
git rev-parse origin/main
git branch --list docs/add-readme-demo-video
git ls-remote --heads origin docs/add-readme-demo-video
```

Expected: clean `main`, matching local and remote commit IDs, and no local or remote feature branch.
