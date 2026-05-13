# 终端性能对齐 Ghostty 原版实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 对齐 Ghostty 原版的 SurfaceWrapper / SurfaceRepresentable 封装模式，消除终端渲染卡顿。

**Architecture:** 逐项对比 Ghostty 原版（`SurfaceView.swift:35-160` + `:570-609`）和我们的 `ContentView.swift:283-315`，只修复差异点，不新增 Ghostty 没有的东西。

**Tech Stack:** SwiftUI, AppKit, GhosttyRuntime

---

## 差异对比表

| # | Ghostty 原版 | 我们当前 | 影响 |
|---|-------------|---------|------|
| 1 | `SurfaceRepresentable.makeOSView` 返回 `SurfaceScrollView` | 返回 `GhosttySurfaceView`（外层 NSView） | size 守卫比较的是错误的 view bounds |
| 2 | `GeometryReader` 后无 `.frame()` | 有 `.frame(width:geo.size.width, height:geo.size.height)` | 冗余布局计算，可能触发布局死循环 |
| 3 | `.id()` 不用 | `.id(activeTab.id)` 强制重建 | 每次切 tab 销毁重建视图 |
| 4 | `@ObservedObject var surfaceView` | `let surfaceView`（普通 let） | SwiftUI 无法跳过不必要的 body 计算 |
| 5 | `@FocusState private var surfaceFocus` | 缺失 | 键盘焦点无法正确路由 |
| 6 | 窗口焦点通知（didBecomeKey / didResignKey） | 缺失 | 窗口失焦时焦点状态不正确 |
| 7 | `GhosttySurfaceView` 内部创建 `SurfaceScrollView`，`SurfaceRepresentable` 也创建 → 重复 | 当前无重复，但 size 守卫比较错误 | 需要让 `SurfaceRepresentable` 统一管理 |

---

## 文件变更概览

| 文件 | 操作 | 说明 |
|------|------|------|
| `demo/Sources/GhosttyRuntime/GhosttyPublic.swift` | 修改 | 移除 scrollView 创建，暴露 inner，让 SurfaceRepresentable 管理 |
| `demo/Sources/GhosttyRuntime/Surface View/SurfaceScrollView.swift` | 修改 | 改为 public，供 GhosttyDemo 模块访问 |
| `demo/Sources/GhosttyDemo/ContentView.swift` | 修改 | 对齐 Ghostty 的 SurfaceWrapper + SurfaceRepresentable |

---

## Task 1: 让 SurfaceScrollView 对 GhosttyDemo 可见

**Why:** Ghostty 的 `SurfaceRepresentable.makeOSView` 直接返回 `SurfaceScrollView`。我们的 `SurfaceRepresentable` 在 `GhosttyDemo` 模块，而 `SurfaceScrollView` 在 `GhosttyRuntime` 模块（internal 访问级别），无法直接使用。

**Files:**
- Modify: `demo/Sources/GhosttyRuntime/Surface View/SurfaceScrollView.swift:15`

- [ ] **Step 1: 将 SurfaceScrollView 改为 public**

将第 15 行：
```swift
class SurfaceScrollView: NSView {
```

改为：
```swift
public class SurfaceScrollView: NSView {
```

- [ ] **Step 2: 编译验证**

```bash
cd /Users/hue/Documents/ghostty-kanban && cd demo && swift build 2>&1 | tail -5
```

Expected: 编译成功，无新增错误。

---

## Task 2: 重构 GhosttySurfaceView，移除内部 SurfaceScrollView

**Why:** Ghostty 的架构是 `SurfaceRepresentable` 在 `makeOSView` 中创建 `SurfaceScrollView`。当前我们的 `GhosttySurfaceView` 也创建了一个 → 如果 `SurfaceRepresentable` 也创建就会重复。需要让 `GhosttySurfaceView` 变成纯数据容器（暴露 `inner`），不管理视图层级。

**Files:**

- Modify: `demo/Sources/GhosttyRuntime/GhosttyPublic.swift:25-86`

- [ ] **Step 1: 读取当前 GhosttyPublic.swift**

```bash
cat -n /Users/hue/Documents/ghostty-kanban/demo/Sources/GhosttyRuntime/GhosttyPublic.swift
```

- [ ] **Step 2: 重写 GhosttySurfaceView**

将 `GhosttySurfaceView` 整个类（第 25-86 行）替换为：

```swift
public final class GhosttySurfaceView: NSView, ObservableObject {
    /// The inner Ghostty surface view. SurfaceRepresentable uses this
    /// to create a SurfaceScrollView (matching Ghostty's architecture).
    public let inner: Ghostty.SurfaceView

    @Published public private(set) var title: String = ""

    private var titleCancellable: Any?

    public init(_ app: ghostty_app_t) {
        inner = Ghostty.SurfaceView(app)
        super.init(frame: .zero)
        // Forward title changes
        titleCancellable = inner.$title.sink { [weak self] newTitle in
            self?.title = newTitle
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }

    public func sendText(_ text: String) {
        inner.surfaceModel?.sendText(text)
    }

    /// Send a synthetic Enter key press via the key event path.
    public func sendEnter() {
        let event = Ghostty.Input.KeyEvent(key: .enter, action: .press)
        inner.surfaceModel?.sendKeyEvent(event)
    }

    /// The underlying ghostty surface for this view.
    public var surface: ghostty_surface_t? {
        inner.surface
    }

    /// The inner NSView that can become first responder.
    public var surfaceNSView: NSView { inner }

    /// Notify the surface of focus changes.
    public func focusDidChange(_ focused: Bool) {
        inner.focusDidChange(focused)
    }
}
```

关键变化：
- 移除 `private let scrollView: SurfaceScrollView` 和 `init` 中的创建
- 移除 `addSubview(scrollView)` 和 `scrollView.autoresizingMask`
- `inner` 从 `private` 改为 `public let`
- 移除 `layout()` override（不再拥有 scrollView，autoresizing 也不需要了）

- [ ] **Step 3: 编译验证**

```bash
cd /Users/hue/Documents/ghostty-kanban && cd demo && swift build 2>&1 | tail -5
```

Expected: 编译成功。`TerminalTabManager` 中对 `surfaceView.surface`、`surfaceView.surfaceNSView`、`surfaceView.focusDidChange()`、`surfaceView.sendText()`、`surfaceView.sendEnter()` 的调用全部不受影响。

---

## Task 3: 重写 ContentView 的 SurfaceViewWrapper + SurfaceRepresentable

**Why:** 对齐 Ghostty 原版的 `SurfaceWrapper`（`SurfaceView.swift:35-160`）和 `SurfaceRepresentable`（`SurfaceView.swift:570-609`）。这是性能优化的核心改动。

**Files:**
- Modify: `demo/Sources/GhosttyDemo/ContentView.swift:36-44`（SurfaceViewWrapper 调用处）
- Modify: `demo/Sources/GhosttyDemo/ContentView.swift:283-315`（SurfaceViewWrapper + SurfaceRepresentable 定义）

- [ ] **Step 1: 移除 `.id(activeTab.id)`**

将第 40-41 行：
```swift
SurfaceViewWrapper(surfaceView: activeTab.surfaceView)
    .id(activeTab.id)  // Force recreation when tab changes
```

改为：
```swift
SurfaceViewWrapper(surfaceView: activeTab.surfaceView)
```

Ghostty 原版不用 `.id()`。`.id()` 会导致每次 tab 切换销毁重建整个视图树。

- [ ] **Step 2: 重写 SurfaceViewWrapper + SurfaceRepresentable**

将第 283-315 行（从 `// MARK: - Terminal View Wrapper` 到文件末尾的 `SurfaceRepresentable`）整体替换为：

```swift
// MARK: - Terminal View Wrapper

/// Matches Ghostty's SurfaceWrapper (SurfaceView.swift:35-160).
/// Uses @ObservedObject for SwiftUI diffing, @FocusState for keyboard
/// routing, and window focus notifications for correct focus state.
struct SurfaceViewWrapper: View {
    @ObservedObject var surfaceView: GhosttySurfaceView

    @FocusState private var surfaceFocus: Bool
    @State private var windowFocus: Bool = true

    var body: some View {
        let center = NotificationCenter.default

        GeometryReader { geo in
            #if canImport(AppKit)
            let pubBecomeKey = center.publisher(for: NSWindow.didBecomeKeyNotification)
            let pubResign = center.publisher(for: NSWindow.didResignKeyNotification)
            #endif

            SurfaceRepresentable(inner: surfaceView.inner, size: geo.size)
                .focused($surfaceFocus)
            #if canImport(AppKit)
                .onReceive(pubBecomeKey) { notification in
                    guard let window = notification.object as? NSWindow else { return }
                    guard let surfaceWindow = surfaceView.inner.window else { return }
                    windowFocus = surfaceWindow == window
                }
                .onReceive(pubResign) { notification in
                    guard let window = notification.object as? NSWindow else { return }
                    guard let surfaceWindow = surfaceView.inner.window else { return }
                    if surfaceWindow == window {
                        windowFocus = false
                    }
                }
            #endif
        }
    }
}

/// Matches Ghostty's SurfaceRepresentable (SurfaceView.swift:570-609).
/// Returns SurfaceScrollView (not the wrapper NSView) so the size guard
/// compares against the correct view bounds.
private struct SurfaceRepresentable: NSViewRepresentable {
    let inner: Ghostty.SurfaceView
    let size: CGSize

    func makeNSView(context: Context) -> SurfaceScrollView {
        SurfaceScrollView(contentSize: size, surfaceView: inner)
    }

    func updateNSView(_ scrollView: SurfaceScrollView, context: Context) {
        guard scrollView.bounds.size != size else { return }
        scrollView.needsLayout = true
    }
}
```

关键对齐点：
1. `@ObservedObject var surfaceView` → SwiftUI 可以跳过不必要的 body 计算
2. `@FocusState private var surfaceFocus` → 键盘焦点正确路由
3. `@State private var windowFocus` + 窗口通知 → Ghostty 的焦点管理模式
4. `SurfaceRepresentable` 返回 `SurfaceScrollView` → size 守卫比较正确的 view
5. 无 `.frame()` → 消除冗余布局计算
6. 无 `.id()` → 消除强制视图重建

- [ ] **Step 3: 编译验证**

```bash
cd /Users/hue/Documents/ghostty-kanban && cd demo && swift build 2>&1 | tail -5
```

Expected: 编译成功。

- [ ] **Step 4: 打包并运行验证**

```bash
cd /Users/hue/Documents/ghostty-kanban && bash demo/run.sh
```

验证清单：
- [ ] 终端能正常渲染文字
- [ ] 键盘输入正常
- [ ] Tab 切换不闪烁
- [ ] 窗口 resize 不卡顿
- [ ] 输出长命令（如 `ls -la /usr/lib`）不卡顿

---

## 验证标准

1. 终端渲染正常（文字、颜色、光标）
2. 键盘输入正常（包括特殊键、Ctrl+C 等）
3. Tab 切换流畅（不再销毁重建视图）
4. 窗口 resize 流畅
5. 输出大量内容时不卡顿
6. 焦点行为与 Ghostty 原版一致

---

## 预期改动量

- `GhosttyPublic.swift`: ~30 行修改（移除 scrollView，暴露 inner）
- `SurfaceScrollView.swift`: 1 行修改（class → public class）
- `ContentView.swift`: ~50 行修改（重写 wrapper + representable）
- 总计：~80 行，3 个文件
