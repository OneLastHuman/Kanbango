# Tab Single-Click Fix Implementation Plan

**Goal:** Fix tab switching so single-click works instead of requiring double-click.

**Architecture:** Add `.allowsHitTesting(false)` to `TabMiddleClickView` background so click events pass through to the underlying `Button`. Middle-click handling via `NSEvent` monitor remains unaffected.

**Tech Stack:** SwiftUI, AppKit event monitoring

---

### Task 1: Fix TabButton background hit testing

**Files:**
- Modify: `demo/Sources/GhosttyDemo/ContentView.swift:174`

- [ ] **Step 1: Add allowsHitTesting(false) to TabMiddleClickView**

Change line 174 from:
```swift
.background(TabMiddleClickView(onClose: onClose))
```
To:
```swift
.background(TabMiddleClickView(onClose: onClose).allowsHitTesting(false))
```

- [ ] **Step 2: Build and test**

Run: `bash demo/run.sh`
Expected: Compiles successfully, app launches, single-click on tabs switches active tab

- [ ] **Step 3: Verify middle-click close still works**

Click middle mouse button on a tab.
Expected: Tab closes (if more than one tab exists)

- [ ] **Step 4: Commit**

```bash
git add demo/Sources/GhosttyDemo/ContentView.swift
git commit -m "fix: allow single-click tab switching by disabling hit testing on background view"
```

---

### Task 2 (Fallback): Alternative implementation if Task 1 fails

If `.allowsHitTesting(false)` does not resolve the issue, implement middle-click detection using SwiftUI gesture modifier instead of NSView background.

**Files:**
- Modify: `demo/Sources/GhosttyDemo/ContentView.swift:146-176`

- [ ] **Step 1: Replace TabMiddleClickView background with SwiftUI gesture**

Change `TabButton` body to use `.simultaneousGesture(LongPressGesture().simultaneously(with: DragGesture()))` detecting 3-finger tap or implement `.onTapGesture(count: 2)` pattern adapted for middle-click simulation.

Note: This is a fallback path. Only proceed if Task 1 verification fails.
