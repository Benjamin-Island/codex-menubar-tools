# Codex Menu Bar

A native, local-only macOS menu bar dashboard for Codex usage, Token history, and live interactive CLI sessions.

One menu bar item shows the primary usage remaining and the number of live interactive sessions. Click it to open a SwiftUI dashboard with three pages:

- **Overview** — primary and secondary rate-limit windows, a compact Token heatmap, and live-session shortcuts.
- **History** — the latest 60 local days, daily Total/Input/Cached/Output/Reasoning details, and per-session breakdowns.
- **Sessions** — strictly detected top-level Codex terminal TUIs, with activity, working directory, last update, and cumulative Tokens.

## Pet Island

Pet Island keeps the same usage and live-session signal attached to the top
center of the active display. On a notched MacBook it visually joins the camera
notch; on a display without a notch it remains docked to the top edge instead of
floating over the desktop.

The island renders the user's local Codex custom pet in the same window as the
usage metrics, so the pet and status never need to be manually aligned. It
discovers read-only pet packages from:

- `~/.codex/pets/*/pet.json`
- `~/Library/Application Support/Codex/pets/*/pet.json`
- `~/Library/Application Support/ChatGPT/pets/*/pet.json`

Use **Pet Island** in the dashboard footer to show or hide the island and choose
an installed custom pet. The currently selected pet id and visibility setting
are stored in macOS user defaults; pet packages are never modified. If the Codex
app's own pet overlay is enabled, turn one of the two overlays off to avoid
showing the same pet twice.

No pet artwork is bundled, copied, or redistributed by Codex Menu Bar. Every
rendered frame is loaded at runtime from the local manifest's
`spritesheetPath`, and the sprite layout follows its `spriteVersionNumber`.

## Why

Codex already records useful local session data, but checking usage and understanding activity across days normally requires leaving the current workflow. Codex Menu Bar turns that local data into a small read-only dashboard without Electron, accounts, or a background service.

## Privacy and read-only behavior

The app:

- reads `~/.codex/sessions/**/*.jsonl` and `~/.codex/session_index.jsonl`;
- inspects current-user process metadata and writable rollout file associations to identify interactive TUIs;
- does **not** read Codex credentials or `auth.json`;
- does **not** make network requests;
- does **not** write a cache, database, analytics, or log file;
- does **not** start, stop, or otherwise control Codex sessions.

Session JSONL files are streamed in bounded chunks. While the app is running, appended bytes update pure-memory daily summaries; raw historical Token events are not retained. The index is never written to disk, so restarting the app performs a fresh streaming scan.

History includes every indexed local rollout source from the latest 60 local calendar days, while the live Sessions page intentionally includes only top-level interactive terminal TUIs. At most 10,000 ordinary logs are indexed, plus every log required by a currently running session.

## Token semantics

Codex records cumulative Token counters. The app converts consecutive cumulative values into increments, handles counter resets independently, and groups increments by system-local calendar day.

`Total` is used as reported. Cached input and Reasoning are shown as detail fields and are never added to Total again.

## Requirements

- macOS 14 or later
- Xcode 16 or Swift 6 command-line tools
- A local Codex installation with session data under `~/.codex`

Install Apple's command-line developer tools if needed:

```bash
xcode-select --install
```

## Download — Apple Silicon preview

> [!WARNING]
> This free preview is built for Apple Silicon Macs, uses an ad-hoc signature, and is not Apple-notarized. macOS may block the first launch.

[Download Codex Menu Bar v0.3.2](https://github.com/Benjamin-Island/codex-menubar-tools/releases/download/v0.3.2/CodexMenuBar-v0.3.2-apple-silicon.zip)

[SHA-256 checksum](https://github.com/Benjamin-Island/codex-menubar-tools/releases/download/v0.3.2/CodexMenuBar-v0.3.2-apple-silicon.zip.sha256)

Unzip the download, move `CodexMenuBar.app` to `Applications`, then right-click the app and choose **Open** for the first launch. If macOS still refuses to open it, build from source below instead of disabling system-wide security controls.

## Build from source

Clone the repository, build the app locally, and open it:

```bash
git clone https://github.com/Benjamin-Island/codex-menubar-tools.git
cd codex-menubar-tools
codex-menubar/macos/CodexMenuBar/scripts/build-app.sh
open codex-menubar/macos/CodexMenuBar/dist/CodexMenuBar.app
```

The app runs only in the menu bar and has no Dock icon. The first scan may take a little longer for large Codex histories; later refreshes validate the saved file boundary and read only appended bytes whenever possible.

Optional path overrides are available for development:

```bash
CODEX_SESSIONS_DIR=/path/to/sessions \
CODEX_SESSION_INDEX=/path/to/session_index.jsonl \
codex-menubar/macos/CodexMenuBar/dist/CodexMenuBar.app/Contents/MacOS/CodexMenuBar
```

## Test

From the repository root:

```bash
swift test --package-path codex-menubar/macos/CodexMenuBar
```

The suite includes parser, aggregation, rate-limit, process-classification, routing, SwiftUI layout, and read-only live smoke coverage.

## Demo video

See Codex Menu Bar move through usage limits, the 60-day Token history, daily details, and live interactive sessions.

[![Codex Menu Bar demo](docs/assets/codex-menubar-demo.gif)](docs/assets/codex-menubar-demo.mp4)

[Watch the high-quality MP4](docs/assets/codex-menubar-demo.mp4)

## Notes

- This is an independent project, not an official OpenAI application.
- Usage data comes from local Codex session events, not an official Usage API.
- The locally built app is ad-hoc signed and not notarized. If macOS blocks the first launch, right-click the app and choose **Open**.
