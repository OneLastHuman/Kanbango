# Terminal 性能问题排查与解决

**日期:** 2026-05-04
**问题:** 终端加载长文本时卡顿严重（鼠标转圈），resize 窗口时响应极慢
**根因:** `libghostty-internal.a` 静态库是用 Zig 默认的 Debug 模式编译的，整个 Metal 渲染管线没有优化
**解决:** 用 `-Doptimize=ReleaseFast` 重新编译 libghostty，替换静态库

---

## 问题描述

用户反馈：
1. 终端内加载长文本内容时，鼠标转圈很久才有响应
2. 拖拽分隔条 resize 窗口时，终端响应极慢
3. 原版 Ghostty 终端不存在此问题

## 排查过程

### Phase 1: 初步分析 — SwiftUI 布局开销？

最初假设：SwiftUI 的 `HSplitView` 在 resize 时会触发整个视图树重新布局，导致性能问题。

**分析结果:**
- `ContentView` 使用 `HSplitView` 包含看板和终端
- `GeometryReader` + `@Published` 属性可能在 resize 时触发大量 SwiftUI 视图 diff
- JsonlWatcher 每 3 秒扫描 `~/.claude/projects/` 也可能加重主线程负担

**尝试的修复:**
1. ✅ 改 `run.sh` 用 `swift build -c release`（从 debug 改为 release 编译 Swift 代码）
2. ❌ 对 `SurfaceScrollView.sizeDidChange` 做 33ms 防抖 — 无效，撤回
3. ❌ 用 AppKit `NSSplitView` 替换 SwiftUI `HSplitView` — 无效，撤回

### Phase 2: 隔离测试 — 确认瓶颈位置

**关键测试:** 临时去掉看板，只留终端全屏，测试 resize 性能。

**结果:** 还是卡！说明瓶颈不在 SwiftUI 布局，而在终端渲染本身。

### Phase 3: 深入对比 — libghostty 编译模式

对比原版 Ghostty 和我们的应用，发现两者使用**完全相同的** libghostty 渲染代码：
- Metal 渲染管线（CVDisplayLink 驱动）
- `SurfaceScrollView` → `sizeDidChange` → `ghostty_surface_set_size` 链路
- `GeometryReader` → `SurfaceRepresentable` → `needsLayout` 机制

**关键发现:** 检查 `libghostty-internal.a` 的编译模式：

```
# Zig 的 build.zig 中优化配置
const optimize = b.standardOptimizeOption(.{});  # 默认 = Debug

# GhosttyLib.zig 中
.optimize = deps.config.optimize,  # 继承全局配置
```

Zig 默认编译模式是 **Debug**（无优化）。`libghostty-internal.a`（384MB）是用 Debug 模式编译的，整个渲染管线（Metal、terminal reflow、CVDisplayLink）都运行在无优化状态。

**证据:**
- Debug 库: 384MB（包含调试符号）
- ReleaseFast 库: 270MB（优化后，体积减少 30%）

### Phase 4: 重新编译 libghostty

macOS 上 `zig build -Dapp-runtime=none` 不会直接生成 `ghostty-internal.a`（有 `!isDarwin()` 守卫），需要通过 xcframework 构建流程：

```bash
# 清除缓存（之前的缓存导致构建卡住）
rm -rf /Users/hue/Documents/ghostty-main/.zig-cache /Users/hue/Documents/ghostty-main/zig-out

# 用 ReleaseFast 编译
cd /Users/hue/Documents/ghostty-main
zig build -Dapp-runtime=none -Doptimize=ReleaseFast

# 替换旧库
cp macos/GhosttyKit.xcframework/macos-arm64_x86_64/ghostty-internal.a \
   /path/to/kanban-ghostty/libghostty-internal.a
```

## 最终结果

替换为 ReleaseFast 编译的 `libghostty-internal.a` 后：
- ✅ 加载长文本不再卡顿
- ✅ resize 窗口流畅无延迟
- ✅ 性能与原版 Ghostty 一致

## 经验总结

| 问题 | 教训 |
|------|------|
| 一开始假设 SwiftUI 布局是瓶颈 | 隔离测试很重要——去掉看板后还卡，排除了 SwiftUI 假设 |
| 防抖、NSSplitView 都没用 | 如果根因不对，再多优化也没用 |
| Zig 编译模式默认 Debug | 预编译库一定要确认编译模式，体积是重要线索（384MB vs 270MB） |
| zig build 缓存损坏导致卡住 | 遇到构建卡死先清缓存（`.zig-cache` + `zig-out`） |

## 涉及文件

| 文件 | 变更 |
|------|------|
| `run.sh` | `swift build` → `swift build -c release`，`.build/debug/` → `.build/release/` |
| `package-kanbango.sh` | `swift build` → `swift build -c release` |
| `libghostty-internal.a` | 替换为 ReleaseFast 编译版本（384MB → 270MB） |
