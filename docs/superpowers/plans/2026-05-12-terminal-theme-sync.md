# Terminal Theme Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When the user toggles the Kanbango theme (Cmd+Shift+T), the Ghostty terminal should also switch between light and dark color schemes.

**Architecture:** Expose `ghostty_app_set_color_scheme` and `ghostty_surface_set_color_scheme` C APIs through the GhosttyRuntime public facade. When `BoardState.toggleTheme()` fires, iterate all terminal tabs and call `ghostty_surface_set_color_scheme` on each, plus `ghostty_app_set_color_scheme` on the app. This tells Ghostty's renderer which color scheme to use; if the user's Ghostty config has `theme = light:X,dark:Y`, the terminal will switch themes automatically.

**Tech Stack:** Swift, Ghostty C API (`ghostty.h`), SwiftUI, GhosttyRuntime

---

## Background: How It Works

The Ghostty C API provides two functions that are currently unused in Kanbango:

```c
void ghostty_app_set_color_scheme(ghostty_app_t, ghostty_color_scheme_e);   // ghostty.h:1098
void ghostty_surface_set_color_scheme(ghostty_surface_t, ghostty_color_scheme_e);  // ghostty.h:1120
```

Where `ghostty_color_scheme_e` is:
```c
GHOSTTY_COLOR_SCHEME_LIGHT = 0
GHOSTTY_COLOR_SCHEME_DARK = 1
```

When called, these tell Ghostty's renderer which color scheme preference to use. If the user's `~/.config/ghostty/config` has a dual-mode theme like `theme = light:Catppuccin Latte,dark:Catppuccin Mocha`, the terminal will switch between them. If they have a single theme, the color scheme change has no visible effect (the terminal stays the same).

### Data Flow

```
User presses Cmd+Shift+T
  → AppDelegate.toggleTheme()
  → BoardState.toggleTheme()  (flips isDarkMode, saves to UserDefaults)
  → NEW: syncTerminalColorScheme(isDark:tabManager:app:)
      → ghostty_app_set_color_scheme(app, .dark/.light)
      → for each tab in tabManager.tabs:
          ghostty_surface_set_color_scheme(surface, .dark/.light)
```

### Key Files and Their Roles

| File | Role |
|------|------|
| `Sources/GhosttyKit/include/ghostty.h:1098,1120` | C API declarations (already exist) |
| `Sources/GhosttyRuntime/GhosttyPublic.swift` | Public facade — needs `setColorScheme` on both `GhosttyApp` and `GhosttySurfaceView` |
| `Sources/Kanbango/TerminalTabManager.swift` | Manages tabs — needs a method to set color scheme on all surfaces |
| `Sources/Kanbango/KanbanBoardState.swift:97` | `toggleTheme()` — needs to call terminal sync after flipping `isDarkMode` |
| `Sources/Kanbango/DemoApp.swift:128` | `toggleTheme(_:)` menu action — needs to pass `tabManager` and `app` to `BoardState` |

---

### Task 1: Expose `setColorScheme` on `GhosttyApp` public facade

**Files:**
- Modify: `Sources/GhosttyRuntime/GhosttyPublic.swift:12-27`

- [ ] **Step 1: Add `setColorScheme` method to `GhosttyApp`**

Add the following method after the existing `changeFontSize` method (after line 23):

```swift
public func setColorScheme(_ scheme: ghostty_color_scheme_e) {
    guard let app = inner.app else { return }
    ghostty_app_set_color_scheme(app, scheme)
}
```

- [ ] **Step 2: Verify it compiles**

Run: `swift build 2>&1 | head -20`
Expected: No errors related to `setColorScheme` or `ghostty_app_set_color_scheme`.

- [ ] **Step 3: Commit**

```bash
git add Sources/GhosttyRuntime/GhosttyPublic.swift
git commit -m "feat: expose setColorScheme on GhosttyApp public facade"
```

---

### Task 2: Expose `setColorScheme` on `GhosttySurfaceView` public facade

**Files:**
- Modify: `Sources/GhosttyRuntime/GhosttyPublic.swift:29-76`

- [ ] **Step 1: Add `setColorScheme` method to `GhosttySurfaceView`**

Add the following method after the existing `focusDidChange` method (after line 70):

```swift
public func setColorScheme(_ scheme: ghostty_color_scheme_e) {
    guard let surface = inner.surface else { return }
    ghostty_surface_set_color_scheme(surface, scheme)
}
```

- [ ] **Step 2: Verify it compiles**

Run: `swift build 2>&1 | head -20`
Expected: No errors related to `setColorScheme` on `GhosttySurfaceView`.

- [ ] **Step 3: Commit**

```bash
git add Sources/GhosttyRuntime/GhosttyPublic.swift
git commit -m "feat: expose setColorScheme on GhosttySurfaceView public facade"
```

---

### Task 3: Add `setColorSchemeForAllTabs` to `TerminalTabManager`

**Files:**
- Modify: `Sources/Kanbango/TerminalTabManager.swift`

- [ ] **Step 1: Add the method**

Add the following method before the private `setOcclusion` method (before line 110):

```swift
func setColorSchemeForAllTabs(_ scheme: ghostty_color_scheme_e) {
    for tab in tabs {
        tab.surfaceView.setColorScheme(scheme)
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `swift build 2>&1 | head -20`
Expected: No errors.

- [ ] **Step 3: Commit**

```bash
git add Sources/Kanbango/TerminalTabManager.swift
git commit -m "feat: add setColorSchemeForAllTabs to TerminalTabManager"
```

---

### Task 4: Wire `toggleTheme` to sync terminal color scheme

**Files:**
- Modify: `Sources/Kanbango/KanbanBoardState.swift:97-100`
- Modify: `Sources/Kanbango/DemoApp.swift:128-130`

The challenge: `BoardState.toggleTheme()` currently has no reference to the terminal. The menu action in `DemoApp.swift` calls `BoardState.shared.toggleTheme()` directly. We need to also call the terminal sync.

The cleanest approach: have the menu action call both `toggleTheme()` and the terminal sync, since `AppDelegate` has access to the global `ghosttyApp` and can post a notification that `ContentView` observes.

However, the simplest approach: add a callback/delegate pattern. But even simpler — use a `NotificationCenter` notification.

- [ ] **Step 1: Add a notification for theme changes**

In `Sources/Kanbango/KanbanBoardState.swift`, add a notification name at the top (after line 7):

```swift
static let themeDidChange = Notification.Name("kanbanThemeDidChange")
```

- [ ] **Step 2: Post the notification in `toggleTheme()`**

In `Sources/Kanbango/KanbanBoardState.swift`, modify `toggleTheme()` (lines 97-100) to post the notification:

```swift
func toggleTheme() {
    isDarkMode.toggle()
    UserDefaults.standard.set(isDarkMode, forKey: "kanban-dark-mode")
    NotificationCenter.default.post(name: Self.themeDidChange, object: nil)
}
```

- [ ] **Step 3: Observe the notification in `ContentView` and sync terminal**

In `Sources/Kanbango/ContentView.swift`, add an `.onReceive` modifier to the body. Find the `.onAppear` block (around line 53) and add this modifier before it:

```swift
.onReceive(NotificationCenter.default.publisher(for: BoardState.themeDidChange)) { _ in
    let scheme: ghostty_color_scheme_e = boardState.isDarkMode ? GHOSTTY_COLOR_SCHEME_DARK : GHOSTTY_COLOR_SCHEME_LIGHT
    ghostty.setColorScheme(scheme)
    tabManager.setColorSchemeForAllTabs(scheme)
}
```

- [ ] **Step 4: Verify it compiles**

Run: `swift build 2>&1 | head -20`
Expected: No errors.

- [ ] **Step 5: Commit**

```bash
git add Sources/Kanbango/KanbanBoardState.swift Sources/Kanbango/ContentView.swift
git commit -m "feat: sync terminal color scheme when theme toggles"
```

---

### Task 5: Build, run, and manually test

**Files:**
- No file changes

- [ ] **Step 1: Build and run the app**

Run: `bash run.sh`

- [ ] **Step 2: Test with dual-theme Ghostty config**

If the user's `~/.config/ghostty/config` has a dual-mode theme (e.g., `theme = light:Catppuccin Latte,dark:Catppuccin Mocha`):
1. Press Cmd+Shift+T to toggle to dark mode → terminal should switch to dark theme
2. Press Cmd+Shift+T again to toggle to light mode → terminal should switch to light theme

If the user has a single theme, the terminal won't change — this is expected behavior.

- [ ] **Step 3: Test with multiple tabs**

1. Open a second terminal tab (click "+" in tab bar)
2. Toggle theme → both tabs should switch color scheme

- [ ] **Step 4: Test new tab inherits current theme**

1. With dark mode active, create a new tab
2. The new tab should open with the dark color scheme

- [ ] **Step 5: Commit (if any fixes needed)**

```bash
git add -A
git commit -m "fix: address theme sync issues found during testing"
```

---

### Task 6: Ensure new tabs inherit the current color scheme

**Files:**
- Modify: `Sources/Kanbango/TerminalTabManager.swift:22-58` (the `newTab` method)

When a new tab is created, it should inherit the current theme state.

- [ ] **Step 1: Add color scheme to `newTab`**

In `TerminalTabManager.newTab(app:workspacePath:)`, after the surface is created and before the `sendText` call (around line 45), add:

```swift
// Apply current color scheme to new tab
let scheme: ghostty_color_scheme_e = BoardState.shared.isDarkMode ? GHOSTTY_COLOR_SCHEME_DARK : GHOSTTY_COLOR_SCHEME_LIGHT
sv.setColorScheme(scheme)
```

- [ ] **Step 2: Verify it compiles**

Run: `swift build 2>&1 | head -20`
Expected: No errors.

- [ ] **Step 3: Commit**

```bash
git add Sources/Kanbango/TerminalTabManager.swift
git commit -m "feat: new terminal tabs inherit current color scheme"
```

---

### Task 7: Build and run final verification

- [ ] **Step 1: Full build and run**

Run: `bash run.sh`

- [ ] **Step 2: End-to-end test**

1. Launch app → terminal should use whatever Ghostty config says
2. Cmd+Shift+T → terminal color scheme switches
3. Cmd+Shift+T again → terminal switches back
4. Open new tab → inherits current color scheme
5. Switch between tabs → color scheme stays consistent

- [ ] **Step 3: Final commit**

```bash
git add -A
git commit -m "feat: complete terminal theme sync with Kanbango theme toggle"
```
