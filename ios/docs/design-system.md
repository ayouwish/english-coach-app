# 设计系统 · English Coach iOS

> 目标：与 Web 端**视觉同源**（浅蓝底 `#f5f7ff`、紫蓝主色 `#5b5bd6`、卡片圆角 20 / 弹层 28、轻阴影）——**以仓库根 `docs/design-tokens.md` 为准**（该文件从 Web 实际 CSS 提取；本文早期用的是近似值，已更正），
> 但交互尺寸按触屏与儿童重做。所有颜色/字号在 iOS 侧定义一次，页面只引用语义令牌。
> 对比度标注为**按 WCAG 相对亮度公式估算**，未用工具实测；上线前建议用 Accessibility Inspector 复核。

---

## 1. 原则

1. **内容优先**：一个页面只有一个主行动（录音球 / 登录 / 下一句），其余降级。
2. **孩子在前面**：孩子模式的字号、按钮、文案、色彩是独立令牌，不是“成人界面缩小/放大”。
3. **轻**：白卡片 + 浅蓝底 + 极轻阴影；不用深色大色块，不用重描边。
4. **可读性 > 装饰**：正文对比度 ≥4.5:1，正文最小 17pt（孩子 20pt）。
5. **动效服务于因果**：录音/评分/翻页有动效，装饰性动画不做。

---

## 2. 颜色令牌

### 2.1 基础语义色

| Token | Hex | 用途 | 对比度（估） |
| --- | --- | --- | --- |
| `bgCanvas` | `#F5F7FF` | 页面背景（与 Web 一致） | — |
| `surfaceCard` | `#FFFFFF` | 卡片、输入框、Sheet | — |
| `surfaceMuted` | `#ECEBFF` | 次级按钮底、选中态底、标签底 | — |
| `surfaceSunken` | `#F1F5F9` | 分组长条、骨架底色 | — |
| `primary` | `#5B5BD6` | 主按钮、选中、进度、链接 | 白底 ≈6.3:1 ✅ |
| `primaryPressed` | `#4A4AC4` | 按下态 | ≈7.5:1 ✅ |
| `primaryDisabled` | `#C7D2FE` | 禁用填充 | 仅填充 |
| `onPrimary` | `#FFFFFF` | 主色上的文字 | — |
| `textPrimary` | `#1F2937` | 标题、正文 | 背景上 ≈14:1 ✅ |
| `textSecondary` | `#6B7280` | 辅助说明 | 背景上 ≈4.6:1 ✅ |
| `textTertiary` | `#9CA3AF` | 占位符、时间戳（不承载关键信息） | ≈2.8:1（仅装饰） |
| `borderSubtle` | `#E5E7EB` | 输入框、分割线 | — |
| `borderFocus` | `#5B5BD6` | 聚焦描边 | — |
| `success` | `#16A34A` | 正确、达标（图标/填充）；文字用 `#15803D` | 文字 ≈5.0:1 ✅ |
| `warning` | `#B45309` | 提醒文字 | ≈5.0:1 ✅ |
| `danger` | `#DC2626` | 删除、错误文字 | ≈4.8:1 ✅ |
| `overlayScrim` | `rgba(15,23,42,0.35)` | 模态遮罩 | — |

### 2.2 品牌与儿童色

| Token | Hex | 用途 |
| --- | --- | --- |
| `brandGradientStart` | `#5B5BD6` | 录音球、Logo 渐变起 |
| `brandGradientEnd` | `#7C7CE6` | 渐变止 |
| `childAccent` | `#F59E0B` | 孩子模式的星星、坚持天数、庆祝 |
| `childAccentSoft` | `#FEF3C7` | 孩子模式卡片高亮底 |
| `childAccentText` | `#78350F` | 琥珀底上的文字（≈8:1） |
| `childSky` | `#0EA5E9` | 孩子模式次要强调（如“听一听”） |
| `recordingRed` | `#EF4444` | 录音中状态（仅脉冲与圆点，不做大面积） |
| `playbackBlue` | `#0EA5E9` | 播放中声波 |

> 孩子模式**不新增主色**，只把 `childAccent` 用于星星/庆祝，保持与 Web 的品牌一致。

### 2.3 分数色阶（**仅成人**）

| 区间 | Token | Hex | 说明 |
| --- | --- | --- | --- |
| 85–100 | `scoreExcellent` | `#16A34A` | 绿 |
| 70–84 | `scoreGood` | `#5B5BD6` | 主色（不要用蓝色以外的彩虹色） |
| 55–69 | `scoreFair` | `#B45309` | 琥珀 |
| 0–54 | `scoreWeak` | `#DC2626` | 红 |

**孩子模式不存在这张表**：分数只映射为 `tier ∈ {celebrate, encourage, retry}`（3/2/1 星），永远不使用 `scoreWeak`。

### 2.4 颜色使用规则
- 同一屏幕最多出现 1 个主色实心按钮；其余为 tonal 或文字按钮。
- 红色只用于“删除/错误/录音中圆点”，不用于“分数低”（成人用 `scoreWeak` 但仅限分数组件内）。
- 颜色不作为唯一信息载体：分数同时有数字/星级，状态同时有图标/文案（色盲可用）。

---

## 3. 字体层级

使用系统字体（SF Pro / 中文 PingFang SC），通过 Dynamic Type 缩放。

| Token | 默认字号/行高 | 字重 | 对应 Text Style | 用途 |
| --- | --- | --- | --- | --- |
| `display` | 40 / 48 | Bold | `.largeTitle` | 登录页标题、成就页 |
| `titleLarge` | 28 / 34 | Bold | `.title` | 页面大标题 |
| `title` | 22 / 28 | Semibold | `.title2` | 区块标题、句子卡主标题（短句） |
| `heading` | 20 / 26 | Semibold | `.title3` | 卡片标题、按钮文字（孩子） |
| `sentence` | 26 / 34 | Semibold | 自定义（基于 `.title2` 缩放） | 跟读页英文句子（**唯一的大字号正文**） |
| `body` | 17 / 24 | Regular | `.body` | 正文、翻译、说明 |
| `bodyEmphasis` | 17 / 24 | Semibold | `.body` | 强调、按钮（成人） |
| `callout` | 16 / 22 | Regular | `.callout` | 列表副标题 |
| `footnote` | 13 / 18 | Regular | `.footnote` | 时间、标签、辅助信息 |
| `caption` | 12 / 16 | Medium | `.caption` | 状态点说明、角标 |
| `ipa` | 16 / 22 | Regular（等宽可选） | `.callout` + `.monospaced` | IPA 音标（**仅成人**） |
| `scoreNumber` | 44 / 44 | Bold + `.rounded` 设计 | 自定义 | 分数环中心数字（仅成人） |

规则：
- 一个页面内标题层级不超过 3 级（`titleLarge` → `title` → `body`）。
- 英文句子用 `sentence`；中文翻译用 `body` + `textSecondary`。
- 孩子模式整体放大：`body → 20`、`heading → 24`、按钮字号 `20`；在 `Typography` 里用 `childScale = 1.15` 统一乘算，**不要**逐页改字号。
- 支持 Dynamic Type 到 `AX3`；超过 `AX3` 时句子卡改为可滚动，按钮文字允许换行。
- 自定义字号（`sentence` / `scoreNumber`）必须用 `.custom(size:relativeTo:)` 或 `@ScaledMetric`，否则不随系统字号缩放。

```swift
enum AppFont {
    static func body(_ caps: RoleCapabilities) -> Font {
        .system(size: 17 * caps.bodyFontScale, weight: .regular, design: .default)
    }
    static let sentence = Font.system(size: 26, weight: .semibold)
    static let score = Font.system(size: 44, weight: .bold, design: .rounded)
    static let ipa = Font.system(size: 16, design: .monospaced)
}
```

---

## 4. 间距与栅格

| Token | 值 | 用途 |
| --- | --- | --- |
| `space2` | 2 | 图标与文字微调 |
| `space4` | 4 | 标签内边距 |
| `space8` | 8 | 元素间距（紧凑） |
| `space12` | 12 | 卡片内边距（紧凑）、列表行间 |
| `space16` | 16 | **页面左右边距**、卡片内边距 |
| `space20` | 20 | 区块间距 |
| `space24` | 24 | 大区块间距、卡片之间 |
| `space32` | 32 | 页面顶部留白、空态 |
| `space40` | 40 | 登录页/成就页 |

- 页面水平边距固定 **16pt**（孩子 20pt）。
- 卡片内边距 16；卡片间距 12–16。
- 可点击元素最小 44×44（孩子 56×56）。

---

## 5. 圆角、描边、阴影

| Token | 值 | 用途 |
| --- | --- | --- |
| `radiusSmall` | 8 | 标签、Chip、输入框内小元素 |
| `radiusMedium` | 14 | 输入框、次级按钮（Web 按钮 `0.9rem`≈14） |
| `radiusLarge` | 20 | 卡片、主按钮（Web 卡片 `1.25rem`=20） |
| `radiusXLarge` | 28 | Sheet、底部弹层（Web 大容器 `1.75rem`=28） |
| `radiusPill` | 999 | 分段控件、胶囊标签 |
| `borderWidth` | 1 | 输入框/卡片描边（`borderSubtle`） |
| `shadowCard` | `y:1, blur:3, color: #1F2937 6%` + `y:1, blur:2, color: #5B5BD6 4%` | 卡片 |
| `shadowFloating` | `y:8, blur:24, color: #5B5BD6 12%` | 录音球、悬浮层 |

**轻阴影原则**：卡片阴影几乎不可见，靠留白与圆角分层；禁止大范围模糊阴影。

---

## 6. 按钮层级

| 层级 | 外观 | 高度（成人/孩子） | 用途 |
| --- | --- | --- | --- |
| Primary | 主色填充、白字、`radiusLarge` | 48 / 56 | 每屏唯一主行动（登录、提交、开始） |
| Secondary (tonal) | `surfaceMuted` 底、主色字 | 44 / 52 | 次行动（听示范、换一版） |
| Tertiary (text) | 透明底、主色字 | 44 / 48 | 低权重（跳过、查看全部） |
| Destructive | `danger` 文字（确认弹层内为填充） | 44 / 52 | 删除、退出 |
| Icon | 44×44 命中区、`textSecondary` | 44 | 返回、关闭、设置 |
| RecordOrb | 圆形渐变 + `shadowFloating`，录音中红色脉冲环 | 80 / 96 | 录音（唯一可重复的主行动） |
| PlayPill | 胶囊 + 播放图标 + 文本 | 36 / 44 | 行内示范音 |

状态：normal / pressed（`primaryPressed` 或 scale 0.98）/ disabled（`primaryDisabled` 填充或 40% 透明 + 禁点击）/ loading（文字替换为 spinner，宽度不变，防跳动）。
- 禁用态**必须**带解释（长按/点击后 toast 或副文案），不能只是灰掉。
- 主按钮 loading 时不显示进度百分比（除 OCR 上传这类有真实进度）。

---

## 7. 组件清单（Core/DesignSystem/Components）

| 组件 | 规格要点 |
| --- | --- |
| `ScoreRing` | 120pt 圆环，轨道 `borderSubtle`，进度用分数色；中心 `scoreNumber`；**仅成人**；动画 0.6s easeOut |
| `StarRating` | 3 颗星，`childAccent`，空星描边；仅孩子 |
| `WordChip` | 圆角 8，成功 `#ECFDF5`/`#15803D`，待改 `#FEF3C7`/`#78350F`；成人四级色阶 |
| `PhonemeTag` | 胶囊，IPA 等宽字体（成人）；孩子模式替换为中文别名 |
| `RecordOrb` | 80/96pt，渐变，外圈脉冲（录音时 `recordingRed`，评分中主色脉冲）；拖拽/点击均可停 |
| `LevelWaveform` | 24–32 根竖条，随电平 20Hz 更新；孩子更粗更圆 |
| `SentenceCard` | 白卡 + `radiusLarge`；英文 `sentence`，中文 `body`，标签行 `footnote` |
| `EntryCard` | 图标 + 标题 + 一句副标题；孩子模式大图标 |
| `ScenarioCard` | emoji/图标 + 标题 + 难度 + 一行描述 |
| `ChatBubble` | 助手左侧白底、用户右侧 `surfaceMuted`；播放中显示三格声波 |
| `MaterialCard` | 16:10 图片 + 标题 + 日期；图片占位用 `surfaceSunken` |
| `MemberRow` | 头像（首字母）+ 名称 + 角色/等级 + 操作 |
| `ProgressDots` | 连读模式句子状态：灰/脉冲/绿/红，最多 10 个 |
| `StepDots` | 向导 4 步指示 |
| `CoverageRing` | 故事复述覆盖率环（成人百分比 / 孩子星星） |
| `PitchContourChart` | Swift Charts 折线，Y 轴归一化，无坐标轴标签（仅形状），成人可见 |
| `MetricTile` | 家长面板数字块（句数/时长/连续天数） |
| `EmptyStateView` | 图标 96pt + 标题 + 说明 + 主按钮 |
| `ErrorStateView` | 同空态结构 + 重试 |
| `OfflineBanner` | 顶部 44pt，三态文案，可点开详情 |
| `PermissionCard` | 图标 + 标题 + 两句说明 + 主/次按钮 |
| `InlineError` | 14pt 红字 + 可选重试链接 |
| `SkeletonBlock` | `surfaceSunken` 圆角，微光扫过（Reduce Motion 时静态） |

组件必须支持 `#Preview` 的三种注入：成人/孩子/长文案（Localization 溢出）。

---

## 8. 动效

| 场景 | 时长/曲线 |
| --- | --- |
| 按钮按下 | 0.12s easeOut，scale 0.98 |
| 卡片进入（结果区） | 0.3s spring(response 0.35, damping 0.85)，位移 12pt + 透明度 |
| 录音开始 | 0.2s 圆球 scale 1→1.08 + 触感 `.impact(.medium)` |
| 评分中 | 1.2s 循环呼吸（scale 1.0↔1.05），不旋转 |
| 翻页转场 | 系统默认 |
| 星级出现 | 逐颗 0.15s 延迟弹入 |
| 错题/正误 | 0.2s 淡入颜色，不用抖动（避免焦虑） |

`UIAccessibility.isReduceMotionEnabled` 时：去掉呼吸、位移、骨架扫光，保留 0.15s 淡入。

---

## 9. 无障碍

| 项 | 要求 |
| --- | --- |
| VoiceOver | 录音球 label：“开始录音”，录音中：“正在录音，双击结束”；评分结果一次性 announce（`AccessibilityNotification.Announcement`） |
| 动态字体 | 支持到 AX3；句子卡可滚动；按钮高度随字号增长 |
| 对比度 | 正文 ≥4.5:1；大字号 ≥3:1 |
| 点击区 | ≥44pt（孩子 56pt）；列表整行可点 |
| 色盲 | 分数/状态均带图标或文字，不只靠颜色 |
| 动效 | 遵循 Reduce Motion |
| 语音提示 | 孩子模式关键状态可用 `.speech` 音效（M4） |
| 横屏 | iPhone 只支持竖屏（`UISupportedInterfaceOrientations` 仅 Portrait）；iPad 原生全屏并支持竖屏 + 左右横屏（见 Q8 与契约 §5） |

---

## 10. 图标（SF Symbols 映射）

| 语义 | Symbol | 备注 |
| --- | --- | --- |
| 练习/跟读 | `mic.fill` | 主行动 |
| 连读 | `waveform.path` 或 `infinity` | 连续 |
| 对话 | `bubble.left.and.bubble.right.fill` | |
| 故事 | `book.fill` / `photo.on.rectangle` | |
| 盲测 | `ear.fill` | |
| 成长 | `chart.line.uptrend.xyaxis` | |
| 家长 | `person.2.fill` | |
| 设置 | `gearshape.fill` | |
| 播放 | `play.fill` / `speaker.wave.2.fill` | |
| 慢速 | `tortoise.fill` | 配合文字“慢速” |
| 录音中 | `stop.fill` | 圆球内 |
| 成功/正确 | `checkmark.circle.fill` | `success` |
| 待改进 | `arrow.clockwise.circle.fill` | `warning`，不用叉号 |
| 离线 | `wifi.slash` | |
| 服务器故障 | `externaldrive.badge.exclamationmark` | NAS 语义 |
| 相机 | `camera.fill` | |
| 相册 | `photo.fill` | |
| 插画/魔法 | `wand.and.stars` | 生图 |
| 锁 | `lock.fill` | 权限/隐私 |

图标统一 `Image(systemName:)`，尺寸配字号（不单独写死）；填充型与描边型不混用同一层级。

---

## 11. 与 Web 令牌的对照（保证同源）

| Web（CSS 变量/约定） | iOS Token | 值 |
| --- | --- | --- |
| `--bg` / `background: #f5f7ff` | `bgCanvas` | `#F5F7FF` |
| `--primary` / 主按钮 | `primary` | `#5B5BD6` |
| 卡片白底 | `surfaceCard` | `#FFFFFF` |
| 卡片圆角 12–16px | `radiusMedium/Large` | 12 / 16 |
| 轻阴影 | `shadowCard` | 6% / 4% 双层 |
| 正文 16–17px | `body` | 17pt（孩子 20） |
| 辅助文字灰 | `textSecondary` | `#6B7280` |
| 标签胶囊 | `radiusPill` + `surfaceMuted` | — |

差异点（有意为之）：
- iOS 主按钮高度 48/56，Web 通常 40–44（触屏更大）；
- iOS 卡片阴影更轻（屏幕上更明显）；
- iOS 孩子模式有独立的字号/按钮/文案体系，Web 端的儿童版若不一致，以本文档为准。

---

## 12. 落地方式

```
Core/DesignSystem/
├── Theme.swift          // Environment 注入：颜色/字体/间距/能力
├── Tokens.swift         // 颜色、间距、圆角、阴影常量（唯一 hex 来源）
├── Typography.swift     // AppFont
├── Components/          // 上表组件
└── Modifiers/
    ├── CardStyle.swift
    ├── ChildModeStyle.swift   // 大字号/大按钮/无 IPA 的修饰器
    └── Shimmer.swift          // 骨架（Reduce Motion 自动关闭）
```

规则：
- **hex 只允许出现在 `Tokens.swift`**；其他文件一律引用语义名。
- 颜色同时提供 `Color(hex:)` 初始化与 `UIColor` 版本（供 `AVAudioPlayer` 无关的 UIKit 桥接、`Info.plist` 启动图不需）。
- 深色模式：**本期不支持**，`AppRoot` 显式 `preferredColorScheme(.light)`，并在 M4 作为可选项评估（Web 也只有浅色）。
- 所有组件在 `#Preview` 中同时渲染成人/孩子/超长文案三种，作为视觉回归的最低要求。
