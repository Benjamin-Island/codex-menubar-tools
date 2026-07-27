<p align="right">
  <a href="README.md">English</a> |
  <strong>简体中文</strong>
</p>

<div align="center">
  <h1>Codex Menu Bar</h1>
  <p>原生、仅本地运行的 macOS 菜单栏仪表盘，用于查看 Codex 用量、Token 历史记录和实时 Codex 会话。</p>
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

- **概览** — 查看当前速率限制周期及各周期今日初始剩余百分比、紧凑的 Token 热力图，以及实时会话快捷入口。
- **历史记录** — 浏览最近 30 个本地自然日的数据，包括每天的 Total、Input、Cached、Output、Reasoning 明细和各会话分项。
- **会话** — 跟踪活跃的顶层 Codex 终端会话和 Codex Desktop 会话，并显示活动状态、工作目录、最后更新时间和累计 Token。
- **隐私优先** — 无需账户、网络请求、分析服务或后台服务，即可查看本地 Codex 数据。

## 原生 Pet 用量徽标

Codex Menu Bar 可以在 Codex Desktop 自带的原生 Pet 旁显示一个小型 **Primary 剩余额度**徽标，不再创建或渲染第二只宠物。点击徽标会打开紧凑摘要，显示当前项目或任务、Primary 与 Secondary 剩余百分比，以及运行中的会话数量。

在仪表盘底部启用**在 Codex 宠物旁显示额度**，然后在 Codex Desktop 中显示原生 Pet。徽标会跟随 Pet 跨显示器移动；Pet 移动时会关闭摘要，Pet 被收起或无法被安全识别时会自动隐藏。关闭摘要不会移动 Pet 或徽标。

检测过程只读取本机 Codex Desktop 进程的窗口元数据，不读取宠物素材或 Codex 配置，也不需要“辅助功能”或“屏幕录制”权限。

## 为什么使用 Codex Menu Bar

Codex 已经记录了实用的本地会话数据，但检查用量或了解多日活动通常需要离开当前工作流。Codex Menu Bar 将这些数据整理成小巧的只读 SwiftUI 仪表盘，可直接从 macOS 菜单栏打开。

菜单栏图标会显示主要用量的剩余额度和实时交互会话数量。点击图标即可打开“概览”“历史记录”和“会话”页面。

## 隐私与只读设计

本应用：

- 读取 `~/.codex/sessions/**/*.jsonl` 和 `~/.codex/session_index.jsonl`；
- 检查当前用户的进程元数据，以及可写 rollout 文件的关联信息，以识别交互式 TUI；
- **不会**读取 Codex 凭据或 `auth.json`；
- **不会**发起网络请求；
- 只会在 macOS Caches 目录写入本地解析状态缓存；
- **不会**写入数据库、分析数据或日志文件；
- **不会**启动、停止或以其他方式控制 Codex 会话。

应用只从每个会话文件的第一行读取元数据，最多读取 256 KiB；历史文件按最近 30 天的日期目录发现。JSONL 正文以有界数据块流式读取，冷扫描每轮最多读取 64 MiB、单文件最多 16 MiB，或运行 500 ms。缓存保存文件标识、修改时间、大小、解析偏移和每日汇总，不会复制原始 JSONL 记录；文件增长时只从上次偏移继续。

“历史记录”包含最近 30 个本地自然日内所有已建立索引的本地 rollout 来源。冷扫描尚未完成时，界面会明确显示“统计中/部分数据”和剩余文件数，不会把部分结果冒充完整历史。今日初始剩余额度由独立的今日快速索引提供，无需等待 30 天历史完成。“会话”页面显示顶层交互式终端会话，以及 Codex Desktop 中当前打开的用户会话。应用最多索引 10,000 个普通日志，并额外包含当前运行会话所需的全部日志。

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

- [下载 Codex Menu Bar v0.3.5](https://github.com/Benjamin-Island/codex-menubar-tools/releases/download/v0.3.5/CodexMenuBar-v0.3.5-apple-silicon.zip)
- [SHA-256 校验值](https://github.com/Benjamin-Island/codex-menubar-tools/releases/download/v0.3.5/CodexMenuBar-v0.3.5-apple-silicon.zip.sha256)

解压下载文件，将 `CodexMenuBar.app` 移到 `Applications`，然后右键点击应用并选择“打开”完成首次启动。如果 macOS 仍然拒绝打开，请改为从源码构建，不要关闭系统级安全防护。

### 版本历史

| 版本 | 发布日期 | 主要更新 |
| --- | --- | --- |
| [v0.3.5](https://github.com/Benjamin-Island/codex-menubar-tools/releases/tag/v0.3.5) | 2026-07-26 | Pet Island 与有界持久化 30 天历史 |
| [v0.3.4](https://github.com/Benjamin-Island/codex-menubar-tools/releases/tag/v0.3.4) | 2026-07-25 | 显示今日初始剩余额度 |
| [v0.3.3](https://github.com/Benjamin-Island/codex-menubar-tools/releases/tag/v0.3.3) | 2026-07-24 | 实时跟踪 Codex Desktop 会话 |
| [v0.3.2](https://github.com/Benjamin-Island/codex-menubar-tools/releases/tag/v0.3.2) | 2026-07-21 | 点击外部区域时关闭弹窗 |
| [v0.3.1](https://github.com/Benjamin-Island/codex-menubar-tools/releases/tag/v0.3.1) | 2026-07-21 | 减少超大日志产生的干扰 |
| [v0.3.0](https://github.com/Benjamin-Island/codex-menubar-tools/releases/tag/v0.3.0) | 2026-07-21 | 60 天增量用量历史 |
| [v0.2.1](https://github.com/Benjamin-Island/codex-menubar-tools/releases/tag/v0.2.1) | 2026-07-21 | Token Prism 图标 |
| [v0.2.0](https://github.com/Benjamin-Island/codex-menubar-tools/releases/tag/v0.2.0) | 2026-07-21 | Apple Silicon 预览版 |

[查看全部 Releases](https://github.com/Benjamin-Island/codex-menubar-tools/releases)

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
