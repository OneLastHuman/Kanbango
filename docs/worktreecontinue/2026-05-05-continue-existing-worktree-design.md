# 继续已有 Worktree 会话 - 设计规格

## 问题

当一个任务已有 worktree 会话时，用户无法在同一个 worktree 目录下启动新会话。点击"添加会话"始终触发 `claude --worktree`，这会创建一个**新的** worktree 目录，而不是复用已有的那个。

## 目标

允许用户在**已有** worktree 目录中启动新会话，无需创建新目录。

## 关键洞察

- `claude --worktree` 总是创建新的 worktree 目录
- 要在已有 worktree 中工作，只需 `cd` 进去然后运行 `claude`（不加 `--worktree` 标志）
- 会话的 `.jsonl` 文件存储在运行 `claude` 的目录中

## 解决方案

### UI：统一选择器下拉菜单

将"创建 worktree"开关替换为单个选择器，处理两种场景：

**当任务没有 worktree 会话时：**
- 选择器只显示一个选项：`+ 创建新 worktree`
- 行为不变（与当前相同）

**当任务有 1 个以上 worktree 会话时：**
- 选择器显示所有已有 worktree 会话作为选项
- 最后加上 `+ 创建新 worktree`

```
┌─ 新建会话 ────────────────────┐
│                                 │
│  选择类型:                      │
│  ┌───────────────────────────┐ │
│  │ 继续: feature-auth         │ │ ← 已有 worktree 会话
│  │ 继续: bugfix-123          │ │
│  │ ─────────────────────────  │ │
│  │ + 创建新 worktree          │ │ ← 始终在最后
│  └───────────────────────────┘ │
│                                 │
│  [取消]              [创建]    │
└────────────────────────────────┘
```

### SessionOption 枚举

```swift
enum SessionOption: Equatable {
    case continueWorktree(session: Session)
    case newWorktree
}
```

### createSession 方法变更

新增 `continueSession: Session? = nil` 参数：

```swift
func createSession(
    for taskID: UUID,
    worktree: Bool,
    branch: String,
    cwd: String? = nil,
    continueSession: Session? = nil,  // 新增：继续已有 worktree
    boardState: BoardState
) -> Session
```

### 行为矩阵

| 用户选择 | 发送的命令 | isWorkTree 标志 |
|---------|-----------|----------------|
| `继续: {session}` | `cd {session.cwd}` → `claude` | `false` |
| `+ 创建新 worktree` | `claude --worktree` | `true` |

### 数据模型

继续已有 worktree 时创建的新会话：
- `isWorkTree: false`（它是已有 worktree 目录中的普通会话）
- `cwd: session.cwd`（从被继续的会话继承）
- `branch: ""`（不创建新分支）

## 需要修改的文件

1. **TaskCardView.swift** - UI 变更（开关 → 选择器）
2. **SessionManager.swift** - 为 `createSession` 添加 `continueSession` 参数

## 无需修改

- Session 模型保持不变
- JSONL 监控逻辑不变
- 持久化不变
