# Ghostty 终端主题热更新尝试记录

日期：2026-05-04

## 目标

在不重启 App、不销毁终端会话的前提下，实现终端主题三态切换（Default / Light / Dark）。

## 尝试的方案

### 方案 A：独立配置文件 + overlay 加载

**做法：**
1. 在 `~/Library/Application Support/KanbanBoard/config.ghostty` 维护自己的配置文件
2. 切换主题时，写入 `theme = Apple System Colors Light`（或 Dark），Default 模式写空文件
3. 加载配置时，先调 `ghostty_config_load_default_files()` 获取用户基础配置（字体、透明度等），再调 `ghostty_config_load_file()` 叠加我们的 theme 文件
4. 用 `ghostty_app_update_config()` 更新 app 级配置
5. 遍历每个 tab，调 `ghostty_surface_update_config()` 更新单个 surface

**修改的文件：**
- `Sources/GhosttyRuntime/Ghostty.Config.swift` — 新增 `Config(withOverlay:)` 和 `loadConfig(withOverlay:finalize:)` 方法
- `Sources/GhosttyRuntime/GhosttyPublic.swift` — 新增 `GhosttyApp.reloadConfig(withOverlay:)` 和 `GhosttySurfaceView.updateConfig(withOverlay:)` 公开方法
- `Sources/GhosttyDemo/GhosttyThemeManager.swift` — 新建，管理配置文件读写和主题应用
- `Sources/GhosttyDemo/KanbanBoardState.swift` — 新增 `themeMode` 属性，`toggleTheme()` 改为三态循环
- `Sources/GhosttyDemo/KanbanView.swift` — 按钮图标改为三态循环
- `Sources/GhosttyDemo/ContentView.swift` — 监听 `themeMode` 变化，调用 `themeManager.applyTheme()`

**结果：** 编译通过，运行正常，但切换主题后终端界面没有任何变化。

## 失败原因分析

### 核心问题：`ghostty_app_update_config` 对 theme 不生效

Ghostty 的配置热更新机制链路：

```
ghostty_app_update_config(app, newConfig)
  → 触发 configChange 回调
    → 发送 ghosttyConfigDidChange 通知
      → 各 SurfaceView 收到通知
        → 更新 DerivedConfig（包含 backgroundColor 等）
```

`DerivedConfig` 通过 `ghostty_config_get(config, &color, "background", ...)` 读取背景色。当 config 中设置了 `theme` 时，Ghostty C 库应该根据 theme 解析出对应的背景色。

**但实际行为是：** `ghostty_app_update_config` 虽然被调用了，`configChange` 回调也触发了，但 `DerivedConfig` 中的 `backgroundColor` 没有变化。这说明 Ghostty C 库在 `ghostty_app_update_config` 路径下，**不会重新解析 theme 并更新派生颜色值**。

### 为什么单独调 `ghostty_surface_update_config` 也不行

`ghostty_surface_update_config` 是 surface 级别的配置更新，但：
1. 它不触发 `configChange` 通知（通知是 app 级别的）
2. 即使 C 库内部更新了 surface 的 config，Swift 侧的 `DerivedConfig` 不会自动重新读取
3. 渲染循环可能不会因为 config 变化而重绘

### 为什么原生 Ghostty 能直接设置主题

原生 Ghostty 应用在以下场景会完整重建 surface：
- 新建窗口/标签页
- 重启应用

这些场景下 `Ghostty.App.init()` 被调用，`ghostty_config_load_default_files()` 加载完整配置（包含 theme），然后 `ghostty_app_new()` 创建 app 时传入完整 config。**theme 在这个路径下是被正确解析的。**

而在我们的嵌入场景中，app 已经创建好了，我们只是试图"热更新"配置。Ghostty 的热更新机制对部分配置项（如字体大小、快捷键）有效，但对 **theme 这种需要重新解析整个调色板的配置项不生效**。

## 结论

Ghostty 的 `theme` 配置项**不适合在运行时热更新**。它需要在 surface 创建时就被正确解析。任何试图在 surface 已经创建后修改 theme 的方法，都受限于 Ghostty C 库的内部实现。

## 可行的替代方案

1. **重建 surface（不重启 app）** — 保留 tab/session 元数据，销毁旧 surface view，创建新的。新 surface 会在创建时读取最新 config（包含 theme）。代价是运行中的 shell 进程会被终止。
2. **只 rebuild 当前活跃 tab** — 切主题时只重建当前终端，其他 tab 在切换到时再重建。影响范围最小。
3. **重启 app** — 最简单但体验最差。
