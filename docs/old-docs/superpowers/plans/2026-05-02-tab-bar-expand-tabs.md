# Tab Bar Expand Tabs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 Tab 栏的 tab 均分整个宽度，像 Ghostty 的 `expand-tabs: true` 那样。

**Architecture:** 修改 `ContentView.swift` 中的 `TabBarView`，使用 SwiftUI 的 `frame(maxWidth: .infinity)` 配合 `HStack(spacing: 0)` 让每个 tab 均分可用空间。

**Tech Stack:** SwiftUI

---

## 文件变更

| 文件 | 变更 |
|------|------|
| `demo/Sources/GhosttyDemo/ContentView.swift:89-131` | 修改 `TabBarView` 和 `TabButton` 实现均分宽度 |

---

## Task 1: 修改 TabBarView 实现均分宽度

**Files:**
- Modify: `demo/Sources/GhosttyDemo/ContentView.swift:89-131`

- [ ] **Step 1: 读取当前 TabBarView 实现**

确认当前 `TabBarView` 的完整代码，了解现有结构。

- [ ] **Step 2: 修改 TabBarView - 使用 `frame(maxWidth: .infinity)` 均分宽度**

将 `TabBarView` 中的:
```swift
HStack(spacing: 2) {
    ForEach(tabManager.tabs) { tab in
        TabButton(...)
    }
    // + button
}
```

改为使用 `HStack(spacing: 0)` 并给每个 tab 设置 `frame(maxWidth: .infinity)`:

```swift
HStack(spacing: 0) {
    ForEach(tabManager.tabs) { tab in
        TabButton(
            title: tab.title,
            isActive: tab.id == tabManager.activeTabID,
            canClose: tabManager.tabs.count > 1,
            onSelect: { tabManager.selectTab(id: tab.id) },
            onClose: {
                tabManager.closeTab(id: tab.id)
                sessionManager.unlinkTab(tabID: tab.id)
            }
        )
        .frame(maxWidth: .infinity)  // 关键：让每个 tab 均分宽度
    }

    Button(action: {
        if let app = ghostty.app {
            tabManager.newTab(app: app, workspacePath: boardState.workspacePath)
        }
    }) {
        Image(systemName: "plus")
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
    }
    .buttonStyle(.plain)
    .help("New Tab")
}
.padding(.horizontal, 4)
```

- [ ] **Step 3: 修改 TabButton - 适应等宽布局**

`TabButton` 需要能够在其父元素给定的最大宽度内居中显示文字，并截断过长的标题。

修改 `TabButton` 的 body:
```swift
var body: some View {
    HStack(spacing: 4) {
        Button(action: onSelect) {
            Text(title)
                .font(.system(size: 11))
                .lineLimit(1)
                .truncationMode(.middle)  // 中间截断，避免 title 过长时close按钮被挤走
        }
        .buttonStyle(.plain)

        if canClose {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
            }
            .buttonStyle(.plain)
        }
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 4)
    .frame(maxWidth: .infinity)  // 占据父元素给的全部宽度
    .background(isActive ? Color.accentColor.opacity(0.15) : Color.clear)
    .cornerRadius(4)
    .background(TabMiddleClickView(onClose: onClose))
}
```

- [ ] **Step 4: 测试**

运行 `bash demo/run.sh` 编译并启动 app，验证：
1. 多个 tab 时，每个 tab 均分整个 tab 栏宽度
2. 每个 tab 内的文字居中显示
3. 新增 tab 后宽度重新均分
4. 关闭 tab 后剩余 tab 宽度重新均分
5. 中键点击可以关闭 tab

- [ ] **Step 5: 提交**

```bash
git add demo/Sources/GhosttyDemo/ContentView.swift
git commit -m "feat: make tabs expand to fill tab bar width like Ghostty's expand-tabs"
```

---

## Task 2 (可选): 添加 Tab 拖拽重排

**Files:**
- Modify: `demo/Sources/GhosttyDemo/ContentView.swift`
- Modify: `demo/Sources/GhosttyDemo/TerminalTabManager.swift`

- [ ] **Step 1: 添加 tab 移动方法到 TerminalTabManager**

在 `TerminalTabManager` 中添加:
```swift
func moveTab(fromIndex: Int, toIndex: Int) {
    guard fromIndex != toIndex,
          fromIndex >= 0, fromIndex < tabs.count,
          toIndex >= 0, toIndex < tabs.count else { return }
    let tab = tabs.remove(at: fromIndex)
    tabs.insert(tab, at: toIndex)
}
```

- [ ] **Step 2: 在 TabBarView 中使用 `.draggable()` 和 `.dropDestination()`**

给每个 TabButton 添加拖拽逻辑...

- [ ] **Step 3: 测试**

验证 tab 拖拽后能正确重排。

- [ ] **Step 4: 提交**

---

## 验证清单

- [ ] 单个 tab 时占满整个 tab 栏
- [ ] 多个 tab 时均分宽度
- [ ] 新增 tab 宽度重新均分
- [ ] 关闭 tab 宽度重新均分
- [ ] 文字过长时正确截断
- [ ] 中键点击关闭 tab 正常
