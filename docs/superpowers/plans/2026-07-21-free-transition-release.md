# Free Transition Release Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publish an Apple Silicon, ad-hoc-signed `v0.2.0` GitHub Pre-release and add a direct binary download path to the README.

**Architecture:** Keep `build-app.sh` as the app-bundle builder and add a small release packager that validates the bundle, produces a fixed asset name, and writes a SHA-256 checksum. Merge documentation and tooling through a pull request, then build from merged `main`, create the exact `v0.2.0` Pre-release, upload both files, and verify the public download.

**Tech Stack:** Swift 6, Swift Package Manager, Bash, `ditto`, `codesign`, `plutil`, `shasum`, GitHub CLI.

## Global Constraints

- Release version is exactly `v0.2.0` and app version is exactly `0.2.0`.
- Release asset is Apple Silicon only and named `CodexMenuBar-v0.2.0-apple-silicon.zip`.
- The app remains ad-hoc signed and is not Apple-notarized.
- GitHub Release is marked as a Pre-release.
- README discloses architecture and Gatekeeper behavior before the download link.
- Runtime stays read-only; release work does not change app behavior.
- All tracked changes go through `release/free-transition-v0.2.0` and a pull request to `main`.

---

### Task 1: Reproducible Release Packager

**Files:**
- Create: `codex-menubar/macos/CodexMenuBar/scripts/package-release.sh`
- Reuse: `codex-menubar/macos/CodexMenuBar/scripts/build-app.sh`

**Interfaces:**
- Consumes: `build-app.sh`, which produces `dist/CodexMenuBar.app` with version `0.2.0`.
- Produces: `dist/CodexMenuBar-v0.2.0-apple-silicon.zip` and its `.sha256` checksum.

- [ ] **Step 1: Add the packaging script**

```bash
#!/usr/bin/env bash
set -euo pipefail

VERSION="0.2.0"
APP_NAME="CodexMenuBar"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DIST_DIR="$PACKAGE_DIR/dist"
APP_PATH="$DIST_DIR/$APP_NAME.app"
ASSET_NAME="$APP_NAME-v$VERSION-apple-silicon.zip"
ASSET_PATH="$DIST_DIR/$ASSET_NAME"

"$SCRIPT_DIR/build-app.sh"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")" = "$VERSION"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_PATH/Contents/Info.plist")" = "dev.benjamin.codex-menubar"
test "$(lipo -archs "$APP_PATH/Contents/MacOS/$APP_NAME")" = "arm64"
codesign --verify --deep --strict "$APP_PATH"

rm -f "$ASSET_PATH" "$ASSET_PATH.sha256"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ASSET_PATH"
(
    cd "$DIST_DIR"
    shasum -a 256 "$ASSET_NAME" > "$ASSET_NAME.sha256"
)

echo "$ASSET_PATH"
echo "$ASSET_PATH.sha256"
```

- [ ] **Step 2: Make the script executable and run it**

Run:

```bash
chmod +x codex-menubar/macos/CodexMenuBar/scripts/package-release.sh
codex-menubar/macos/CodexMenuBar/scripts/package-release.sh
```

Expected: exit code `0`; both release files are printed and exist under `dist/`.

- [ ] **Step 3: Inspect the archive and checksum**

Run:

```bash
unzip -t codex-menubar/macos/CodexMenuBar/dist/CodexMenuBar-v0.2.0-apple-silicon.zip
(cd codex-menubar/macos/CodexMenuBar/dist && shasum -a 256 -c CodexMenuBar-v0.2.0-apple-silicon.zip.sha256)
```

Expected: archive reports no errors and checksum reports `OK`.

- [ ] **Step 4: Commit the packager**

```bash
git add codex-menubar/macos/CodexMenuBar/scripts/package-release.sh
git commit -m "build: add Apple Silicon release packager"
```

### Task 2: README Download Experience

**Files:**
- Modify: `README.md`

**Interfaces:**
- Consumes: exact tag `v0.2.0` and asset name from Task 1.
- Produces: an exact-version download link and safe first-launch instructions.

- [ ] **Step 1: Replace the no-release copy with a download section**

```markdown
## Download — Apple Silicon preview

> [!WARNING]
> This free preview is built for Apple Silicon Macs, uses an ad-hoc signature, and is not Apple-notarized. macOS may block the first launch.

[Download Codex Menu Bar v0.2.0](https://github.com/benjaminazz1210/codex-menubar-tools/releases/download/v0.2.0/CodexMenuBar-v0.2.0-apple-silicon.zip)

Unzip the download, move `CodexMenuBar.app` to `Applications`, then right-click the app and choose **Open** for the first launch. If macOS still refuses to open it, build from source below instead of disabling system-wide security controls.

## Build from source
```

Keep the existing clone, build, open, development overrides, and test commands below the new heading.

- [ ] **Step 2: Verify documentation references**

Run:

```bash
rg -n "v0\.2\.0|apple-silicon|right-click|build-app\.sh|swift test" README.md
```

Expected: exact release URL, warning, first-launch instructions, source build, and test command all appear.

- [ ] **Step 3: Commit the README update and plan**

```bash
git add README.md docs/superpowers/plans/2026-07-21-free-transition-release.md
git commit -m "docs: add preview download instructions"
```

### Task 3: Verify, Merge, and Publish Pre-release

**Files:**
- Create temporarily, do not commit: `/tmp/codex-menubar-v0.2.0-release-notes.md`
- Upload: `codex-menubar/macos/CodexMenuBar/dist/CodexMenuBar-v0.2.0-apple-silicon.zip`
- Upload: `codex-menubar/macos/CodexMenuBar/dist/CodexMenuBar-v0.2.0-apple-silicon.zip.sha256`

**Interfaces:**
- Consumes: merged `main`, packaging script, README link, GitHub authentication.
- Produces: merged pull request and public GitHub Pre-release `v0.2.0` with verified assets.

- [ ] **Step 1: Run the full local verification matrix before PR creation**

```bash
swift test --package-path codex-menubar/macos/CodexMenuBar
codex-menubar/macos/CodexMenuBar/scripts/package-release.sh
unzip -t codex-menubar/macos/CodexMenuBar/dist/CodexMenuBar-v0.2.0-apple-silicon.zip
(cd codex-menubar/macos/CodexMenuBar/dist && shasum -a 256 -c CodexMenuBar-v0.2.0-apple-silicon.zip.sha256)
git diff --check
git status --short
```

Expected: 60 tests pass, all packaging checks exit `0`, and tracked changes are committed.

- [ ] **Step 2: Push, open, inspect, and merge the pull request**

```bash
git push -u origin release/free-transition-v0.2.0
gh pr create --base main --head release/free-transition-v0.2.0 --title "release: add v0.2.0 preview download" --body "Adds reproducible Apple Silicon preview packaging and a clearly disclosed direct README download."
gh pr view --json url,state,mergeable,mergeStateStatus,statusCheckRollup
gh pr merge --merge
```

Expected: the PR is mergeable, has no failing checks, and becomes `MERGED`.

- [ ] **Step 3: Rebuild from merged main and create the Pre-release**

Create `/tmp/codex-menubar-v0.2.0-release-notes.md` containing:

```markdown
## Codex Menu Bar v0.2.0 — Apple Silicon preview

This is a free, ad-hoc-signed preview for Apple Silicon Macs running macOS 14 or later.

- Unified usage, 30-week Token history, and live interactive TUI sessions
- Native AppKit + SwiftUI menu bar application
- Local-only, read-only runtime behavior

This build is not Apple-notarized. After unzipping, move the app to Applications, then right-click it and choose Open for the first launch. If macOS still blocks it, build from source instead of disabling system-wide security controls.
```

Run from updated `main`:

```bash
codex-menubar/macos/CodexMenuBar/scripts/package-release.sh
gh release create v0.2.0 \
  codex-menubar/macos/CodexMenuBar/dist/CodexMenuBar-v0.2.0-apple-silicon.zip \
  codex-menubar/macos/CodexMenuBar/dist/CodexMenuBar-v0.2.0-apple-silicon.zip.sha256 \
  --target main \
  --title "Codex Menu Bar v0.2.0 — Apple Silicon preview" \
  --notes-file /tmp/codex-menubar-v0.2.0-release-notes.md \
  --prerelease
```

Expected: GitHub returns the public release URL.

- [ ] **Step 4: Verify the published artifact**

```bash
gh release view v0.2.0 --json url,isPrerelease,tagName,targetCommitish,assets
curl -fL -o /tmp/CodexMenuBar-v0.2.0-apple-silicon.zip \
  https://github.com/benjaminazz1210/codex-menubar-tools/releases/download/v0.2.0/CodexMenuBar-v0.2.0-apple-silicon.zip
unzip -t /tmp/CodexMenuBar-v0.2.0-apple-silicon.zip
```

Expected: `isPrerelease` is `true`, both assets are listed, download succeeds, and archive validation reports no errors.

- [ ] **Step 5: Clean intermediates and branches after verification**

```bash
rm -rf codex-menubar/macos/CodexMenuBar/.build codex-menubar/macos/CodexMenuBar/dist
rm -f /tmp/CodexMenuBar-v0.2.0-apple-silicon.zip /tmp/codex-menubar-v0.2.0-release-notes.md
git push origin --delete release/free-transition-v0.2.0
git branch -d release/free-transition-v0.2.0
git status --short
```

Expected: intermediates and feature branches are absent and `main` is clean.
