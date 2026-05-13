# Menu Bar Redesign Design

## 概述

将"打开工作区"和"切换主题"从看板工具栏移到 macOS 菜单栏，提升界面简洁性。

## 目标

- 工具栏只保留"新建任务"按钮
- 应用级操作移到系统菜单栏，符合 macOS 交互惯例

## 菜单设计

| 菜单 | 菜单项 | 动作 | 快捷键 |
|------|--------|------|--------|
| **Project** | Open Workspace... | `boardState.selectWorkspace()` | ⌘O |
| **Kanbango** | Toggle Theme | `boardState.toggleTheme()` | ⌘⇧T |

### 菜单结构

```
[Kanbango] [Project] [Edit] [Window]
```

- **Project 菜单**：新增独立菜单，包含"打开工作区"
- **Kanbango 菜单**：在现有 App Menu 中添加"切换主题"

## 修改文件

- `Sources/Kanbango/DemoApp.swift` — `setupMenuBar()` 方法

## 实现步骤

1. 在 `setupMenuBar()` 中创建 Project Menu（⌘O）
2. 在 Kanbango App Menu 中添加 Toggle Theme 菜单项（⌘⇧T）
3. 从 `KanbanToolbar` 中移除对应的两个按钮
4. 测试验证功能正常

## 验证

- 菜单项可点击，功能正常
- 快捷键有效
- 工具栏只显示新建任务按钮
