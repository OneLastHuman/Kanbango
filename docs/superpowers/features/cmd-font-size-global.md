# Cmd+/Cmd-/Cmd+0 全局字体缩放

## 背景

Ghostty 终端通过 `GhosttySurfaceView.performKeyEquivalent` 拦截了 Cmd+/Cmd-，当终端聚焦时这些快捷键被消耗，不会传播到 NSMenu 或其他 UI 层。

## 实现方案

### 1. Local Monitor 拦截

使用 `NSEvent.addLocalMonitorForEvents` 而非 global monitor。Local monitor 在视图处理完事件后仍能看到事件（即使已被消费），确保无论焦点在哪都能捕获快捷键。

```swift
// DemoApp.swift
fontSizeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
    guard event.modifierFlags.contains(.command) else { return event }
    switch event.charactersIgnoringModifiers {
    case "+", "=":
        FontSizeManager.shared.increase()
    case "-":
        FontSizeManager.shared.decrease()
    case "0":
        FontSizeManager.shared.reset()
    default:
        return event
    }
    return nil  // 消费事件，防止 GhosttySurfaceView 重复处理
}
```

### 2. FontSizeManager 改造

- 添加 `onTerminalFontSizeChange` 回调
- `increase()`/`decrease()`/`reset()` 调用回调通知终端字体同步
- `baseFontSize` 持久化到 UserDefaults

```swift
// FontSizeManager.swift
var onTerminalFontSizeChange: ((Ghostty.App.FontSizeModification) -> Void)?

func increase() {
    let new = baseFontSize + step
    if new <= maxFontSize {
        baseFontSize = new
        onTerminalFontSizeChange?(.increase(1))
    }
}
```

### 3. ContentView 绑定回调

```swift
// ContentView.swift onAppear
fontManager.onTerminalFontSizeChange = { [weak tabManager, weak ghostty] change in
    guard let tabManager = tabManager,
          let ghostty = ghostty,
          let surface = tabManager.activeTab?.surfaceView.surface else { return }
    ghostty.changeFontSize(surface: surface, change)
}
```

## 文件变更

| 文件 | 变更 |
|------|------|
| `DemoApp.swift` | 添加 local monitor 拦截键盘事件 |
| `FontSizeManager.swift` | 添加 `onTerminalFontSizeChange` 回调 + UserDefaults 持久化 |
| `ContentView.swift` | 在 onAppear 设置 terminal font sync callback |
| `GhosttyPublic.swift` | 添加 `changeFontSize` 公共方法 |
| `Ghostty.App.swift` | `FontSizeModification` 改为 public |
| `GhosttyPackageMeta.swift` | `Ghostty` enum 改为 public |

## 行为

- **Cmd+0**: 重置为 15pt
- **Cmd+= 或 Cmd++**: 字号 +1pt（最大 30pt）
- **Cmd+-**: 字号 -1pt（最小 10pt）

所有快捷键同时调节 UI（看板、标签栏、模态框）和终端字体，不受焦点位置影响。
