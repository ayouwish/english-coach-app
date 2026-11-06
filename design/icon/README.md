# English Coach · App 图标规范

一套跨端统一的图标：**渐变紫底 + 白色麦克风 + 三圈声波 + 暖色星点**。
“麦克风 + 声波”= 开口说英语；“星点”= 每次练习的一点进步 / 鼓励语，整体保持孩子也会喜欢但不过分幼稚。

## 视觉规范

| 项目 | 值 |
| --- | --- |
| 主色渐变 | `#7B68FF` → `#4A34D8`（对角，约 52°） |
| 前景 | `#FFFFFF`（网罩细线 `#D9D5FF`） |
| 点缀 | 星点 `#FFB080` / `#FFD6AA` |
| 画布 | 1024 × 1024，圆角半径 230（squircle） |
| 安全区 | 前景内容位于中间约 72% 区域，适配 Android/iOS/鸿蒙裁切 |

设计约束：
- 不使用文字/字母（小尺寸会糊）；32px 下麦克风与星点仍可辨认
- 前景、背景分离，适配 Android adaptive icon / 鸿蒙分层图标 / iOS 单尺寸 AppIcon
- 深色、浅色桌面均成立（暗底靠白色麦克风，浅底靠紫底）

## 文件

| 文件 | 用途 |
| --- | --- |
| `icon.svg` | 矢量母版（可任意放大，设计稿源文件） |
| `icon_1024.png` | 圆角母版（文档 / 商店展示） |
| `icon_1024_square.png` | 满幅方图（Apple / 需要系统自行裁切的场景） |
| `icon_16..512.png` | 常用尺寸（16 未提供时用 32 缩放） |
| `../../design/preview_sheet.png` | 多尺寸 + 明暗底预览 |

## 各端落点

### HarmonyOS（`hos/`）
- `AppScope/resources/base/media/`：`background.png`、`foreground.png`、`layered_image.json`
- `entry/src/main/resources/base/media/`：同上 + `startIcon.png`（启动页）
- `AppScope/app.json5` 与 `entry/src/main/module.json5` 的 `icon` 均指向 `$media:layered_image`

### Android（`android/`）
- `res/drawable-nodpi/ic_launcher_foreground.png` / `ic_launcher_background.png`
- `res/mipmap-anydpi-v26/ic_launcher.xml`（adaptive-icon 引用上面两张）
- `res/mipmap-mdpi..xxxhdpi/ic_launcher.png`、`ic_launcher_round.png`（旧系统 48–192px）

### iOS（`ios/`）
- `EnglishCoach/Resources/Assets.xcassets/AppIcon.appiconset/icon_1024.png`（RGB，无 alpha）
- `project.yml`：`ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon`

## 重新生成

```bash
python design/make_icon.py
```

脚本会：生成母版/预览 → 同步写入 HOS、Android、iOS 三端资源 → 清理旧资源。
依赖 Pillow（已随工作区提供）。
