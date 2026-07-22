# README Demo Video Design

## Goal

Add a polished public demo of Codex Menu Bar to the README while protecting personal information visible in the source recording.

## Source

- Input: `~/Desktop/Screen Recording 2026-07-22 at 07.42.14.mov`
- Duration: approximately 23 seconds
- Source format: H.264, 1706 × 1186, 60 FPS, no audio

## Presentation

The demo keeps the existing interaction sequence:

1. Overview
2. History
3. Sessions
4. Overview

The published frame contains only the application window. The macOS desktop and menu bar are cropped out. Idle frames at the beginning and end are removed.

## Privacy

The following source content must not be readable in either output wherever it appears in Overview, History, or Sessions:

- session titles, including the three Chinese live-session titles and History breakdown titles;
- local filesystem paths, including paths under `~/Downloads`.

These regions are obscured whenever they are visible. Token totals and non-personal interface labels remain visible.

## Outputs

- `docs/assets/codex-menubar-demo.mp4`
  - H.264;
  - 30 FPS;
  - maximum width of 1280 pixels;
  - optimized for a compact, high-quality downloadable demo.
- `docs/assets/codex-menubar-demo.gif`
  - approximately 900 pixels wide;
  - 10–12 FPS;
  - palette-optimized for an inline README preview.

The GIF is embedded in the README and links to the MP4. A separate text link to the MP4 is included for accessibility and discoverability.

## README Change

Replace the placeholder text in the existing `Demo video` section with:

- a short description;
- the clickable animated preview;
- a direct high-quality MP4 link.

## Verification

Before committing the implementation:

1. Inspect frames from the beginning, History page, Sessions page, and end.
2. Confirm the private titles and local path cannot be read.
3. Validate both files with `ffprobe`.
4. Confirm expected codecs, dimensions, frame rates, duration, and file sizes.
5. Check that README relative paths resolve with exact filename casing.
6. Run the full Swift test suite.
7. Review the Git diff and ensure no build or temporary files are tracked.

## Git Workflow

Implementation remains on `docs/add-readme-demo-video`, is pushed through a pull request, and is merged into `main`. The feature branch and temporary processing files are removed after verification.
