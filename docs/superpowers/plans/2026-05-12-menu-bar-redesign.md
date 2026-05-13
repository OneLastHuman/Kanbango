# Menu Bar Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan.

**Goal:** 将"打开工作区"和"切换主题"从工具栏移到 macOS 菜单栏

**Architecture:** 在 DemoApp.swift 的 setupMenuBar() 中添加 Project 菜单，在 Kanbango App Menu 中添加 Toggle Theme 菜单项

**Tech Stack:** AppKit NSMenu, SwiftUI

---

## Task 1: 添加 Project 菜单（Open Workspace）

**Files:**
- Modify: `Sources/Kanbango/DemoApp.swift:69-106`

- [ ] **Step 1: 修改 setupMenuBar() 添加 Project 菜单**

在 `NSApp.mainMenu = mainMenu` 之前添加 Project 菜单：

```swift
// Project menu
let projectMenuItem = NSMenuItem()
mainMenu.addItem(projectMenuItem)
let projectMenu = NSMenu(title: "Project")
projectMenuItem.submenu = projectMenu
projectMenu.addItem(withTitle: "Open Workspace...",
                    action: #selector(openWorkspace(_:)),
                    keyEquivalent: "o")
```

- [ ] **Step 2: 添加 openWorkspace 方法**

```swift
@objc private func openWorkspace(_ sender: Any?) {
    boardState.selectWorkspace()
}
```

需要先声明 boardState 属性。在 AppDelegate 类中添加：

```swift
private var boardState: BoardState { BoardState.shared }
```

- [ ] **Step 3: 提交**

```bash
git add Sources/Kanbango/DemoApp.swift
git commit -m "feat: add Project menu with Open Workspace (⌘O)"
```

---

## Task 2: 添加 Toggle Theme 到 App Menu

**Files:**
- Modify: `Sources/Kanbango/DemoApp.swift`

- [ ] **Step 1: 在 App Menu 中添加 Toggle Theme**

在 appMenu 的 "Quit Kanbango" 之前添加：

```swift
appMenu.addItem(NSMenuItem.separator())
appMenu.addItem(withTitle: "Toggle Theme",
                action: #selector(toggleTheme(_:)),
                keyEquivalent: "t")
appMenu.addItem(NSMenuItem.separator())  // 保持 separator 在 Quit 上方
```

修改 keyEquivalent 为空字符串 ""，并添加 shift 修饰键。

- [ ] **Step 2: 修改 keyEquivalent 和添加修饰键**

由于 ⌘⇧T 需要同时检测 shift 修饰键，修改菜单项添加：

```swift
if let menuItem = appMenu.items.last {
    menuItem.keyEquivalentModifierMask = [.command, .shift]
}
```

或者在添加时直接设置：

```swift
let toggleThemeItem = NSMenuItem(title: "Toggle Theme",
                                  action: #selector(toggleTheme(_:)),
                                  keyEquivalent: "")
toggleThemeItem.keyEquivalentModifierMask = [.command, .shift]
appMenu.addItem(toggleThemeItem)
```

- [ ] **Step 3: 添加 toggleTheme 方法**

```swift
@objc private func toggleTheme(_ sender: Any?) {
    boardState.toggleTheme()
}
```

- [ ] **Step 4: 提交**

```bash
git add Sources/Kanbango/DemoApp.swift
git commit -m "feat: add Toggle Theme menu item (⌘⇧T)"
```

---

## Task 3: 移除 KanbanToolbar 中的按钮

**Files:**
- Modify: `Sources/Kanbango/ContentView.swift:413-441`

- [ ] **Step 1: 简化 KanbanToolbar**

移除文件夹和主题切换按钮，只保留新建任务：

```swift
HStack {
    Spacer()
    Button(action: { showNewTaskModal = true }) {
        Image(systemName: "plus")
    }
}
```

- [ ] **Step 2: 提交**

```bash
git add Sources/Kanbango/ContentView.swift
git commit -m "chore: remove folder/theme buttons from toolbar"
```

---

## Task 4: 验证构建

- [ ] **Step 1: 运行构建**

```bash
swift build
```

- [ ] **Step 2: 如构建成功，测试功能**

运行 app 并验证：
- Project 菜单 → Open Workspace... 可点击并打开文件夹选择
- Kanbango 菜单 → Toggle Theme 可点击并切换主题
- 工具栏只剩新建任务按钮
