# V2EX 发布文案

## 标题

[分享创造] 做了一个 macOS 菜单栏小工具，随时看 Codex 5h / 7d 剩余额度

## 正文

最近 Codex 用得比较频繁，但每次想看剩余额度都不太顺手，于是做了一个很小的 macOS 菜单栏工具：**Codex Usage Menu Bar**。

装好之后，菜单栏会直接显示当前主窗口的剩余百分比；点开可以看到：

- 5 小时窗口的剩余额度和重置时间
- 7 天窗口的剩余额度和重置时间
- 当前 Plan、Credits 状态
- 数据最后更新时间

它是原生 Swift/AppKit 写的，没有 Electron，压缩包大约 100 KB。没有 Dock 图标，Codex 日志有变化时会自动刷新，同时每 5 秒兜底刷新一次。

隐私方面我比较在意，所以目前的实现很克制：

- 只读取本机 `~/.codex/sessions/**/*.jsonl`
- 不读取 `~/.codex/auth.json`
- 不发网络请求
- 不写缓存，也不执行 shell 命令

需要说明的是，这不是 OpenAI 官方工具，也不是通过官方 Usage API 获取的数据，而是读取 Codex 本地 session 日志中的 `token_count` 事件。所以要先正常使用过一次 Codex，让本地日志里产生用量数据。

下载：{{DOWNLOAD_URL}}

源码：{{SOURCE_URL}}

截图：{{SCREENSHOT_URL}}

当前版本是 v0.1.0，暂时只打了 Apple Silicon（arm64）包，需要 macOS 14 或以上。应用目前是 ad-hoc 签名、没有做 Apple 公证；如果首次打开被系统拦截，可以右键应用选择“打开”，或者到“系统设置 → 隐私与安全性”里确认打开。

使用方式很简单：下载 ZIP、解压，把 `CodexUsageMenuBar.app` 拖进“应用程序”后运行。它是纯菜单栏应用，启动后不会出现在 Dock 里。

这是我自己日常在用的小工具，第一版功能比较简单。如果你也在重度使用 Codex，欢迎试试；有问题或希望支持 Intel Mac、开机启动之类的功能，也欢迎在楼里反馈或提 Issue。

## 发布前替换

- `{{DOWNLOAD_URL}}`：公开 GitHub Release 中 ZIP 文件的下载地址
- `{{SOURCE_URL}}`：公开后的 GitHub 仓库地址
- `{{SCREENSHOT_URL}}`：建议放一张菜单栏数字和下拉菜单同时可见的截图；如果暂时没有截图，可删掉这一行

仓库当前地址：<https://github.com/benjaminazz1210/codex-menubar-tools>
