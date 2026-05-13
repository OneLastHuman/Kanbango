# AGENTS.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# 行为准则

1. 每当我提新功能/修改点，先用准确易懂的语言复述并找我确认；周全思考，提醒我未考虑的细节。
2. 我是一个毫无编程经验的产品经理，请用简单、清晰、有逻辑的语言表达。
3. 任务稍微复杂就委派子 Agent；复杂度更高则拆成多个子 Agent 串行/并行，你作为协调者规划和统筹。

# Kanbango

一个 macOS SwiftUI 应用，将 Ghostty 终端通过 C API 嵌入到看板应用中，用于管理 Claude Code 会话。

Ghostty源码位置在：/Users/hue/Documents/ghostty-main

## 项目结构

```
Kanbango/
├── Sources/
│   ├── Kanbango/                  # 看板应用全部源码（~13 个文件）
│   ├── GhosttyRuntime/            # Ghostty Swift Runtime（侵入式集成，源码来自 Ghostty 项目）
│   ├── GhosttyKit/                # C 桥接模块，链接 libghostty-internal.a
│   └── GhosttyObjC/               # ObjC 桥接模块
├── Package.swift                  # SPM 包定义，链接 384MB libghostty-internal.a 静态库
├── run.sh                         # 编译 → 打包 .app → 启动（开发版 Kanbango）
├── release.sh                     # 编译 → 打包 .app → 安装到 /Applications（发布版 Kanbango-Release）
├── libghostty-internal.a          # GhosttyKit 预编译静态库
└── docs/                          # 设计文档、探索记录、技术文档
```

## 构建

```bash
# 开发版：编译 + 打包 .app + 启动（推荐）
bash run.sh

# 发布版：编译 + 打包 + 安装到 /Applications
bash release.sh

# 仅编译
swift build
```

- `run.sh`：构建 `Kanbango.app`（bundle id: `com.kanbango.app`），杀旧进程后启动
- `release.sh`：构建 `Kanbango-Release.app`（bundle id: `com.kanbango.release`），复制到 `/Applications`。两个版本进程独立，互不干扰

**重要：每次修改 Swift 代码后必须重新打包 app。** 调试用 Safari Web Inspector 不可用（纯 SwiftUI，非 WKWebView）。

## 架构概览

### 应用入口

```
main.swift → AppDelegate → ContentView(HSplitView)
  ├── 左面板：KanbanView（看板列 + 任务卡片）
  └── 右面板：TabBar + GhosttySurfaceView（终端）
```

启动流程：`ghostty_init()` → `GhosttyApp()`（渲染定时器启动）→ `ContentView` → 创建首个终端 tab → 配置 `SessionManager` → 启动 `JsonlWatcher` 监控 JSONL 文件。

### 核心数据流

```
JsonlWatcher (GCD) → onChange callback → SessionManager.updateSession()
  → 匹配 sessionId → 更新内存状态 + BoardState.save() 持久化

SessionManager.createSession() → TerminalTabManager.newTab()
  → sendText("claude ...") → 终端执行 → Claude 创建 JSONL 文件
  → JsonlWatcher 检测新文件 → onNewSessionId → matchNewSessionId() FIFO 匹配
```

### 5 大核心类

| 类 | 职责 | 关键模式 |
|----|------|---------|
| `BoardState` (@MainActor, singleton) | 任务 CRUD、主题、工作区路径选择 | `@Published` + 每次修改调 `save()` |
| `SessionManager` (@MainActor, singleton) | 会话创建/恢复/删除、JSONL 状态同步 | 双索引：flat `sessions` 列表 + `taskSessionIDs`/`sessionTaskMap` 映射 |
| `TerminalTabManager` (@MainActor) | 终端标签页创建/切换/关闭 | `GhosttySurfaceView` (GhosttyKit) + `focusDidChange`/`setOcclusion` |
| `JsonlWatcher` | 监控 `~/.claude/projects/` 的 JSONL 文件 | GCD DispatchSource + 3s 轮询 + 增量解析 + LRU 缓存 |
| `Persistence` (singleton) | JSON 读写任务数据 | `tasks.json` 存在工作区 `.kanban/` 或 `~/Library/Application Support/KanbanBoard/` |

### 拖拽实现

完全基于 SwiftUI 原生 API：
- `DragGesture` 在 `TaskCardView` 识别
- `DragDropState`（ObservableObject）管理全局拖拽状态
- PreferenceKey（`ColumnFramesKey`/`CardFramesKey`）收集布局坐标
- 命中检测：幽灵卡片中心点 + 列 frame 容差检测，确定目标列和插入索引
- 按 Esc 可取消拖拽

### 主题系统

`KanbanTheme.swift` 定义 `Theme.Light`/`Theme.Dark` 两组颜色常量，通过 `ThemeColors` struct + `EnvironmentKey` 注入到视图层级。在 `ContentView` 通过 `.environment(\.themeColors, ...)` 设置。

### 工作区切换

`BoardState.selectWorkspace()` 打开 NSOpenPanel，选择文件夹后保存路径到 UserDefaults，然后**启动新 app 实例**（`NSWorkspace.shared.openApplication` + `createsNewApplicationInstance = true`）。

### JSONL 增量解析

`JsonlWatcher` 跟踪每个文件的字节偏移量，只读取追加的新行。解析结果缓存在 LRU 字典（最大 500 个文件）。采用 GCD DispatchSource 监控目录写入/重命名/删除，+ 3 秒回退轮询（捕获取子目录变化）。

会话匹配优先级：
1. `session.sessionId == parsed.sessionId`
2. `session.id.uuidString.uppercased() == parsed.sessionId.uppercased()`
3. `session.sessionId == nil`（通过 cwd 或直接匹配）
4. 无匹配 → `autoCreateSession()` 自动创建新 kanban 会话

新会话匹配使用 FIFO 队列（`pendingSessionQueue`），优先按 `isWorkTree` 标志匹配，否则取队首。

### Session 生命周期

```
createSession → newTab + sendText("claude ...") + 入 pendingSessionQueue
  → JSONL 文件出现 → onNewSessionId → matchNewSessionId（设 sessionId）→ 出队

resumeSession → tab 存在则 selectTab，否则 newTab + sendText("claude --resume ...")

deleteSession → closeTab + 从索引移除

unlinkTab → 有 sessionId 则 tabID=nil（可恢复），否则完全删除
```

### 数据模型

```swift
KanbanTask: id, title, description, priority(P0-P3), status(todo/inProgress/review/done), sessions, tags(bug/feat/docs/refac/test/ui/sec/perf), isExpanded
Session: id, title, status(running/idle/needInput), timestamp, isWorkTree, isWorkTreeOverridden, branch, sessionId, tabID(UUID?), cwd
```

## 存储

| 数据 | 位置 |
|------|------|
| 任务 | `{workspace}/.kanban/tasks.json` 或 `~/Library/Application Support/KanbanBoard/tasks.json` |
| Claude 会话 | `~/.claude/projects/*/*.jsonl`（只读监控）|
| 工作区路径 | UserDefaults `kanban-workspace-path` |
| 主题偏好 | UserDefaults `kanban-dark-mode` |

## 开发注意

- 主题颜色在 `KanbanTheme.swift` 中调整
- 已知问题：JSONL 监控依赖 `~/.claude/projects/` 目录存在；首次启动创建示例任务数据
