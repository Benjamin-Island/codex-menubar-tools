# Bilingual README Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reorganize the English README into a product-first layout and add a structurally synchronized, naturally localized Simplified Chinese README.

**Architecture:** `README.md` remains the canonical English entry point and `README.zh-CN.md` mirrors its hierarchy, commands, links, warnings, and media. Both files share a centered product header, language navigation, informational badges, demo placement, and the same nine-section reading flow.

**Tech Stack:** GitHub Flavored Markdown, small HTML alignment blocks supported by GitHub, Shields.io informational badges, Swift Package Manager test suite.

## Global Constraints

- Work only on the existing `docs/readme-bilingual-redesign` feature branch.
- Keep `README.md` as the English default and create `README.zh-CN.md` for Simplified Chinese.
- Preserve macOS 14+, Xcode 16 or Swift 6, Apple Silicon preview v0.3.2, all existing release URLs, commands, paths, warnings, and documented behavior.
- Keep both language editions synchronized in heading hierarchy, section order, code blocks, links, warnings, and media.
- Keep `Codex`, `Codex Menu Bar`, `Token`, `SwiftUI`, `TUI`, and `JSONL` in their established forms.
- Do not add application features, platform claims, dependencies, a license, a contribution guide, a roadmap, or repository policy.
- Deliver through a Pull Request to `main`; do not push changes directly to `main`.

---

## File structure

- Modify `README.md`: canonical English product and technical documentation.
- Create `README.zh-CN.md`: Simplified Chinese localization with the same structure and technical content.
- Do not modify application source, tests, release artifacts, demo assets, or the approved design document.

### Task 1: Reorganize and polish the English README

**Files:**
- Modify: `README.md`
- Reference: `docs/superpowers/specs/2026-07-23-readme-bilingual-redesign-design.md`

**Interfaces:**
- Consumes: the current README facts, commands, URLs, and media assets.
- Produces: the canonical eight-H2 English structure that Task 2 mirrors.

- [ ] **Step 1: Confirm the branch and establish the content baseline**

Run:

```bash
git branch --show-current
rg -F 'v0.3.2' README.md
rg -F 'does **not** make network requests' README.md
rg -F 'swift test --package-path codex-menubar/macos/CodexMenuBar' README.md
```

Expected:

```text
docs/readme-bilingual-redesign
```

The three searches must each print one matching line. Stop if any search fails,
because the source facts no longer match the approved design.

- [ ] **Step 2: Replace `README.md` with the approved English content**

Use this complete content:

````markdown
<p align="right">
  <strong>English</strong> |
  <a href="README.zh-CN.md">简体中文</a>
</p>

<div align="center">
  <h1>Codex Menu Bar</h1>
  <p>A native, local-only macOS menu bar dashboard for Codex usage, Token history, and live interactive CLI sessions.</p>
  <p>
    <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-000000?logo=apple">
    <img alt="Swift 6" src="https://img.shields.io/badge/Swift-6-F05138?logo=swift&amp;logoColor=white">
    <img alt="Local-only data" src="https://img.shields.io/badge/data-local--only-2ea44f">
    <img alt="Read-only access" src="https://img.shields.io/badge/access-read--only-0969da">
  </p>
</div>

<p align="center">
  <a href="docs/assets/codex-menubar-demo.mp4">
    <img alt="Codex Menu Bar demo" src="docs/assets/codex-menubar-demo.gif">
  </a>
</p>

<p align="center">
  <a href="docs/assets/codex-menubar-demo.mp4">Watch the high-quality MP4</a>
</p>

## Features

- **Overview** — see primary and secondary rate-limit windows, a compact Token heatmap, and shortcuts to live sessions.
- **History** — explore the latest 60 local days with daily Total, Input, Cached, Output, and Reasoning details plus per-session breakdowns.
- **Sessions** — find strictly detected top-level Codex terminal TUIs, including activity, working directory, last update, and cumulative Tokens.
- **Private by design** — inspect local Codex data without accounts, network requests, analytics, or a background service.

## Why Codex Menu Bar

Codex already records useful local session data, but checking usage and understanding activity across days usually means leaving your current workflow. Codex Menu Bar turns that data into a small, read-only SwiftUI dashboard available directly from the macOS menu bar.

The menu bar item shows the primary usage remaining and the number of live interactive sessions. Click it to open the Overview, History, and Sessions pages.

## Privacy and read-only design

The app:

- reads `~/.codex/sessions/**/*.jsonl` and `~/.codex/session_index.jsonl`;
- inspects current-user process metadata and writable rollout file associations to identify interactive TUIs;
- does **not** read Codex credentials or `auth.json`;
- does **not** make network requests;
- does **not** write a cache, database, analytics, or log file;
- does **not** start, stop, or otherwise control Codex sessions.

Session JSONL files are streamed in bounded chunks. While the app is running, appended bytes update in-memory daily summaries; raw historical Token events are not retained. The index is never written to disk, so restarting the app performs a fresh streaming scan.

History includes every indexed local rollout source from the latest 60 local calendar days. The live Sessions page intentionally includes only top-level interactive terminal TUIs. At most 10,000 ordinary logs are indexed, plus every log required by a currently running session.

## Requirements

- macOS 14 or later
- Xcode 16 or Swift 6 command-line tools
- A local Codex installation with session data under `~/.codex`

Install Apple's command-line developer tools if needed:

```bash
xcode-select --install
```

## Quick start

### Download the Apple Silicon preview

> [!WARNING]
> This free preview is built for Apple Silicon Macs, uses an ad-hoc signature, and is not Apple-notarized. macOS may block the first launch.

- [Download Codex Menu Bar v0.3.2](https://github.com/Benjamin-Island/codex-menubar-tools/releases/download/v0.3.2/CodexMenuBar-v0.3.2-apple-silicon.zip)
- [SHA-256 checksum](https://github.com/Benjamin-Island/codex-menubar-tools/releases/download/v0.3.2/CodexMenuBar-v0.3.2-apple-silicon.zip.sha256)

Unzip the download, move `CodexMenuBar.app` to `Applications`, then right-click the app and choose **Open** for the first launch. If macOS still refuses to open it, build from source instead of disabling system-wide security controls.

### Build from source

Clone the repository, build the app locally, and open it:

```bash
git clone https://github.com/Benjamin-Island/codex-menubar-tools.git
cd codex-menubar-tools
codex-menubar/macos/CodexMenuBar/scripts/build-app.sh
open codex-menubar/macos/CodexMenuBar/dist/CodexMenuBar.app
```

The app runs only in the menu bar and has no Dock icon. The first scan may take a little longer for large Codex histories; later refreshes validate the recorded file boundary and read only appended bytes whenever possible.

Optional path overrides are available for development:

```bash
CODEX_SESSIONS_DIR=/path/to/sessions \
CODEX_SESSION_INDEX=/path/to/session_index.jsonl \
codex-menubar/macos/CodexMenuBar/dist/CodexMenuBar.app/Contents/MacOS/CodexMenuBar
```

## Data and Token semantics

Codex records cumulative Token counters. The app converts consecutive cumulative values into increments, handles counter resets independently, and groups increments by the system's local calendar day.

`Total` is used as reported. Cached input and Reasoning are detail fields and are never added to Total again.

## Test

From the repository root:

```bash
swift test --package-path codex-menubar/macos/CodexMenuBar
```

The suite covers parser, aggregation, rate-limit, process-classification, routing, SwiftUI layout, and read-only live smoke behavior.

## Notes

- This is an independent project, not an official OpenAI application.
- Usage data comes from local Codex session events, not an official Usage API.
- Locally built copies are ad-hoc signed and not notarized. If macOS blocks the first launch, right-click the app and choose **Open**.
````

- [ ] **Step 3: Validate the English structure and retained facts**

Run:

```bash
test "$(rg -c '^## ' README.md)" -eq 8
test "$(rg -c '^### ' README.md)" -eq 2
test "$(rg -c '^```' README.md)" -eq 8
rg -F 'README.zh-CN.md' README.md
rg -F 'CodexMenuBar-v0.3.2-apple-silicon.zip' README.md
rg -F 'does **not** make network requests' README.md
git diff --check -- README.md
```

Expected: all commands exit 0; the three searches print matches; the final
whitespace check prints nothing.

- [ ] **Step 4: Commit the English redesign**

Run:

```bash
git add README.md
git commit -m "docs: reorganize English README"
```

Expected: one commit that changes only `README.md`.

### Task 2: Add the synchronized Simplified Chinese README

**Files:**
- Create: `README.zh-CN.md`
- Reference: `README.md`

**Interfaces:**
- Consumes: Task 1's eight-H2 English structure and exact technical values.
- Produces: a natural Chinese localization with identical commands, URLs, warning count, and media references.

- [ ] **Step 1: Create `README.zh-CN.md` with the approved Chinese content**

Use this complete content:

````markdown
<p align="right">
  <a href="README.md">English</a> |
  <strong>简体中文</strong>
</p>

<div align="center">
  <h1>Codex Menu Bar</h1>
  <p>原生、仅本地运行的 macOS 菜单栏仪表盘，用于查看 Codex 用量、Token 历史记录和实时交互式 CLI 会话。</p>
  <p>
    <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-000000?logo=apple">
    <img alt="Swift 6" src="https://img.shields.io/badge/Swift-6-F05138?logo=swift&amp;logoColor=white">
    <img alt="数据仅保存在本地" src="https://img.shields.io/badge/data-local--only-2ea44f">
    <img alt="只读访问" src="https://img.shields.io/badge/access-read--only-0969da">
  </p>
</div>

<p align="center">
  <a href="docs/assets/codex-menubar-demo.mp4">
    <img alt="Codex Menu Bar 演示" src="docs/assets/codex-menubar-demo.gif">
  </a>
</p>

<p align="center">
  <a href="docs/assets/codex-menubar-demo.mp4">观看高清 MP4 视频</a>
</p>

## 核心功能

- **概览** — 查看主要和次要速率限制周期、紧凑的 Token 热力图，以及实时会话快捷入口。
- **历史记录** — 浏览最近 60 个本地自然日的数据，包括每天的 Total、Input、Cached、Output、Reasoning 明细和各会话分项。
- **会话** — 严格识别顶层 Codex 终端 TUI，并显示活动状态、工作目录、最后更新时间和累计 Token。
- **隐私优先** — 无需账户、网络请求、分析服务或后台服务，即可查看本地 Codex 数据。

## 为什么使用 Codex Menu Bar

Codex 已经记录了实用的本地会话数据，但检查用量或了解多日活动通常需要离开当前工作流。Codex Menu Bar 将这些数据整理成小巧的只读 SwiftUI 仪表盘，可直接从 macOS 菜单栏打开。

菜单栏图标会显示主要用量的剩余额度和实时交互会话数量。点击图标即可打开“概览”“历史记录”和“会话”页面。

## 隐私与只读设计

本应用：

- 读取 `~/.codex/sessions/**/*.jsonl` 和 `~/.codex/session_index.jsonl`；
- 检查当前用户的进程元数据，以及可写 rollout 文件的关联信息，以识别交互式 TUI；
- **不会**读取 Codex 凭据或 `auth.json`；
- **不会**发起网络请求；
- **不会**写入缓存、数据库、分析数据或日志文件；
- **不会**启动、停止或以其他方式控制 Codex 会话。

应用以有界数据块流式读取会话 JSONL 文件。运行期间，新增字节只会更新内存中的每日汇总；原始历史 Token 事件不会保留。索引不会写入磁盘，因此每次重启都会重新进行流式扫描。

“历史记录”包含最近 60 个本地自然日内所有已建立索引的本地 rollout 来源。“会话”页面则只显示顶层交互式终端 TUI。应用最多索引 10,000 个普通日志，并额外包含当前运行会话所需的全部日志。

## 系统要求

- macOS 14 或更高版本
- Xcode 16 或 Swift 6 命令行工具
- 已在 `~/.codex` 下生成会话数据的本地 Codex 安装

如有需要，请安装 Apple 命令行开发工具：

```bash
xcode-select --install
```

## 快速开始

### 下载 Apple Silicon 预览版

> [!WARNING]
> 此免费预览版面向 Apple Silicon Mac，使用临时签名且未经 Apple 公证。macOS 可能会阻止首次启动。

- [下载 Codex Menu Bar v0.3.2](https://github.com/Benjamin-Island/codex-menubar-tools/releases/download/v0.3.2/CodexMenuBar-v0.3.2-apple-silicon.zip)
- [SHA-256 校验值](https://github.com/Benjamin-Island/codex-menubar-tools/releases/download/v0.3.2/CodexMenuBar-v0.3.2-apple-silicon.zip.sha256)

解压下载文件，将 `CodexMenuBar.app` 移到 `Applications`，然后右键点击应用并选择“打开”完成首次启动。如果 macOS 仍然拒绝打开，请改为从源码构建，不要关闭系统级安全防护。

### 从源码构建

克隆仓库，在本地构建并打开应用：

```bash
git clone https://github.com/Benjamin-Island/codex-menubar-tools.git
cd codex-menubar-tools
codex-menubar/macos/CodexMenuBar/scripts/build-app.sh
open codex-menubar/macos/CodexMenuBar/dist/CodexMenuBar.app
```

应用仅在菜单栏中运行，不显示 Dock 图标。如果 Codex 历史记录较多，首次扫描可能需要更长时间；后续刷新会验证已记录的文件边界，并尽可能只读取新增字节。

开发时可以通过以下环境变量覆盖默认路径：

```bash
CODEX_SESSIONS_DIR=/path/to/sessions \
CODEX_SESSION_INDEX=/path/to/session_index.jsonl \
codex-menubar/macos/CodexMenuBar/dist/CodexMenuBar.app/Contents/MacOS/CodexMenuBar
```

## 数据与 Token 统计规则

Codex 记录的是累计 Token 计数器。应用会把相邻累计值转换为增量，分别处理计数器重置，并按系统本地自然日归组。

`Total` 直接采用记录值。Cached input 和 Reasoning 仅作为明细字段展示，不会再次计入 Total。

## 测试

在仓库根目录运行：

```bash
swift test --package-path codex-menubar/macos/CodexMenuBar
```

测试套件覆盖解析、聚合、速率限制、进程分类、路由、SwiftUI 布局和只读实时冒烟行为。

## 项目说明

- 本项目为独立项目，并非 OpenAI 官方应用。
- 用量数据来自本地 Codex 会话事件，而非官方 Usage API。
- 本地构建版本使用临时签名且未经公证。如果 macOS 阻止首次启动，请右键点击应用并选择“打开”。
````

- [ ] **Step 2: Validate the Chinese structure and retained facts**

Run:

```bash
test "$(rg -c '^## ' README.zh-CN.md)" -eq 8
test "$(rg -c '^### ' README.zh-CN.md)" -eq 2
test "$(rg -c '^```' README.zh-CN.md)" -eq 8
rg -F 'README.md' README.zh-CN.md
rg -F 'CodexMenuBar-v0.3.2-apple-silicon.zip' README.zh-CN.md
rg -F 'swift test --package-path codex-menubar/macos/CodexMenuBar' README.zh-CN.md
git diff --check -- README.zh-CN.md
```

Expected: all commands exit 0; the three searches print matches; the final
whitespace check prints nothing.

- [ ] **Step 3: Commit the Chinese edition**

Run:

```bash
git add README.zh-CN.md
git commit -m "docs: add Simplified Chinese README"
```

Expected: one commit that creates only `README.zh-CN.md`.

### Task 3: Verify bilingual parity and the project test suite

**Files:**
- Verify: `README.md`
- Verify: `README.zh-CN.md`
- Verify: `docs/assets/codex-menubar-demo.gif`
- Verify: `docs/assets/codex-menubar-demo.mp4`

**Interfaces:**
- Consumes: the completed English and Chinese README files.
- Produces: evidence that both editions are structurally synchronized and that the application test suite still passes.

- [ ] **Step 1: Expand and run the README validation matrix**

Run:

```bash
test -f docs/assets/codex-menubar-demo.gif
test -f docs/assets/codex-menubar-demo.mp4
test "$(rg -c '^## ' README.md)" -eq "$(rg -c '^## ' README.zh-CN.md)"
test "$(rg -c '^### ' README.md)" -eq "$(rg -c '^### ' README.zh-CN.md)"
test "$(rg -c '^```' README.md)" -eq "$(rg -c '^```' README.zh-CN.md)"
test "$(rg -c '\\[!WARNING\\]' README.md)" -eq "$(rg -c '\\[!WARNING\\]' README.zh-CN.md)"
test "$(rg -c 'docs/assets/codex-menubar-demo.gif' README.md)" -eq 1
test "$(rg -c 'docs/assets/codex-menubar-demo.gif' README.zh-CN.md)" -eq 1
test "$(rg -c 'docs/assets/codex-menubar-demo.mp4' README.md)" -eq 2
test "$(rg -c 'docs/assets/codex-menubar-demo.mp4' README.zh-CN.md)" -eq 2
test "$(rg -c 'releases/download/v0.3.2' README.md)" -eq 2
test "$(rg -c 'releases/download/v0.3.2' README.zh-CN.md)" -eq 2
test "$(rg -c 'xcode-select --install' README.md)" -eq 1
test "$(rg -c 'xcode-select --install' README.zh-CN.md)" -eq 1
test "$(rg -c 'swift test --package-path' README.md)" -eq 1
test "$(rg -c 'swift test --package-path' README.zh-CN.md)" -eq 1
git diff --check
```

Expected: every command exits 0 and `git diff --check` prints nothing.

- [ ] **Step 2: Run the full Swift test suite**

Run:

```bash
swift test --package-path codex-menubar/macos/CodexMenuBar
```

Expected: exit 0 with all tests passing and no test failures.

- [ ] **Step 3: Inspect the final branch diff**

Run:

```bash
git status --short --branch
git diff main...HEAD --stat
git diff main...HEAD -- README.md README.zh-CN.md
```

Expected:

- The branch is `docs/readme-bilingual-redesign`.
- The worktree is clean.
- The branch diff contains the design document, English README, Chinese README,
  and this implementation plan only.
- No application source or test file is changed.

- [ ] **Step 4: Commit validation-only corrections if required**

If a heading, code-block, warning, media, release-link, or command count fails,
replace the affected README with the exact approved content from Task 1 or Task
2, then rerun Steps 1 and 2 in full. If a demo asset is absent or the Swift
suite fails, stop and report the blocker without changing application code or
tests.

After a README correction and a fully passing rerun, run:

```bash
git add README.md README.zh-CN.md
git commit -m "docs: align bilingual README details"
```

Expected: either no correction commit is needed, or one focused correction
commit is created after the full matrix passes.

### Task 4: Deliver the documentation through a Pull Request

**Files:**
- Deliver: the committed branch diff; no new file changes.

**Interfaces:**
- Consumes: a clean feature branch with all Task 3 checks passing.
- Produces: a reviewable Pull Request from `docs/readme-bilingual-redesign` to `main`.

- [ ] **Step 1: Push the feature branch**

Run:

```bash
git push -u origin docs/readme-bilingual-redesign
```

Expected: the remote branch is created or updated successfully without
modifying `main`.

- [ ] **Step 2: Inspect the GitHub-rendered README files**

Open:

```text
https://github.com/Benjamin-Island/codex-menubar-tools/blob/docs/readme-bilingual-redesign/README.md
https://github.com/Benjamin-Island/codex-menubar-tools/blob/docs/readme-bilingual-redesign/README.zh-CN.md
```

Expected in both files:

- the language switcher is right-aligned and links to the alternate edition;
- the product name, description, and four badges are centered;
- the animated demo renders and links to the MP4;
- the warning renders as a GitHub warning callout;
- eight H2 sections and two H3 quick-start subsections are visible;
- code blocks are not swallowed by the surrounding HTML or Markdown.

If rendering differs, restore the affected file to its exact approved Task 1
or Task 2 content, rerun Task 3 in full, commit the correction, and push the
same branch again before continuing.

- [ ] **Step 3: Open the Pull Request**

Run:

```bash
gh pr create \
  --base main \
  --head docs/readme-bilingual-redesign \
  --title "docs: redesign README and add Simplified Chinese edition" \
  --body "## Summary
- reorganize the English README around a product-first flow
- add a structurally synchronized Simplified Chinese README
- preserve the existing privacy, installation, release, and testing details

## Validation
- bilingual heading, code-block, warning, media, and release-link parity checks
- swift test --package-path codex-menubar/macos/CodexMenuBar"
```

Expected: GitHub prints the new Pull Request URL.

- [ ] **Step 4: Wait for review before merging**

Report the Pull Request URL, commit list, changed files, and Task 3 test results.
Do not merge until the Pull Request has been reviewed. Apply requested
documentation updates on the same feature branch, rerun Task 3 in full, commit,
and push them to the existing Pull Request.

- [ ] **Step 5: Merge only through the approved Pull Request**

After review approval, run:

```bash
gh pr merge --merge --delete-branch
```

Expected: GitHub reports that the Pull Request was merged into `main`; no direct
push to `main` occurs.
