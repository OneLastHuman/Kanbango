# WorkTree Session Matching Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix WorkTree session association so it works as fast as main branch sessions.

**Architecture:** Replace workspace-specific JSONL directory watching with parent directory (`~/.claude/projects/`) watching + workspace prefix filtering. This covers both main and worktree subdirectories naturally. Add workspace boundary checks to `autoCreateSession` and `matchNewSessionId` to prevent cross-workspace contamination.

**Tech Stack:** Swift (SwiftUI/GCD), GhosttyKit C bridge

---

## Background: Why WorkTree Sessions Don't Match

**Problem**: `JsonlWatcher` watches `~/.claude/projects/<encoded-workspace>/`, but WorkTree session JSONL files are stored in `~/.claude/projects/<encoded-workspace>--claude-worktrees-<name>/` — a subdirectory that is NOT covered by the current watch path.

**Evidence**:
```
Watch path:  ~/.claude/projects/-Users-hue-Desktop-git1/
WorkTree:    ~/.claude/projects/-Users-hue-Desktop-git1--claude-worktrees-abstract-frolicking-eich/
```

**Key finding from JSONL inspection**:
- Main session cwd: `/Users/hue/Desktop/git1`
- WorkTree session cwd: `/Users/hue/Desktop/git1/.claude/worktrees/abstract-frolicking-eich`

WorkTree cwd IS a subdirectory of the main workspace — so workspace prefix filtering WILL work for both.

**Critical difference in path structure**:
```
Main:      ...projects/-prefix/sessions/file.jsonl     → prefix followed by /
Worktree:  ...projects/-prefix--claude-worktrees-name/sessions/file.jsonl → prefix followed by -
```

The filter must handle both delimiters (`/` for main, `-` for worktree).

---

## Files to Modify

| File | Responsibility |
|------|----------------|
| `Sources/GhosttyDemo/ContentView.swift` | Change `watchPath` from workspace-specific to parent `~/.claude/projects/`, pass `workspacePrefix` to both JsonlWatcher and SessionManager |
| `Sources/GhosttyDemo/JsonlWatcher.swift` | Accept optional `workspacePrefix` filter, filter by checking if `filePath` contains workspace prefix as a path component (delimited by `/` or `-`) |
| `Sources/GhosttyDemo/SessionManager.swift` | Store `workspacePrefix` and `currentWorkspacePath`, add workspace boundary in `autoCreateSession` and `matchNewSessionId` using the original (decoded) workspace path for comparison |

---

## Task 1: Update `ContentView.swift` — Change Watch Path to Parent Directory

**Files:**
- Modify: `Sources/GhosttyDemo/ContentView.swift:79-92`

- [ ] **Step 1: Add workspace prefix computation**

Find this code (lines 79-88):
```swift
let watchPath: String
if let ws = boardState.workspacePath {
    let encoded = ws.replacingOccurrences(of: "/", with: "-")
        .replacingOccurrences(of: ".", with: "-")
        .replacingOccurrences(of: ":", with: "-")
        .replacingOccurrences(of: " ", with: "-")
    watchPath = claudeProjects + "/" + encoded
} else {
    watchPath = claudeProjects
}
```

Replace with:
```swift
// Compute encoded workspace prefix for filtering sessions across both
// main and worktree subdirectories.
let workspacePrefix: String
let watchPath: String
if let ws = boardState.workspacePath {
    let encoded = ws.replacingOccurrences(of: "/", with: "-")
        .replacingOccurrences(of: ".", with: "-")
        .replacingOccurrences(of: ":", with: "-")
        .replacingOccurrences(of: " ", with: "-")
    workspacePrefix = encoded
    watchPath = claudeProjects  // Watch parent so we catch worktree subdirs
} else {
    workspacePrefix = ""
    watchPath = claudeProjects
}
```

- [ ] **Step 2: Pass workspace prefix to sessionWatcher**

Update the `sessionWatcher.start(...)` call to pass the prefix.

Find (around line 90-93):
```swift
let sessionWatcher = JsonlWatcher(path: watchPath)
sessionWatcher.start(
    onChange: { [sessionManager] parsedSessions in
```

Change to:
```swift
let sessionWatcher = JsonlWatcher(path: watchPath, workspacePrefix: workspacePrefix)
sessionWatcher.start(
    onChange: { [sessionManager] parsedSessions in
```

- [ ] **Step 3: Pass workspacePrefix to SessionManager**

`SessionManager` currently stores `currentWorkspacePath` via `configure()` (line 54). Add a separate `workspacePrefix` property.

After `sessionManager.configure(tabManager: tabManager, app: app)` (line 57 area), add:
```swift
sessionManager.workspacePrefix = workspacePrefix
```

- [ ] **Step 4: Commit**

```bash
git add Sources/GhosttyDemo/ContentView.swift
git commit -m "fix: watch parent dir for worktree JSONL files"
```

---

## Task 2: Update `JsonlWatcher` — Add Workspace Prefix Filter

**Files:**
- Modify: `Sources/GhosttyDemo/JsonlWatcher.swift` (init and filtering logic)

- [ ] **Step 1: Add `workspacePrefix` parameter to initializer**

Find the initializer at line 239:
```swift
init(path: String) {
    self.path = path
}
```

Replace with:
```swift
let workspacePrefix: String

init(path: String, workspacePrefix: String = "") {
    self.path = path
    self.workspacePrefix = workspacePrefix
}
```

- [ ] **Step 2: Add filter logic in `enumerateJsonlFiles`**

The filter must be applied in `enumerateJsonlFiles()` (line 386), NOT in `parseFile`. The file paths at this level look like:

```
~/.claude/projects/-Users-hue-Desktop-git1/sessions/abc123.jsonl           (main)
~/.claude/projects/-Users-hue-Desktop-git1--claude-worktrees-name/sessions/abc123.jsonl  (worktree)
```

The workspace prefix appears as a path component. In main sessions it's followed by `/`, in worktree sessions it's followed by `-` (the start of `--claude-worktrees-...`). The filter must handle both cases.

In `enumerateJsonlFiles()`, after the `subagents/` check (line 400-405), add:

```swift
// Filter: skip files not belonging to this workspace.
// workspacePrefix is empty when no workspace is configured (backward compatible).
if !workspacePrefix.isEmpty {
    let pathComponentPrefix = "/" + workspacePrefix
    // Main sessions: prefix is followed by "/"
    // Worktree sessions: prefix is followed by "-" (e.g. "--claude-worktrees-name")
    if !filePath.contains(pathComponentPrefix + "/") &&
       !filePath.contains(pathComponentPrefix + "-") {
        continue
    }
}
```

The `-` match could theoretically have a false positive if another workspace name happens to start with `-Users-hue-Desktop-git1-something` (without worktree separator), but this is extremely unlikely given that workspace prefixes are encoded from full absolute paths. The downstream cwd boundary check in `SessionManager` serves as the definitive safety net.

- [ ] **Step 3: Commit**

```bash
git add Sources/GhosttyDemo/JsonlWatcher.swift
git commit -m "feat: add workspacePrefix filter to JsonlWatcher"
```

---

## Task 3: Update `SessionManager` — Add Workspace Boundary Checks

**Files:**
- Modify: `Sources/GhosttyDemo/SessionManager.swift` (autoCreateSession, matchNewSessionId, and updateSession)

- [ ] **Step 1: Store workspacePrefix as instance property**

Find the SessionManager class properties (near line 32). Add after `currentWorkspacePath`:
```swift
/// Encoded workspace prefix, used to gate boundary checks.
/// Empty when no workspace is configured.
var workspacePrefix: String = ""
```

- [ ] **Step 2: Add workspace boundary check in `autoCreateSession`**

Find `autoCreateSession` at line 401. Add at the top, before any session creation logic:

```swift
private func autoCreateSession(from parsed: ParsedSession) {
    // SECURITY: Only auto-create if cwd belongs to this workspace.
    // When watching parent dir, other workspaces' sessions must not leak in.
    if !workspacePrefix.isEmpty, let workspacePath = currentWorkspacePath {
        guard let cwd = parsed.cwd, cwd.hasPrefix(workspacePath) else {
            return
        }
    }
    // ... rest of existing method
}
```

Note: `currentWorkspacePath` contains the decoded path like `/Users/hue/Desktop/git1`. Both main cwd (`/Users/hue/Desktop/git1`) and worktree cwd (`/Users/hue/Desktop/git1/.claude/worktrees/name`) pass `hasPrefix(workspacePath)`, so this works for both.

- [ ] **Step 3: Add cwd validation in `matchNewSessionId`**

Find `matchNewSessionId` at line 366. Add validation before the matching logic (before `guard !pendingSessionQueue.isEmpty`):

```swift
func matchNewSessionId(_ claudeSessionId: String, from parsed: ParsedSession) {
    // SECURITY: Validate workspace boundary when watching parent directory.
    if !workspacePrefix.isEmpty, let workspacePath = currentWorkspacePath {
        // Reject if cwd is missing OR doesn't match workspace.
        guard let parsedCwd = parsed.cwd, parsedCwd.hasPrefix(workspacePath) else {
            return
        }
    }

    guard !pendingSessionQueue.isEmpty else { return }
    // ... rest of existing matching logic unchanged ...
```

This also handles the nil-cwd case (sessions without cwd are rejected when watching parent directory), because the `guard let` fails when `parsed.cwd` is nil.

- [ ] **Step 4: Add workspace boundary check in `updateSession`**

Find `updateSession` at line 262. Add at the top:

```swift
func updateSession(from parsed: ParsedSession) {
    // SECURITY: When watching parent dir, skip sessions from other workspaces.
    if !workspacePrefix.isEmpty, let workspacePath = currentWorkspacePath {
        if let parsedCwd = parsed.cwd, !parsedCwd.hasPrefix(workspacePath) {
            return
        }
    }

    var matchedIndex: Int?
    // ... rest of existing method unchanged ...
```

Note: Unlike `matchNewSessionId`, we do NOT reject nil-cwd sessions here. The `updateSession` matching chain (sessionId → uuidString → cwd → fallback) is more reliable and can still match sessions that haven't emitted their cwd yet. The `enumerateJsonlFiles` filter already filters by workspace prefix, so the risk of cross-workspace matching here is minimal.

- [ ] **Step 5: Commit**

```bash
git add Sources/GhosttyDemo/SessionManager.swift
git commit -m "fix: add workspace boundary checks to prevent cross-workspace session contamination"
```

---

## Task 4: Test — Verify WorkTree Session Matching

**Files:**
- Test: Manual verification (no existing test suite)

- [ ] **Step 1: Rebuild the app**

```bash
bash run.sh
```

- [ ] **Step 2: Create a WorkTree session and verify association**

1. Open the app with workspace set to a git repo with worktree support
2. Create a new task or select existing one
3. Click "New Session" with WorkTree toggle ON
4. Observe: the session should associate within seconds (same as main branch)
5. Check: the session card shows the correct branch name and worktree indicator

- [ ] **Step 3: Verify main branch sessions still work**

1. Create a regular (non-WorkTree) session in the same workspace
2. Verify it associates quickly

- [ ] **Step 4: Verify terminal-created sessions are detected**

1. Open a terminal tab, `cd` to the workspace directory
2. Run `claude` manually in the terminal
3. Verify the session is auto-detected and added to the first task

- [ ] **Step 5: Verify cross-workspace isolation**

1. Have two different workspace directories on disk (e.g., `/Users/hue/Desktop/git1` and `/Users/hue/Desktop/project-b`)
2. Open the app pointing to workspace A
3. Manually create a JSONL file in workspace B's directory
4. Verify: NO stray session is auto-created in workspace A

- [ ] **Step 6: Test app restart with active worktree session**

1. Create a worktree session, verify it associates
2. Restart the app (quit and relaunch via `bash run.sh`)
3. Verify: the worktree session restores correctly with its `sessionId` and `tabID`

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "test: verify worktree session matching fix"
```

---

## Verification Checklist

- [ ] WorkTree session JSONL files in `~/.claude/projects/--claude-worktrees-*/` are now detected
- [ ] WorkTree sessions associate within ~1 second (same as main branch)
- [ ] Main branch sessions still work unchanged
- [ ] `enumerateJsonlFiles` correctly filters both main (`prefix/`) and worktree (`prefix-`) paths
- [ ] `autoCreateSession` does NOT create stray sessions from other workspaces
- [ ] `matchNewSessionId` does NOT match sessions from other workspaces
- [ ] `updateSession` does NOT update sessions with cwd from other workspaces
- [ ] Sessions without `cwd` are rejected in `matchNewSessionId` but still processable in `updateSession`
- [ ] App restart restores worktree sessions correctly
- [ ] App builds and runs without crashes
