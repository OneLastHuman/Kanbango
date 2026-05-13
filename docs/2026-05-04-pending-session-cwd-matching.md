# Pending Session FIFO Matching Bug — Worktree Tab/Task Mismatch

## 问题描述

当用户在同一个 Workspace 下创建多个 WorkTree 终端 tab，然后在不同的 tab 中分别执行 `claude` 命令时，终端 tab 的 session 可能会被关联到错误的 Task。

### 复现步骤

1. Task A → 点 "New Session" (WorkTree ON) → 新开终端 tab T1，生成 pending 条目 P1（关联 Task A，worktree=true）
2. Task B → 点 "New Session" (WorkTree ON) → 新开终端 tab T2，生成 pending 条目 P2（关联 Task B，worktree=true）
3. 在 T2（属于 Task B）中执行 `claude` 命令
4. Claude 启动成功，产生 JSONL 文件 → 触发 `matchNewSessionId`
5. 当前匹配逻辑按 FIFO 取队首 → 匹配到 P1（属于 Task A）
6. **结果**：T2 的内容错误关联到 Task A 的 session，Tab 和 Task 串了

### 为什么有这个问题

`createSession` 中每个 tab 只记录了一个 `(localId, isWorkTree, createdAt)` 三元组，FIFO 队列无法区分多个 worktree session。当两个 pending 条目都是 worktree 时，`isWorkTree` 匹配退化为字典序/插入序——而 `claude` 命令在哪个 tab 产生 JSONL 是**不确定**的（取决于用户在哪个 tab 先执行命令）。

### Resume 为什么能正确对应

`resumeSession` 使用 `session.sessionId` 直接匹配（`sendText("claude --resume <id>")`），不经过 pending 队列，所以不受顺序影响。

## 修复方案

### 核心思路

每个 worktree tab 的 cwd 路径是唯一标识符：

```
~/.claude/projects/<prefix>--claude-worktrees-eich/sessions/xxx.jsonl  →  cwd: /Users/hue/Desktop/repo/.claude/worktrees/eich
~/.claude/projects/<prefix>--claude-worktrees-khorana/sessions/xxx.jsonl  →  cwd: /Users/hue/Desktop/repo/.claude/worktrees/khorana
```

在 `matchNewSessionId` 中增加 cwd 匹配作为中间优先级，正确区分不同 worktree tab 产生的 session。

### 修改计划

#### Step 1: `pendingSessionQueue` 增加 `cwd` 字段

在 `SessionManager.swift` 中：

```swift
// 当前
private var pendingSessionQueue: [(localId: UUID, isWorkTree: Bool, createdAt: Date)] = []

// 改为
private var pendingSessionQueue: [(localId: UUID, isWorkTree: Bool, createdAt: Date, cwd: String?)] = []
```

#### Step 2: `createSession` 传递 cwd 到 pending 队列

在 `createSession` 中添加 pending 条目时传入 `cwd` 参数：

```swift
// 当前
pendingSessionQueue.append((localId: localId, isWorkTree: worktree, createdAt: Date()))

// 改为
pendingSessionQueue.append((localId: localId, isWorkTree: worktree, createdAt: Date(), cwd: cwd))
```

#### Step 3: `matchNewSessionId` 增加 cwd 匹配优先级

新的匹配优先级（从高到低）：

1. **isWorkTree + cwd 双重匹配**：当 `parsed.cwd` 非空且 `entry.cwd` 非空时，取两者都匹配的条目
2. **纯 isWorkTree 匹配**：退化到现有逻辑（为 compatibility 保留）
3. **FIFO 队首**：兜底逻辑

```swift
// Priority 1: isWorkTree + cwd match (preferred)
if let cwd = parsed.cwd {
    if let match = pendingSessionQueue.first(where: { $0.isWorkTree == parsed.isWorkTree && $0.cwd == cwd }) {
        entry = match
    }
}
// Priority 2: isWorkTree match (existing)
// Priority 3: FIFO (existing)
```

### 文件

| 文件 | 修改内容 |
|------|----------|
| `Sources/GhosttyDemo/SessionManager.swift` | pending 队列增加 cwd 字段；createSession 传入 cwd；matchNewSessionId 增加 cwd 匹配 |

### 边界情况

- **cwd 为空**：如果 `createSession` 没有 cwd 参数，cwd 为 nil，退化到现有匹配逻辑
- **parsed.cwd 为空**：JSONL 还没写入 cwd，跳过 cwd 匹配，退化到 isWorkTree/FIFO
- **非 WorkTree 场景**：isWorkTree=false 的条目不受影响，继续使用现有逻辑
- **tab 被关掉再 Resume**：不经过 pending 队列，不受影响
