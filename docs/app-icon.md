# App Icon 集成文档

## 概述

本项目使用自定义 App Icon。ICNS 文件已纳入项目仓库：`Sources/Kanbango/AppIcon.icns`。

## 图标文件

| 文件 | 说明 |
|------|------|
| `final-icon/16.png` ~ `final-icon/1024.png` | 原始 PNG 资源 |
| `final-icon/AppIcon.icns` | macOS Dock/Launchpad 显示用 |
| `Sources/Kanbango/Assets.xcassets/` | 项目内 Assets Catalog |

## 构建流程

图标通过以下流程集成到 `.app` bundle：

1. **PNG → ICNS 转换**（手动执行一次）
   ```bash
   cd "/Users/hue/Documents/图像/final-icon"
   mkdir AppIcon.iconset
   # 复制各尺寸 PNG 到 iconset
   iconutil -c icns AppIcon.iconset
   ```

2. **run.sh 自动打包**
   - 编译 Swift 代码
   - 创建 `Kanbango.app` bundle
   - 复制 `Sources/Kanbango/AppIcon.icns` 到 `Contents/Resources/`
   - 复制 `Sources/Kanbango/Assets.xcassets` 到 `Contents/Resources/`
   - ad-hoc codesign

## 修改图标后

如果更新了图标源文件，需要：

1. 重新生成 ICNS 并覆盖到项目：
   ```bash
   cd "/Users/hue/Documents/图像/final-icon"
   iconutil -c icns AppIcon.iconset
   cp AppIcon.icns /path/to/Kanbango/Sources/Kanbango/AppIcon.icns
   ```

2. 重新运行 `bash run.sh`

3. 清除 icon 缓存：
   ```bash
   sudo rm -rf /Library/Caches/com.apple.iconservices.store
   killall Dock
   ```

## Info.plist 配置

```xml
<key>CFBundleIconFile</key>
<string>AppIcon.icns</string>
```

## Assets.xcassets 结构

```
Sources/Kanbango/Assets.xcassets/
├── Contents.json
└── AppIcon.appiconset/
    ├── Contents.json
    ├── AppIcon-16.png
    ├── AppIcon-32.png
    ├── AppIcon-64.png
    ├── AppIcon-128.png
    ├── AppIcon-256.png
    ├── AppIcon-512.png
    └── AppIcon-1024.png
```
