# V2EX 发布文案

## 标题

[分享创造] 做了一个原生 macOS 菜单栏：看 Codex 额度、30 周 Token 热力图和实时会话

## 正文

最近 Codex 用得比较多，我一直想在不打断工作的情况下回答三个问题：额度还剩多少、最近一段时间 Token 都花在哪些天、现在到底跑着几个交互式会话。

所以把之前两个小工具合成了一个：**Codex Menu Bar**。

菜单栏现在只有一个入口，左边是主额度剩余，右边是正在运行的交互式 TUI 数量。点开是一个原生 SwiftUI 面板，分成三页：

- **Overview**：5h / 7d 用量卡片、30 周热力图缩略图、实时会话摘要；
- **History**：按周一到周日排列的 30 周 Token 热力图，可以点进每天，再看 Total / Input / Cached / Output / Reasoning 和当天各会话明细；
- **Sessions**：只显示真正的顶层 Codex 终端 TUI，排除 `exec`、review、IDE、ChatGPT App、OpenClaw 等非交互来源。

这里有个容易踩坑的地方：Codex 日志里的 Token 是累计值，不能把每条记录直接相加。我做了逐字段增量和重置处理；Cached 和 Reasoning 只作为明细展示，不会重复加到 Total。

隐私方面还是尽量克制：

- 只读 `~/.codex/sessions/**/*.jsonl` 和 `~/.codex/session_index.jsonl`；
- 为了识别实时 TUI，只查看当前用户的进程元数据和已经打开的 rollout 路径；
- 不读 `auth.json`，不碰账号凭证；
- 不发网络请求；
- 不写缓存、数据库、分析数据或日志；
- 不能启动、停止或控制任何 Codex 会话。

整个索引只放在内存里，退出应用就消失。我的本机有大约 1.3GB / 418 个 session 日志，优化后的首次 30 周扫描约 16–17 秒，后续刷新只重解析新增或变化的文件。

技术上是 Swift 6 + AppKit + SwiftUI：AppKit 负责菜单栏、Popover、剪贴板和文件监控，面板内容全部是 SwiftUI。macOS 14 起可用，没有 Electron，也没有 Dock 图标。

目前先不提供 Release，想试的话可以 clone 后本地构建：

```bash
git clone https://github.com/benjaminazz1210/codex-menubar-tools.git
cd codex-menubar-tools
codex-menubar/macos/CodexMenuBar/scripts/build-app.sh
open codex-menubar/macos/CodexMenuBar/dist/CodexMenuBar.app
```

测试也只有一条命令：

```bash
swift test --package-path codex-menubar/macos/CodexMenuBar
```

这不是 OpenAI 官方工具，用量数据来自本地 Codex session 事件，不是官方 Usage API。现在还是偏开发者自用的版本，如果你也重度使用 Codex，欢迎反馈热力图、会话识别和交互上哪里还不顺手。

## 发布前清单（不要复制到正文）

- 源码地址：`{{SOURCE_URL}}`
- Overview 截图：`{{OVERVIEW_SCREENSHOT_URL}}`
- History 截图：`{{HISTORY_SCREENSHOT_URL}}`
- 演示视频：`{{DEMO_VIDEO_URL}}`
- 如果未来提供 Release，再补：`{{DOWNLOAD_URL}}`
- 确认删除本节后再发帖
