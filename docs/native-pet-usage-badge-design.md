# Native Pet Usage Badge Design

日期：2026-07-27  
状态：用户已确认

## 背景

当前 Pet Island 使用独立 `NSPanel` 同时渲染摘要卡片和第二只 Pet。现有状态只有展开、收起和贴边：

- 收起状态仍固定渲染 `collapsedFloatingSummary`，因此摘要卡片无法完全隐藏。
- 展开与收起通过保持面板右上角不变来调整窗口尺寸，但 Pet 位于面板右下角。默认比例下，窗口高度从 380 pt 收到 132 pt 时，Pet 会向上跳约 248 pt；屏幕边界裁剪会进一步放大跳位。
- Codex Desktop 已提供原生浮动 Pet、任务状态和 Activity Tray。继续渲染第二只 Pet 会造成重复体验。

本设计用一个附着在 Codex 原生 Pet 旁边的 Usage 徽标替代独立 Pet Island。Codex 负责 Pet 的形象、动画、位置和任务状态；Codex Menu Bar 只负责展示额度摘要。

## 目标

- 桌面上只保留 Codex 原生 Pet。
- 原生 Pet 旁边默认只显示 Primary 剩余百分比徽标，例如 `96%`。
- 点击徽标显示紧凑摘要；再次点击、点击外部或按 `Esc` 收起。
- 收起摘要时原生 Pet 和徽标均不跳位。
- 原生 Pet 移动时徽标跟随；摘要在移动开始后自动收起。
- 原生 Pet 被 Tuck Away、Codex 退出或无法可靠识别时，徽标同步隐藏。
- 菜单栏 Usage 面板继续作为稳定、完整的查看入口。
- 不新增 Accessibility、屏幕录制或 Codex 调试端口权限。

## 非目标

- 不修改 Codex 原生 Pet 的进程、窗口或 React/Electron 界面。
- 不通过 CDP、私有 IPC 或 App Server 控制 Pet。
- 不替代 Codex 原生 Activity Tray、Running、Needs input、Ready 或 Blocked 状态。
- 不在桌面摘要中展示完整任务列表。
- 不在原生 Pet 不可用时回退到第二只 Pet 或独立徽标。
- 不删除旧偏好数据，保留版本回退能力。

## 用户体验

### 状态

```text
未找到唯一原生 Pet
└── hidden

找到唯一原生 Pet
└── badge
    ├── 点击徽标 → summary
    └── Pet 消失 → hidden

summary
├── 再次点击徽标 → badge
├── 点击卡片外部 → badge
├── 按 Esc → badge
├── 原生 Pet 开始移动 → badge
└── Pet 消失 → hidden
```

### 徽标

- 固定尺寸：48 × 28 pt。
- 内容只显示 Primary 剩余百分比，例如 `96%`。
- 无有效 Primary 数据时显示 `--`，但只有在原生 Pet 可见时才显示徽标。
- 颜色继续使用当前 Usage 阈值规则。
- 徽标使用单独的透明、无标题、非激活 `NSPanel`，不会抢走当前应用焦点。

### 紧凑摘要

- 固定内容尺寸：306 × 66 pt，与现有紧凑摘要保持一致。
- 展示：
  - 当前项目名称；
  - Primary 剩余百分比；
  - Secondary 剩余百分比；
  - 当前运行中的 Session 数量。
- 摘要使用第二个独立 `NSPanel`，而不是调整徽标窗口尺寸。
- 徽标窗口始终保持原尺寸和锚点，因此摘要展开、收起不会移动徽标或原生 Pet。
- 完整任务列表和 Today initial 等详细信息继续留在菜单栏面板。

## 架构

### `CodexPetWindowLocator`

职责：

- 使用 `CGWindowListCopyWindowInfo` 读取可见窗口元数据。
- 根据窗口 Owner PID 解析 `NSRunningApplication`。
- 只接受 bundle identifier 为 `com.openai.codex` 的窗口。
- 将同一进程、同一屏幕且空间上关联的窗口组成 Pet 窗口簇。
- 输出唯一、经过验证的 Pet 锚点和障碍窗口；无法唯一确认时返回 `nil`。

当前 Codex `26.721.41059` 的实机窗口角色：

| 窗口名称 | 角色 |
| --- | --- |
| `Codex Pet Mascot Effect` | Pet 本体锚点 |
| `Codex Pet Composition Surface` | Pet 组合面，用于验证窗口簇，不作为定位边界 |
| `Codex Pet Activity Stack Backing` | Activity Tray 障碍区域 |
| `Codex Pet Voice Controls Backing` | 语音控件障碍区域 |
| `Codex` | 原生任务提示区域，作为障碍和窗口簇验证信号 |

这些名称只用于建立和诊断当前结构 Profile。Apple 将 `kCGWindowName` 和
`kCGWindowOwnerName` 定义为可选窗口元数据；未授予屏幕录制权限时，系统可能不返回窗口名称。
运行时匹配不能依赖窗口名称，也不会为了获得名称申请权限。

匹配规则：

1. 只使用始终可用的 `kCGWindowOwnerPID`、`kCGWindowNumber`、`kCGWindowBounds`、
   `kCGWindowLayer`、`kCGWindowAlpha` 和共享状态完成基础匹配。
2. 通过 PID 对应的 `NSRunningApplication.bundleIdentifier` 确认进程身份，不依赖
   `kCGWindowOwnerName`。
3. 使用版本化 `PetWindowMatchProfile` 描述窗口层级、尺寸范围、相对位置和空间交叠关系。
4. 当前 Profile 要求一个 layer 2 的 Pet 本体效果窗口，并要求同一 PID 下存在
   layer 3 的组合面、任务提示或控件窗口形成唯一空间簇。
5. 普通 layer 0 Codex 主窗口、单个紧凑窗口或只有组合面的窗口不能成为 Pet 候选。
6. 如果可选窗口名称存在，用它增强验证和诊断，但名称不能让一个结构不匹配的候选通过。
7. 多显示器上按窗口中心点归属屏幕，再按空间交叠或邻接关系分簇。
8. 同时存在多个有效窗口簇且无法通过当前 Space 和屏幕关系唯一选择时返回 `nil`。
9. 未知 Codex 版本只有在结构完全匹配已有 Profile 时才允许显示；否则安全隐藏。

Locator 只读取窗口 ID、边界、层级、PID、bundle identifier、Codex 版本以及系统可选返回的名称，
不截取窗口图像，也不读取聊天内容。

### `PetUsageBadgeTracker`

职责：

- 驱动 Locator。
- 对窗口位置做去抖和移动检测。
- 输出稳定的 `PetAnchorSnapshot`：

```swift
struct PetAnchorSnapshot: Equatable {
    let anchorFrame: CGRect
    let obstacleFrames: [CGRect]
    let screenFrame: CGRect
    let screenVisibleFrame: CGRect
    let processIdentifier: pid_t
    let appVersion: String?
}
```

刷新策略：

- 功能关闭：停止所有窗口扫描。
- Codex 未运行：每 5 秒进行一次低频进程发现。
- 未找到 Pet：每 2 秒调用一次全量可见窗口发现。
- 找到 Pet 后保存窗口 ID，使用 `CGWindowListCreateDescriptionFromArray` 只刷新已跟踪窗口，
  避免反复生成所有系统窗口的字典。
- Pet 静止：每 500 ms 刷新已跟踪窗口。
- 检测到位置变化：切换到每 75 ms 刷新已跟踪窗口。
- 连续 750 ms 未变化：恢复 500 ms。
- 每 10 秒执行一次低频全量校验，发现新 Activity Tray、窗口替换或 Space 变化。
- Locator 连续失败：按 1、2、5 秒退避，成功后恢复正常节奏。
- 任意时刻只允许一个窗口扫描任务运行，避免重入和积压。

### `PetUsageBadgeController`

职责：

- 管理徽标 `NSPanel` 和摘要 `NSPanel`。
- 管理 `hidden`、`badge`、`summary` 三种状态。
- 把 CoreGraphics 顶部原点坐标转换为 AppKit 底部原点坐标。
- 根据定位结果更新两个 Panel，不修改 Codex 的任何窗口。
- 使用现有点击外部事件抽象收起摘要。
- 摘要使用可成为 Key Window 但不激活应用的自定义 `NSPanel`；通过 `cancelOperation`
  或本地键盘事件处理 `Esc`，不安装全局键盘监听。
- Tracker 报告移动后立即关闭摘要并移动徽标。
- Tracker 返回 `nil` 后立即隐藏两个 Panel。

Panel 配置：

- `borderless`、`nonactivatingPanel`、透明背景。
- `canJoinAllSpaces`、`fullScreenAuxiliary`、`stationary`。
- 与当前 Pet Island 一样使用足以显示在原生 Pet 上方的窗口层级。
- 不接受拖动；位置完全由原生 Pet 决定。

### `PetUsageBadgeView`

职责：

- 从 `DashboardStore` 读取 Usage 和 Session 快照。
- 徽标严格使用 `usage.primary`，Primary 缺失时显示 `--`，不回退 Secondary。
- 摘要按 Primary、Secondary 顺序展示。
- 沿用当前 Usage 颜色、项目标题和运行数量格式。
- 不加载 `CodexPetCatalog`、`PetSpriteView` 或自定义 Pet 素材。

## 定位算法

### 坐标转换

- CoreGraphics 窗口元数据使用全局顶部原点坐标。
- AppKit 使用全局底部原点坐标。
- 每个窗口先根据中心点匹配实际 `NSScreen.frame`，再相对于该显示器转换。
- 支持辅助屏在主屏左侧、上方、下方以及负坐标。
- 所有最终位置都限制在 `NSScreen.visibleFrame`。

### 徽标候选位置

基于 Pet 锚点生成以下候选：

1. 右下；
2. 左下；
3. 右侧居中；
4. 左侧居中。

每个候选与 Pet 保持 8 pt 间距。候选按以下顺序评分：

1. 完全位于 `visibleFrame`；
2. 不与 Pet 锚点相交；
3. 不与 Activity Tray、语音控件或原生任务提示障碍区域相交；
4. 与上一帧徽标位置距离最小；
5. 与屏幕边缘保留至少 4 pt。

没有合格候选时临时进入 `hidden`，不覆盖原生控件。

### 摘要位置

- 徽标位置保持不变。
- 摘要优先向 Pet 和屏幕边缘的反方向展开。
- 摘要不得与 Pet 锚点、原生障碍窗口或徽标相交。
- 摘要最终限制在 `visibleFrame`。
- 没有合格摘要位置时保持 `badge`，不显示摘要。

## 数据流

```text
CGWindowListCopyWindowInfo
        ↓
CodexPetWindowLocator
        ↓ PetAnchorSnapshot?
PetUsageBadgeTracker
        ↓ 稳定位置 / 移动 / 消失
PetUsageBadgeController
        ├── badgePanel
        └── summaryPanel

DashboardStore
        ↓ UsageSnapshot + Sessions
PetUsageBadgeView
```

窗口跟踪和 Usage 刷新彼此独立。Usage 失败不会影响 Pet 定位；Pet 定位失败也不会影响菜单栏 Usage。

## 设置与迁移

菜单项从：

```text
Pet Island
```

改为：

```text
Pet Usage Badge
└── Show beside Codex Pet
```

新偏好键：

```text
petUsageBadge.enabled
petUsageBadge.migratedFromPetIsland
```

首次初始化：

1. 如果新键已经存在，直接使用。
2. 否则读取 `petIsland.enabled`。
3. 旧键存在时复制其值；旧键不存在时默认启用。
4. 写入迁移标记。
5. 不删除以下旧键：
   - `petIsland.enabled`
   - `petIsland.selectedPetID`
   - `petIsland.hasExplicitSelection`
   - `petIsland.presentationMode`
   - `petIsland.petScalePercent`

升级后不再显示 Pet 选择、Follow Local Pet 和 Pet size。Pet 外观与位置统一由 Codex 的 **Settings > Pets** 管理。

## 失败处理与可观测性

统一原则：

> 无法确认就隐藏，不错误附着到 Codex 主窗口或其他浮窗。

安全降级场景：

- Codex 未运行；
- 原生 Pet 被 Tuck Away；
- Pet 窗口簇缺少验证信号；
- 同时存在多个无法区分的窗口簇；
- Codex 更新后窗口名称或结构变化；
- 屏幕或坐标信息无效；
- 徽标或摘要没有无冲突位置。

行为：

- 立即隐藏徽标和摘要。
- 保持菜单栏图标、Popover、Usage 读取和 Session 统计正常。
- 使用退避策略继续发现，不忙循环。
- 下一次成功识别后自动恢复徽标。

诊断日志只记录：

- Codex 版本；
- 匹配 Profile 版本；
- Pet 相关窗口 ID、边界和层级；
- 系统可选返回的窗口名称；
- 候选数量；
- 隐藏原因；
- 扫描耗时和当前轮询档位。

日志不记录聊天文本、项目路径、Token 内容或认证信息。

## 测试策略

### 单元测试

`CodexPetWindowLocatorTests`

- 识别当前版本的完整 Pet 窗口簇。
- 普通 Codex 主窗口不能成为 Pet。
- Composition Surface 不能单独成为锚点。
- 缺少辅助验证窗口时返回 `nil`。
- 多个无法区分的窗口簇时返回 `nil`。
- 不同 PID、bundle identifier 和屏幕的窗口不会错误合并。
- Tuck Away 后窗口消失时返回 `nil`。

`PetUsageBadgePlacementTests`

- 主屏和辅助屏坐标转换。
- 左侧负坐标、上方和下方显示器。
- 四个屏幕边缘的徽标位置。
- Activity Tray、语音控件和任务提示避让。
- 优先保持上一帧位置，避免候选位置抖动。
- 无可用位置时返回隐藏。
- 摘要向可用空间展开，徽标锚点不变。

`PetUsageBadgeStateTests`

- `hidden → badge → summary`。
- 点击徽标、点击外部和 `Esc` 收起。
- Pet 移动时 `summary → badge`。
- Pet 消失时任意状态进入 `hidden`。
- 功能关闭后停止活跃轮询。
- 退避和快慢轮询不会重入。

`PetUsageBadgePreferencesTests`

- 迁移开启和关闭的旧设置。
- 新设置优先于旧设置。
- 缺少旧设置时默认启用。
- 迁移不会删除旧键。

`PetUsageBadgeViewTests`

- 徽标只显示 Primary，缺少 Primary 时显示 `--`，即使 Secondary 有值也不回退。
- 摘要按 Primary、Secondary 顺序展示。
- 无 Usage 时显示 `--`。
- 运行数量和项目标题正确。

### 集成与人工验证

- 使用 fake Locator 驱动真实 Controller，验证 Panel 显隐和位置。
- 对 `hidden`、`badge`、`summary` 做 SwiftUI smoke test。
- 在当前 Codex `26.721.41059` 上 Wake/Tuck Away Pet。
- 把 Pet 拖到每个屏幕角落和辅助显示器。
- 打开 Activity Tray、语音控件和原生任务提示。
- Codex 退出、重启和切换 Space。
- 点击徽标、点击外部、按 `Esc`。
- 摘要打开时拖动 Pet，确认摘要先收起且徽标跟随。
- 连续运行至少 10 分钟，确认稳定态不忙循环、CPU 无持续异常。
- 运行完整 `swift test`，并按失败、修复、全量重跑循环直到全部通过。

## 验收标准

- 桌面上不再出现 Codex Menu Bar 渲染的第二只 Pet。
- 原生 Pet 可见时，48 × 28 pt Usage 徽标稳定附着且显示 Primary 剩余百分比。
- 原生 Pet 不可见或识别不明确时，徽标和摘要均不可见。
- 摘要默认隐藏，只有用户点击徽标后显示。
- 再次点击、点击外部或 `Esc` 可收起摘要。
- 展开和收起摘要不会移动原生 Pet 或徽标。
- 拖动原生 Pet 时摘要自动收起，徽标在移动阶段平滑跟随。
- 原生 Activity Tray、语音控件和任务提示不被徽标或摘要遮挡。
- 菜单栏 Usage 和 Session 功能在所有降级场景下保持可用。
- 不请求新的系统权限，不启动调试端口，不注入 Codex。
- 完整测试通过，长时间运行没有持续高 CPU。

## 发布说明

- 将该变化描述为 Pet Island 向 Codex 原生 Pet Usage Badge 的迁移。
- 说明 Codex 原生 Pet 需要处于 Wake 状态，徽标才会出现。
- 说明完整 Usage 和任务列表仍位于菜单栏面板。
- 原 Pet Island 贡献者的 Git 作者历史保持不变；本次迁移不重写已有提交。

## 参考资料

- [Codex Pets](https://learn.chatgpt.com/docs/pets?surface=app)
- [Apple Required Window List Keys](https://developer.apple.com/documentation/coregraphics/required-window-list-keys)
- [Apple Optional Window List Keys](https://developer.apple.com/documentation/coregraphics/optional-window-list-keys)
- [Apple Advances in macOS Security (WWDC19)](https://developer.apple.com/videos/play/wwdc2019/701/?time=1995)
