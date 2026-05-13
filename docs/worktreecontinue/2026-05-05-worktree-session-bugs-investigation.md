# Worktree Session Bug Investigation Report

## Problem Summary

When creating worktree sessions, two bugs occur:
1. **Bug 1 (cwd)**: Session's `cwd` is set to workspace path (e.g., `/Users/hue/Desktop/git1`) instead of actual worktree path (e.g., `/Users/hue/Desktop/git1/.claude/worktrees/mellow-drifting-lerdorf`)
2. **Bug 2 (title/branch)**: Session's `title` and `branch` show workspace name ("git1") or "main" instead of worktree name (e.g., "mellow-drifting-lerdorf")

## JSONL Data Analysis

The JSONL file correctly contains worktree data:

```json
{
  "type": "worktree-state",
  "worktreeSession": {
    "originalCwd": "/Users/hue/Desktop/git1",
    "worktreePath": "/Users/hue/Desktop/git1/.claude/worktrees/mellow-drifting-lerdorf",
    "worktreeName": "mellow-drifting-lerdorf",
    "worktreeBranch": "worktree-mellow-drifting-lerdorf",
    "originalBranch": "main"
  }
}
```

All subsequent `attachment` events also have correct `cwd`:
```json
"cwd": "/Users/hue/Desktop/git1/.claude/worktrees/mellow-drifting-lerdorf"
```

**Conclusion**: JSONL data is correct. Problem is in parsing/persistence logic.

## Root Cause Analysis

### Bug 1 (cwd) - Root Cause

In `JsonlWatcher.swift`, `ParsedSession.absorb()` processes events in this order:

1. **Line 38-40**: `extractCWD()` is called BEFORE checking `worktree-state`
   - For `worktree-state` events with `worktreeSession.worktreePath`, this returns `nil` (no top-level `cwd`)
   - But for `attachment` events that follow, this returns the correct worktree path from top-level `cwd`
   - However, when `isWorkTree` is already `true`, subsequent `attachment` events should NOT overwrite `cwd`

2. **Line 47-61**: `worktree-state` block sets:
   - `isWorkTree = true`
   - `branch = worktreeName`
   - `title = worktreeName`
   - `cwd = worktreePath`

**Problem**: For `attachment` events that follow `worktree-state`, if they have a top-level `cwd`, it would overwrite the worktree path set in `worktree-state`. The code lacked protection against this overwrite.

**Fix Applied** (line 38-45):
```swift
// Only update cwd from top-level json["cwd"] if we're NOT already in a worktree session.
if !isWorkTree {
    if let extractedCWD = Self.extractCWD(from: json), !extractedCWD.isEmpty {
        cwd = extractedCWD
    }
}
```

### Bug 2 (title/branch) - Root Cause

**Title Issue**: In `worktree-state` block (line 47-61), title is only set if `title == "New Session"`:
```swift
if title == "New Session" {
    title = worktreeName
}
```
This condition might fail if title was already changed by prior events.

**Fix Applied** (line 54): Remove condition
```swift
title = worktreeName  // Always set for worktree sessions
```

**Branch Issue**: The `gitBranch` extraction at line 29-36 correctly checks `if !isWorkTree` before overwriting, so this should work correctly. The `worktree-state` block at line 52 sets `branch = worktreeName` which should override.

## Current State of Fixes

### Fix 1: Bug 1 (cwd protection)
**File**: `Sources/GhosttyDemo/JsonlWatcher.swift`
**Change**: Added `if !isWorkTree` guard before `extractCWD()` call (lines 38-45)

### Fix 2: Bug 2 (title always set)
**File**: `Sources/GhosttyDemo/JsonlWatcher.swift`
**Change**: Removed `if title == "New Session"` condition in `worktree-state` block (line 54)

### Fix 3: Bug 1 additional (removed originalCwd fallback)
**File**: `Sources/GhosttyDemo/JsonlWatcher.swift`
**Change**: Removed `originalCwd` fallback in `extractCWD()` function (lines 117-118) - this was causing wrong fallback behavior

## Persistence Issue

After examining `tasks.json`, found that **existing worktree sessions have incorrect data persisted**:
- `isWorkTree: true` but `cwd: "/Users/hue/Desktop/git1"` (workspace path)
- `isWorkTree: true` but `branch: "main"` (not worktree name)

This indicates that the buggy `absorb()` logic was being used to update sessions via `updateSessionFromParsed()`.

## Why Bugs Still Exist After Fixes

1. **Old corrupted data**: Sessions already saved in `tasks.json` have wrong `cwd` and `branch`. The fixes only apply to NEW events being parsed, not to already-persisted data.

2. **Incremental parsing issue**: If `JsonlWatcher` re-parses existing JSONL files, it uses cached `ParsedSession` state. The `isWorkTree` flag in that cache may already be incorrect, affecting subsequent `absorb()` calls.

## Verification Steps Needed

1. Create a **brand new worktree session** (not resume)
2. Wait for `worktree-state` event to be parsed
3. Check if session now shows correct:
   - `cwd` = worktree path (not workspace path)
   - `title` = worktree name (e.g., "mellow-drifting-lerdorf")
   - `branch` = worktree name (not "main")

## Files Modified

| File | Changes |
|------|---------|
| `Sources/GhosttyDemo/JsonlWatcher.swift` | Lines 38-45, 54, 117-118 |

## Commit History

- `e438f1a`: feat: add continueSession parameter to createSession for existing worktree reuse
- `45f6457`: feat: replace worktree toggle with picker dropdown for session creation
- `[pending]`: fix: protect worktree session cwd and title from overwrite

## Root Cause - Updated

**The real root cause is in `KanbanBoardState.updateSessionFromParsed()`:**

When `createSession()` creates a worktree session, it sets:
- `isWorkTree: true`
- `isWorkTreeOverridden: true` (protects from JSONL overwriting)

However, `updateSessionFromParsed()` was updating `branch` and `cwd` **without checking `isWorkTreeOverridden`**:

```swift
// BEFORE (buggy):
if let branch = parsed.branch, !branch.isEmpty {
    session.branch = branch  // Overwrites even when isWorkTreeOverridden = true
}
if let cwd = parsed.cwd {
    session.cwd = cwd  // Overwrites even when isWorkTreeOverridden = true
}
if !session.isWorkTreeOverridden {
    session.isWorkTree = parsed.isWorkTree
}
```

**Flow of the bug:**

1. Session created with `isWorkTreeOverridden = true`, `branch = ""`
2. First JSONL event (e.g., `permission-mode`) parsed → `parsed.branch = nil` or `"main"`
3. `matchNewSessionId` called with this ParsedSession
4. `updateSessionFromParsed` called → **overwrites `branch = "main"`** even though `isWorkTreeOverridden = true`!
5. Later `worktree-state` event sets `parsed.branch = worktreeName`
6. `updateSessionFromParsed` called again → but if `parsed.branch` is now `nil` (from worktree-state not having `gitBranch`), it doesn't update

**Fix Applied** in `KanbanBoardState.swift`:

```swift
// AFTER (fixed):
if !session.isWorkTreeOverridden {
    if let branch = parsed.branch, !branch.isEmpty {
        session.branch = branch
    }
    if let cwd = parsed.cwd {
        session.cwd = cwd
    }
    session.isWorkTree = parsed.isWorkTree
}
```

Now `branch` and `cwd` are protected when `isWorkTreeOverridden = true`.

## Summary of All Fixes

| File | Fix |
|------|-----|
| `JsonlWatcher.swift` | Added `if !isWorkTree` guard before `extractCWD()` to prevent `attachment` events from overwriting worktree cwd |
| `JsonlWatcher.swift` | Removed `if title == "New Session"` condition - title always set from worktreeName |
| `JsonlWatcher.swift` | Removed `originalCwd` fallback in `extractCWD()` |
| `KanbanBoardState.swift` | Added `isWorkTreeOverridden` protection for `branch`, `cwd`, and `isWorkTree` updates |

## Open Questions

1. ~~Is the `worktree-state` event being received BEFORE any `attachment` events in the JSONL parsing?~~ - Yes, confirmed
2. ~~Is `isWorkTree` correctly initialized to `false` in `ParsedSession` before parsing begins?~~ - Yes, it is
3. ~~Is the `sessionsCache` in `JsonlWatcher` causing stale data to persist across parses?~~ - No, cache is correctly maintained
