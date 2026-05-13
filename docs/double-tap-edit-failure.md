# 双击编辑功能探索失败记录

**日期：** 2026-05-03
**目标：** Task 卡片双击任意区域（除按钮外）打开编辑弹窗

## 需求

- 双击卡片标题、描述、标签等区域 → 打开编辑弹窗
- 双击 expand 按钮、session 按钮、删除按钮 → 正常执行按钮动作，不触发编辑
- 以后新加按钮时不需要特殊处理

## 原始实现

双击手势分散在两个子视图上：
- `.onTapGesture(count: 2)` 在标题 Text 上（第 32 行）
- `.onTapGesture(count: 2)` 在描述/标签 VStack 上（第 79 行）

**问题：** 点击区域太小，标题区域只覆盖文字宽度，expand 按钮周围是死区。

## 尝试过的方法

### 方法 1：把双击手势放到父 VStack 上

把 `.onTapGesture(count: 2)` 从两个子视图移到包裹所有内容的 VStack 上。

**结果：** 覆盖区域对了，但双击 expand 按钮区域时，按钮的单击动作和父视图的双击手势同时触发——既展开了卡片，又打开了编辑弹窗。

### 方法 2：把 expand 按钮移到 overlay 层

把 expand 按钮从 HStack 中移出，放到卡片级别的 `.overlay(alignment: .topTrailing)` 中。双击手势留在内容 VStack 上。

**结果：** expand 按钮正常了（overlay 层在点击层级上高于下方的 onTapGesture），但 session 面板里的按钮（resume、delete、Add Session）仍然不灵敏——它们还在内容 VStack 内部，被双击手势拦截。

### 方法 3：BlockDoubleTap 通用 modifier

创建一个 ViewModifier，意图让任何子视图包上它就能屏蔽父视图的双击：

```swift
// 尝试 A：simultaneousGesture + TapGesture
struct BlockDoubleTap: ViewModifier {
    func body(content: Content) -> some View {
        content.simultaneousGesture(
            TapGesture().onChanged { _ in }
        )
    }
}
```

**编译失败：** `Type 'TapGesture.Value' cannot conform to 'Equatable'`

```swift
// 尝试 B：onTapGesture(count: 1)
struct BlockDoubleTap: ViewModifier {
    func body(content: Content) -> some View {
        content.onTapGesture(count: 1) { }
    }
}
```

**编译通过，但运行无效：** session 按钮仍然不灵敏。`.onTapGesture(count: 1)` 并不能可靠地阻止父视图的 `.onTapGesture(count: 2)` 触发。

## 根本原因

SwiftUI 的手势系统中，`.onTapGesture(count: 2)` 放在父视图上时，会和子视图的 Button 手势产生不可靠的冲突：

1. **双击手势覆盖整个父视图区域**，包括子按钮的点击区域
2. **Button 的单击动作和父视图的双击手势是独立的手势识别器**，两者可以同时触发
3. **没有可靠的方法让子视图"吞掉"父视图的双击计数**——`simultaneousGesture`、`onTapGesture(count: 1)`、overlay 层级等方法都无法干净解决
4. **只有把按钮物理移出双击手势的视图层级**（如 overlay）才能完全避免冲突，但这对深层嵌套的按钮（如 session 面板内的 delete）不实用

## 结论

在 SwiftUI 中，不建议在包含交互子元素（Button 等）的父视图上使用 `.onTapGesture(count: 2)`。如果需要"点击空白区域触发某操作"的交互模式，应考虑：

- **右键菜单** — 不和单击/双击手势冲突
- **单击卡片空白区域** — 用 `.onTapGesture(count: 1)` 配合 `.contentShape(Rectangle())` 精确控制点击区域
- **长按手势** — `.onLongPressGesture` 和 Button 手势的冲突更小
- **把交互元素和手势区域物理分离** — 如用 overlay 放置按钮，但维护成本高

## 当前状态

已 `git checkout` 恢复到修改前的原始代码。
