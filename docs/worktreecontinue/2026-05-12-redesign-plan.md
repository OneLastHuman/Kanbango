# Add Session 重新设计方案

> 基于对旧方案（2026-05-05）的审查和新分析。旧方案因文件路径错误、遗漏入口、数据模型矛盾、匹配逻辑缺陷等问题从未成功实施。以下是全新方案。

## 核心概念定义

| 操作 | 含义 | 终端命令 | `isWorkTree` |
|------|------|---------|-------------|
| **新建 Worktree** | 让 Claude 创建全新的 git worktree | `claude --worktree` | `true` |
| **新建普通会话** | 在工作区根目录运行 `claude` | `claude` | `false` |
| **继续 Worktree** | `cd` 到已有 worktree 目录再运行 `claude`，不加 `--worktree` | `cd <cwd> && claude` | `false` |
| **恢复会话** | 通过 `sessionId` 恢复一个已关闭标签页的 Claude 会话 | `claude --resume <id>` | 保持原值 |

## SessionOption 枚举

```swift
enum SessionOption: Equatable, Hashable {
    case plain              // 在工作区根目录启动普通 claude 会话
    case newWorktree        // claude --worktree 创建新 worktree
    case continueWorktree(session: Session)  // cd 到已有 worktree 目录，运行 claude
}
```

`Session` 需要实现 `Hashable`（用 `id` 做 hash）：

```swift
struct Session: Identifiable, Codable, Equatable, Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
```

放在 `KanbanModels.swift` 中。

## 数据模型变更

`Session` 结构体 **不加新字段**，现有字段足够：

- `cwd`：会话的工作目录（继续 worktree 时继承被继续的 session 的 cwd）
- `isWorkTree`：入队时设为 `true`（见下方 pendingSessionQueue 入队逻辑），JSONL 解析后 `applyParsed` 会覆盖为一致值
- `isWorkTreeOverridden`：仅在用户显式选择 "新建 Worktree" 时设为 `true`。继续 worktree 时设为 `false`，让 JSONL 能正确维护 `isWorkTree` 值。现有逻辑（SessionManager.swift:457-459）正确：`if !session.isWorkTreeOverridden { session.isWorkTree = parsed.isWorkTree }`

## SessionManager.createSession 变更

```swift
func createSession(
    for taskID: UUID,
    option: SessionOption,
    branch: String,
    boardState: BoardState
) -> Session
```

内部逻辑：

```swift
let command: String
let effectiveCwd: String?
let effectiveIsWorkTree: Bool

switch option {
case .plain:
    command = "claude --permission-mode bypassPermissions"
    effectiveCwd = boardState.workspacePath
    effectiveIsWorkTree = false
case .newWorktree:
    command = "claude --permission-mode bypassPermissions --worktree"
    effectiveCwd = boardState.workspacePath
    effectiveIsWorkTree = true
case .continueWorktree(let session):
    command = "claude --permission-mode bypassPermissions"
    effectiveCwd = session.cwd ?? boardState.workspacePath
    effectiveIsWorkTree = false  // JSONL 会覆盖为 true
}
```

### pendingSessionQueue 入队逻辑

队列中的 `isWorkTree` 标志仍用于 `matchNewSessionId` 的优先级匹配：

| 场景 | 入队 `isWorkTree` | 备注 |
|------|-------------------|------|
| `.plain` | `false` | Claude 启动后解析 JSONL → `parsed.isWorkTree` 可能为 `false` |
| `.newWorktree` | `true` | Claude 启动后解析 JSONL → `parsed.isWorkTree` 为 `true` |
| `.continueWorktree(_)` | **`true`** | 虽然它是普通 `claude` 启动的，但它确实运行在 worktree 目录中。JSONL 解析后 `parsed.isWorkTree = true`，设 `true` 入队可确保优先级1精确匹配。 |

这样三种场景的入队 `isWorkTree` 与 JSONL 解析后的 `parsed.isWorkTree` 始终一致，不存在竞态问题。

## SessionPanelView 弹窗 UI

```
┌─── New Session ───────────────────────┐
│                                       │
│  Session Type                         │
│  [Picker ▼]                          │
│  ┌─────────────────────────────────┐ │
│  │ 普通 (在工作区目录)              │ │
│  │ + 创建新 Worktree               │ │
│  │ ─────────────────────────────── │ │  ← 仅当有 worktree session 时显示
│  │ → feature-auth                  │ │
│  │ → bugfix-123                    │ │
│  └─────────────────────────────────┘ │
│                                       │
│  [Cancel]              [Create]       │
└───────────────────────────────────────┘
```

### 三种渲染状态

**状态 A：没有任何 worktree session**
- Picker 只显示 2 个选项：`普通`、`+ 创建新 Worktree`
- 默认选中 `普通`

**状态 B：有 worktree session**
- Picker 显示：`普通`、`+ 创建新 Worktree`、分隔线、已有 worktree session 列表
- 默认选中第一个已有 worktree session

**状态 C：从 TaskCreateModal 打开（KanbanModals.swift）**
- 与上相同

### Picker 选项的 data model

```swift
enum SessionOption: Equatable {
    case plain
    case newWorktree
    case continueWorktree(session: Session)
}
```

Picker 需要显式指定 `.pickerStyle(.menu)`（macOS 默认的 NSPopUpButton 不支持 Divider）。项目中已有先例（KanbanModals.swift:67-72 Priority picker）。

Picker 的 tag 用 `SessionOption`：

```swift
Picker("", selection: $selectedOption) {
    Text("普通 (在工作区目录)").tag(SessionOption.plain)
    Divider()
    Text("+ 创建新 Worktree").tag(SessionOption.newWorktree)
    if !worktreeSessions.isEmpty {
        Divider()
        ForEach(worktreeSessions) { session in
            Text(displayLabel(for: session))
                .tag(SessionOption.continueWorktree(session: session))
        }
    }
}
.pickerStyle(.menu)  // 必须加，否则 Divider 不显示
```

### Create 按钮逻辑

```swift
Button("Create") {
    _ = sessionManager.createSession(
        for: taskId,
        option: selectedOption,
        branch: "",
        boardState: boardState
    )
    showCreateSession = false
}
```

## 需要修改的文件

| # | 文件 | 改动类型 | 具体内容 |
|---|------|---------|---------|
| 1 | `Sources/Kanbango/KanbanModels.swift` | 新增 | `SessionOption` 枚举定义 |
| 2 | `Sources/Kanbango/SessionManager.swift` | 修改 | `createSession` 签名从 `(worktree:cwd:)` 改为 `(option:)`；内部 switch 处理三种模式 |
| 3 | `Sources/Kanbango/TaskCardView.swift` | 修改 | `SessionPanelView` 中 Toggle → Picker + 三种状态渲染 |
| 4 | `Sources/Kanbango/KanbanModals.swift` | 修改 | `SessionCreateModal` 中 Toggle → Picker + 三种状态渲染 |

## 防御性编程

### 目录存在性检查

`.continueWorktree` 发送 `cd` 命令前检查目录是否存在：

```swift
case .continueWorktree(let session):
    let targetCwd = session.cwd ?? boardState.workspacePath
    if let cwd = targetCwd, FileManager.default.fileExists(atPath: cwd) {
        effectiveCwd = cwd
    } else {
        // worktree 目录已被删除 — fallback 到 workspacePath
        effectiveCwd = boardState.workspacePath
    }
    command = "claude --permission-mode bypassPermissions"
    effectiveIsWorkTree = true
```

### workspacePath 为 nil

`boardState.workspacePath` 的类型是 `String?`（KanbanBoardState.swift:17）。如果为 nil：

- `.plain` / `.newWorktree`：不发送 `cd`，claude 在 shell 默认目录启动
- `.continueWorktree`：用 `session.cwd`，如果也为 nil，同上

**建议**：Create 按钮在无 workspace 时静默禁用（或弹提示引导用户先选择工作区）。但这属于已有问题（当前代码也没处理），不在本次改动范围内。

## 不变的部分

- `Session` 模型本身不加字段
- `JsonlWatcher` 不动
- `BoardState.addSession / removeSession / updateSessionFromParsed` 不动
- `SessionManager.resumeSession / deleteSession / unlinkTab / updateSession / matchNewSessionId` 不动
- 持久化逻辑不动

## 实施步骤

```
Step 1: KanbanModels.swift — 加 SessionOption 枚举
Step 2: SessionManager.swift — 改 createSession 签名和内部逻辑
Step 3: TaskCardView.swift — 改 SessionPanelView
Step 4: KanbanModals.swift — 改 SessionCreateModal
Step 5: bash run.sh 编译 + 打包 + 启动测试
```

### 验证清单

- [x] 无 worktree session 时点击 Add Session → 显示普通/新建 Worktree 两个选项
- [x] 有 worktree session 时点击 Add Session → 显示普通/新建 Worktree/继续已有 三个分区
- [x] 选择"普通"→ Create → 终端执行 `claude`（无 `--worktree`），`cwd = workspacePath`
- [x] 选择"新建 Worktree"→ Create → 终端执行 `claude --worktree`
- [x] 选择"继续 Worktree"→ Create → 终端 `cd <worktree_cwd>` 然后执行 `claude`
- [x] 继续 Worktree 新建的 session 出现在当前 task 的 session 列表中
- [x] 继续 Worktree 新建的 session 的 JSONL 能被正确匹配（`matchNewSessionId`）
- [x] SessionCreateModal（双击卡片弹出的 modal）行为一致
- [x] `bash run.sh` 编译通过，app 正常启动

## 实施总结

### 改动文件

| 文件 | 改动 |
|------|------|
| `Sources/Kanbango/KanbanModels.swift` | `Session` 加 `Hashable` 协议；新增 `SessionOption` 枚举 |
| `Sources/Kanbango/SessionManager.swift` | `createSession` 签名改为 `(option: SessionOption)`，switch 处理三种模式 |
| `Sources/Kanbango/TaskCardView.swift` | `SessionPanelView` Toggle → Picker (`.pickerStyle(.menu)`) |
| `Sources/Kanbango/KanbanModals.swift` | `SessionCreateModal` 同步改为 Picker |

### 已知问题

- `boardState.workspacePath` 为 nil 时，Create 按钮无禁用保护（已有问题、非本次引入）

### 修正的 Bug

在验证中发现：继续 worktree 时 `branch` 传入 `""`，JSONL 覆盖后 branch 变成 `worktree-swift-xxx`（含 `worktree-` 前缀），与 `isWorkTree` 标签重复显示。修复方式：`.continueWorktree` 分支继承原 session 的 `branch` 值（`effectiveBranch = session.branch`）。
