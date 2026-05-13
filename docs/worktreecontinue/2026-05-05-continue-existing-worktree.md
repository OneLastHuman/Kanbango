# Continue Existing Worktree Session - Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Allow users to start a new session in an existing worktree directory (without creating a new one) by replacing the "Create worktree" Toggle with a Picker dropdown.

**Architecture:** Replace the Toggle with a Picker in SessionPanelView. Add `continueSession: Session?` parameter to `SessionManager.createSession()`. When user selects an existing worktree, `cd` to its directory and run `claude` without `--worktree` flag.

**Tech Stack:** SwiftUI, Swift 5.9+

---

## File Map

| File | Change |
|------|--------|
| `Sources/GhosttyDemo/SessionManager.swift:70-127` | Add `continueSession` parameter to `createSession()` |
| `Sources/GhosttyDemo/TaskCardView.swift:234-303` | Replace Toggle with Picker dropdown |

---

## Task 1: Add `SessionOption` enum and update `SessionManager.createSession()`

**Files:**
- Modify: `Sources/GhosttyDemo/SessionManager.swift:70-127`

- [ ] **Step 1: Read current createSession method**

Verify exact line numbers and current implementation at lines 70-127.

- [ ] **Step 2: Add `continueSession` parameter to createSession**

Find the `createSession` method signature at line 70 and add `continueSession: Session? = nil` parameter:

```swift
func createSession(
    for taskID: UUID,
    worktree: Bool,
    branch: String,
    cwd: String? = nil,
    continueSession: Session? = nil,  // ADD THIS LINE
    boardState: BoardState
) -> Session {
```

- [ ] **Step 3: Modify command building logic to handle continueSession**

Find lines 100-106 where the command is built. Replace the if-else with logic that checks `continueSession`:

```swift
// 3. Send Claude command
let command: String
let effectiveCwd: String?

if let continueSession = continueSession {
    // Continue existing worktree: cd to its directory, run claude WITHOUT --worktree
    command = "claude --permission-mode bypassPermissions"
    effectiveCwd = continueSession.cwd
} else if worktree {
    command = "claude --permission-mode bypassPermissions --worktree"
    effectiveCwd = cwd
} else {
    command = "claude --permission-mode bypassPermissions"
    effectiveCwd = cwd
}
```

- [ ] **Step 4: Update the DispatchQueue block to use effectiveCwd**

Find lines 108-116 where the commands are sent. Change `cwd` to `effectiveCwd`:

```swift
DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak tabManager] in
    guard let tabManager else { return }
    if let effectiveCwd {
        tabManager.activeTab?.surfaceView.sendText("cd \(effectiveCwd)")
        tabManager.activeTab?.surfaceView.sendEnter()
    }
    tabManager.activeTab?.surfaceView.sendText(command)
    tabManager.activeTab?.surfaceView.sendEnter()
}
```

- [ ] **Step 5: Update isWorkTree flag in session creation**

Find lines 87-98 where the Session is created. When `continueSession` is set, `isWorkTree` should be `false`:

```swift
let effectiveIsWorkTree = continueSession != nil ? false : worktree
let session = Session(
    id: localId,
    title: "New Session",
    status: .running,
    timestamp: Date(),
    isWorkTree: effectiveIsWorkTree,
    isWorkTreeOverridden: effectiveIsWorkTree,  // user explicitly specified → protect from JSONL overwrite
    branch: branch,
    sessionId: nil,
    tabID: tabID,
    cwd: effectiveCwd
)
```

- [ ] **Step 6: Update pendingSessionQueue entry**

Find line 121 where `pendingSessionQueue` is appended. Change to use `effectiveIsWorkTree`:

```swift
pendingSessionQueue.append((localId: localId, isWorkTree: effectiveIsWorkTree, createdAt: Date()))
```

- [ ] **Step 7: Commit**

```bash
git add Sources/GhosttyDemo/SessionManager.swift
git commit -m "feat: add continueSession parameter to createSession for existing worktree reuse"
```

---

## Task 2: Replace Toggle with Picker in SessionPanelView

**Files:**
- Modify: `Sources/GhosttyDemo/TaskCardView.swift:234-303`

- [ ] **Step 1: Read current SessionPanelView implementation**

Verify exact lines 234-303.

- [ ] **Step 2: Add SessionOption enum before SessionPanelView**

Find line 233, add the enum definition before `struct SessionPanelView`:

```swift
// MARK: - SessionOption

enum SessionOption: Equatable {
    case continueWorktree(session: Session)
    case newWorktree
}

// MARK: - SessionPanelView
```

- [ ] **Step 3: Replace @State and sheet content**

Replace lines 242-301 with:

```swift
@State private var showCreateSession = false
@State private var selectedOption: SessionOption = .newWorktree
@Environment(\.themeColors) var colors

private var worktreeSessions: [Session] {
    sessions.filter { $0.isWorkTree }
}

var body: some View {
    VStack(spacing: 0) {
        ForEach(sessions) { session in
            SessionRowView(
                session: session,
                onResume: { sessionManager.resumeSession(session) },
                onDelete: { boardState.removeSession(from: taskId, sessionId: session.id) }
            )
            if session.id != sessions.last?.id {
                Divider().padding(.leading, 24)
            }
        }

        Button(action: { showCreateSession = true }) {
            HStack(spacing: 4) {
                Image(systemName: "plus.circle").font(.system(size: 10))
                Text("Add Session").font(.system(size: 10))
            }
            .foregroundColor(colors.accent)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(colors.accent.opacity(0.08))
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .padding(.top, 6)
    }
    .padding(8)
    .background(colors.sessionPanelBg)
    .cornerRadius(6)
    .sheet(isPresented: $showCreateSession) {
        VStack(spacing: 16) {
            Text("New Session").font(.headline)

            if worktreeSessions.isEmpty {
                // No existing worktrees - simple case, just create new
                HStack(spacing: 12) {
                    Button("Cancel") { showCreateSession = false }
                    Button("Create") {
                        _ = sessionManager.createSession(
                            for: taskId,
                            worktree: true,
                            branch: "",
                            cwd: boardState.workspacePath,
                            boardState: boardState
                        )
                        showCreateSession = false
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                // Has existing worktrees - show picker
                Picker("选择类型", selection: $selectedOption) {
                    ForEach(worktreeSessions) { session in
                        Text("Continue: \(session.branch.isEmpty ? (session.cwd?.components(separatedBy: "/").last ?? "worktree") : session.branch)")
                            .tag(SessionOption.continueWorktree(session: session))
                    }
                    Text("+ Create new worktree")
                        .tag(SessionOption.newWorktree)
                }
                .pickerStyle(.menu)

                HStack(spacing: 12) {
                    Button("Cancel") { showCreateSession = false }
                    Button("Create") {
                        switch selectedOption {
                        case .continueWorktree(let session):
                            _ = sessionManager.createSession(
                                for: taskId,
                                worktree: false,
                                branch: "",
                                continueSession: session,
                                boardState: boardState
                            )
                        case .newWorktree:
                            _ = sessionManager.createSession(
                                for: taskId,
                                worktree: true,
                                branch: "",
                                cwd: boardState.workspacePath,
                                boardState: boardState
                            )
                        }
                        showCreateSession = false
                        selectedOption = .newWorktree
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(20)
        .frame(width: 300)
        .background(colors.modalBg)
    }
}
```

- [ ] **Step 4: Commit**

```bash
git add Sources/GhosttyDemo/TaskCardView.swift
git commit -m "feat: replace worktree toggle with picker dropdown for session creation"
```

---

## Task 3: Verify and build

- [ ] **Step 1: Build the project**

```bash
cd /Users/hue/Documents/kanban-ghostty/.claude/worktrees/snazzy-honking-bengio
swift build 2>&1
```

Expected: Build succeeds with no errors.

- [ ] **Step 2: Package and run**

```bash
bash run.sh 2>&1
```

Expected: App launches successfully. Click "Add Session" on a task that has an existing worktree session - should see the picker dropdown with existing worktree options.

---

## Spec Coverage Check

| Spec requirement | Task |
|------------------|------|
| Replace Toggle with Picker | Task 2 |
| Add continueSession parameter | Task 1 |
| Continue: cd + claude (no --worktree) | Task 1 |
| Create new worktree: claude --worktree | Task 1 |
| isWorkTree=false for continued sessions | Task 1 |
| No existing worktrees = only create option | Task 2 |
| Build succeeds | Task 3 |

## Self-Review

- No TODOs or placeholders in the plan
- All file paths are exact with line numbers
- All code blocks are complete and syntactically correct Swift
- Types match between tasks (SessionOption enum, continueSession parameter)
- Command logic: continueSession → `cd` + `claude` without `--worktree`; newWorktree → `claude --worktree`
