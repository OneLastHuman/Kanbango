# Ghostty 终端主题三态切换方案（失败记录）

日期：2026-05-04

## 背景

用户希望在看板应用中实现终端主题的三态切换：
- **日间** → `theme = Apple System Colors Light`
- **夜间** → `theme = Apple System Colors`
- **默认** → 不设置 theme，读取系统 Ghostty 的默认配置

需求还包括：
- 按钮图标三态循环：☀️ → 🌙 → 🎨
- Ghostty config 的 `font-size` 改为 16
- 看板 UI 配色同步切换（这个已实现，基于 `isDarkMode`）

## 已验证的事实

1. **Ghostty 配置文件位置：** `~/Library/Application Support/com.mitchellh.ghostty/config.ghostty`
2. **主题文件位置：** `/Applications/Ghostty.app/Contents/Resources/ghostty/themes/`（463 个主题）
3. **配置加载时机：** `Ghostty.App` 在 `init` 时通过 `ghostty_config_load_default_files()` 加载配置，**之后不再重新读取文件**
4. **热重载机制存在但受限：**
   - `Ghostty.App.reloadConfig()` 调用 `ghostty_app_update_config()` 重新加载配置
   - Surface views 监听 `ghosttyConfigDidChange` 通知并更新 `DerivedConfig`
   - **但是：** `ghostty_app_update_config` 可能不会为 `theme` 变更触发回调（仅对部分配置项生效）

## 尝试过的方案

### 方案 1：修改 config 文件 + reloadConfig（失败）

**做法：**
1. 在 `BoardState.toggleTheme()` 中修改 `config.ghostty` 的 `theme` 行
2. 调用 `ghosttyApp?.reloadConfig()` 让 Ghostty 重新加载配置

**结果：** config 文件被正确修改（验证了文件内容），但终端主题没有变化。

**原因分析：**
- `reloadConfig()` 内部调用 `Config(at: nil)` → `ghostty_config_load_default_files()` 重新加载配置文件
- 然后调用 `ghostty_app_update_config(app, newConfig.config!)` 更新应用配置
- 但 `ghostty_app_update_config` 对 `theme` 属性的变更**可能不触发** `configChange` 回调
- Surface views 的 `DerivedConfig` 不会更新，终端颜色不变

### 方案 2：修改 config 文件 + 重启应用（可用但体验差）

**做法：**
1. 修改 `config.ghostty` 的 `theme` 行
2. 启动新应用实例
3. 旧实例自动退出

**结果：** 主题能切换，但每次切换都要重启应用，用户体验差。

## 技术细节

### Ghostty 配置加载链路

```
Ghostty.App.init(configPath: nil)
  → Config(at: nil)
    → ghostty_config_new()
    → ghostty_config_load_default_files(cfg)  // 只在 init 时调用一次
    → ghostty_config_finalize(cfg)
  → ghostty_app_update_config(app, config)    // 应用配置到 app
```

### Surface 视图的配置更新

```
SurfaceView.init()
  → DerivedConfig(appDelegate.ghostty.config)  // 从 app config 快照

NotificationCenter: ghosttyConfigDidChange
  → ghosttyConfigDidChange(_:) 
    → self.derivedConfig = DerivedConfig(config)  // 重新快照
```

### 关键 C API

| 函数 | 作用 |
|------|------|
| `ghostty_config_load_default_files(cfg)` | 从默认路径加载配置文件 |
| `ghostty_config_load_file(cfg, path)` | 从指定路径加载配置文件 |
| `ghostty_app_update_config(app, config)` | 将新配置应用到 app |
| `ghostty_config_get(config, &color, key, len)` | 读取单个配置项 |

## 可能的解决方向

1. **深入研究 `ghostty_app_update_config` 的行为** — 确认它是否对 `theme` 触发回调，可能需要查看 Ghostty 源码（libghostty C 代码）
2. **直接调用 `ghostty_config_load_file` 重新加载** — 绕过 `reloadConfig`，手动创建新 config 并加载特定文件
3. **在 `DerivedConfig` 中直接读取 theme** — 不依赖通知机制，主动轮询或在渲染时重新读取
4. **放弃运行时切换** — 接受重启应用的方案，优化重启体验（如保留窗口位置、自动恢复终端状态）
5. **不使用 `theme` 配置项** — 改为直接设置 `background`、`foreground` 等颜色值，这些通过 `ghostty_config_get` 可以被 Surface 正确读取

## Python 脚本（保留）

`ghostty-theme` 脚本是独立的 Ghostty 主题切换工具，用于系统级 Ghostty 配置，与看板应用无关。它通过**重启 Ghostty 进程**来应用主题变更，所以能正常工作。这个脚本保留在项目根目录。
