# NSSplitView 替换 HSplitView 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [`) syntax for tracking.

**Goal:** 将 ContentView 中的 SwiftUI `HSplitView` 替换为 AppKit 原生 `NSSplitView`，消除 resize 时的 SwiftUI 布局级联开销，解决终端长文本 resize 卡顿问题。

**Architecture:** 用 `NSViewRepresentable` 包装 `NSSplitView`，左面板 (`KanbanView`) 和右面板 (终端 tab bar + terminal) 各自用 `NSHostingView` 嵌入。`NSSplitView` 直接管理 resize，不经过 SwiftUI 的 `GeometryReader` 布局链路。

**Tech Stack:** Swift, SwiftUI, AppKit (NSSplitView, NSHostingView)

---

## 文件变更清单

| 文件 | 操作 | 说明 |
|------|------|------|
| `Sources/GhosttyDemo/ContentView.swift` | 修改 | 移除 `HSplitView`，替换为 `AppSplitView` (NSViewRepresentable) |
| `Sources/GhosttyDemo/AppSplitView.swift` | 新建 | `NSSplitView` 的 `NSViewRepresentable` 包装器 |

---

### Task 1: 创建 AppSplitView 组件

**Files:**
- Create: `Sources/GhosttyDemo/AppSplitView.swift`

新建一个 `NSViewRepresentable`，内部使用 `NSSplitView` 管理左右两个面板。

- [ ] **Step 1: 创建 AppSplitView.swift**

```swift
import SwiftUI
import AppKit

/// AppKit NSSplitView 的 SwiftUI 包装器。
/// 直接使用 NSSplitView 管理左右面板的 resize，
/// 避免 SwiftUI HSplitView 的 GeometryReader 布局级联开销。
struct AppSplitView<Left: View, Right: View>: NSViewRepresentable {
    let leftView: Left
    let rightView: Right
    let leftMinWidth: CGFloat
    let leftIdealWidth: CGFloat
    let rightMinWidth: CGFloat

    func makeNSView(context: Context) -> NSSplitView {
        let splitView = NSSplitView()
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.autosaveName = "AppSplitView"
        splitView.delegate = context.coordinator

        // 左面板：用 NSHostingView 包装 SwiftUI 视图
        let leftHosting = NSHostingView(rootView: leftView)
        leftHosting.translatesAutoresizingMaskIntoConstraints = false
        splitView.addSubview(leftHosting)

        // 右面板：用 NSHostingView 包装 SwiftUI 视图
        let rightHosting = NSHostingView(rootView: rightView)
        rightHosting.translatesAutoresizingMaskIntoConstraints = false
        splitView.addSubview(rightHosting)

        context.coordinator.leftHosting = leftHosting
        context.coordinator.rightHosting = rightHosting

        return splitView
    }

    func updateNSView(_ splitView: NSSplitView, context: Context) {
        // 更新左右面板的 SwiftUI 内容
        context.coordinator.leftHosting?.rootView = leftView
        context.coordinator.rightHosting?.rootView = rightView
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            leftMinWidth: leftMinWidth,
            leftIdealWidth: leftIdealWidth,
            rightMinWidth: rightMinWidth
        )
    }

    class Coordinator: NSObject, NSSplitViewDelegate {
        let leftMinWidth: CGFloat
        let leftIdealWidth: CGFloat
        let rightMinWidth: CGFloat

        weak var leftHosting: NSHostingView<Left>?
        weak var rightHosting: NSHostingView<Right>?

        init(leftMinWidth: CGFloat, leftIdealWidth: CGFloat, rightMinWidth: CGFloat) {
            self.leftMinWidth = leftMinWidth
            self.leftIdealWidth = leftIdealWidth
            self.rightMinWidth = rightMinWidth
        }

        // MARK: - NSSplitViewDelegate

        func splitView(_ splitView: NSSplitView,
                       constrainMinProposedPosition proposedMinimumPosition: CGFloat,
                       ofSubviewAt dividerIndex: Int) -> CGFloat {
            return leftMinWidth
        }

        func splitView(_ splitView: NSSplitView,
                       constrainMaxProposedPosition proposedMaximumPosition: CGFloat,
                       ofSubviewAt dividerIndex: Int) -> CGFloat {
            return splitView.bounds.width - rightMinWidth
        }

        func splitView(_ splitView: NSSplitView
                       shouldAdjustSizeOfSubview view: NSView) -> Bool {
            // 左面板不自动调整大小（保持用户设定的宽度）
            // 右面板自动填充剩余空间
            if view === leftHosting {
                return false
            }
            return true
        }
    }
}
```

- [ ] **Step 2: 验证编译通过**

Run: `swift build -c release 2>&1 | tail -3`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/GhosttyDemo/AppSplitView.swift
git commit -m "feat: add AppSplitView (NSSplitView wrapper for SwiftUI)"
```

---

### Task 2: 修改 ContentView 使用 AppSplitView

**Files:**
- Modify: `Sources/GhosttyDemo/ContentView.swift:16-48`

将 `HSplitView` 替换为 `AppSplitView`，保持所有功能不变。

- [ ] **Step 1: 替换 HSplitView 为 AppSplitView**

将 `ContentView` 的 `body` 中的 `HSplitView { ... }` 块替换为 `AppSplitView`：

**旧代码 (行 16-48):**
```swift
var body: some View {
    HSplitView {
        KanbanView(
            boardState: boardState,
            sessionManager: sessionManager,
            tabManager: tabManager,
            ghosttyApp: ghostty.app!
        )
        .frame(minWidth: Status.columnMinWidth + Status.columnHPadding,
               idealWidth: Status.columnMinWidth * 1.5 + Status.columnHPadding)
        .layoutPriority(0)

        // Right: tab bar + terminal
        VStack(spacing: 0) {
            // Tab Bar (hidden when only one tab)
            if tabManager.showTabBar {
                TabBarView(tabManager: tabManager, sessionManager: sessionManager)
                    .environmentObject(boardState)
            }

            // Terminal area (only render active tab to save GPU)
            ZStack {
                Color.black
                if let activeTab = tabManager.activeTab {
                    SurfaceViewWrapper(surfaceView: activeTab.surfaceView)
                        .id(activeTab.id)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(minWidth: 400, idealWidth: 600)
        .layoutPriority(1)
    }
    .frame(minWidth: 900, minHeight: 500)
```

**新代码:**
```swift
var body: some View {
    AppSplitView(
        leftView: KanbanView(
            boardState: boardState,
            sessionManager: sessionManager,
            tabManager: tabManager,
            ghosttyApp: ghostty.app!
        )
        .environment(\.themeColors, ThemeColors.colors(isDark: boardState.isDarkMode))
        .preferredColorScheme(boardState.isDarkMode ? .dark : .light),

        rightView: TerminalPanel(
            tabManager: tabManager,
            sessionManager: sessionManager,
            boardState: boardState
        ),

        leftMinWidth: Status.columnMinWidth + Status.columnHPadding,
        leftIdealWidth: Status.columnMinWidth * 1.5 + Status.columnHPadding,
        rightMinWidth: 400
    )
    .frame(minWidth: 900, minHeight: 500)
```

- [ ] **Step 2: 添加 TerminalPanel 辅助视图**

在 `ContentView.swift` 中（`SurfaceViewWrapper` 之前）添加一个 `TerminalPanel` 视图，把右侧面板的逻辑封装起来：

```swift
/// 右侧终端面板：tab bar + terminal surface
private struct TerminalPanel: View {
    @ObservedObject var tabManager: TerminalTabManager
    @ObservedObject var sessionManager: SessionManager
    @ObservedObject var boardState: BoardState

    var body: some View {
        VStack(spacing: 0) {
            if tabManager.showTabBar {
                TabBarView(tabManager: tabManager, sessionManager: sessionManager)
                    .environmentObject(boardState)
            }

            ZStack {
                Color.black
                if let activeTab = tabManager.activeTab {
                    SurfaceViewWrapper(surfaceView: activeTab.surfaceView)
                        .id(activeTab.id)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }
}
```

- [ ] **Step 3: 验证编译通过**

Run: `swift build -c release 2>&1 | tail -3`
Expected: `Build complete!`

- [ ] **Step 4: Commit**

```bash
git add Sources/GhosttyDemo/ContentView.swift
git commit -m "feat: replace HSplitView with AppSplitView for better resize perf"
```

---

### Task 3: 运行测试

- [ ] **Step 1: 打包并启动**

Run: `bash run.sh`
Expected: 应用正常启动，左右分栏显示

- [ ] **Step 2: 验证功能**

确认以下功能正常：
1. 左侧看板正常显示任务卡片
2. 右侧终端正常显示
3. 拖拽分隔条可以调整左右比例
4. 终端内输入命令正常
5. 切换 tab 正常
6. 拖拽分隔条时终端无明显卡顿（特别是终端内有长文本时）

- [ ] **Step 3: 如有问题，修复并 commit**
