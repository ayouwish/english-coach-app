# ADR-0002 · 最低 iOS 版本 26.0 与状态管理选型（Observation）

- **状态**：Accepted（2026-10-31，用户拍板）
- **日期**：2026-10-31
- **决策者**：项目负责人
- **相关**：`README.md` §3/§6.1、`docs/architecture.md` §3、`docs/open-questions.md` Q2（已决）、[ADR-0003](0003-bearer-token.md)（认证）

---

## 背景

这是一个**单人维护**的家庭应用，页面约 15 个，但状态交互密集（录音/上传/轮询/播放/多阶段向导）。UI 用 SwiftUI，需要一个“够轻、够直接”的状态方案。

状态管理候选：

| 方案 | 状态载体 | 最低系统 | 代码量 | 迁移成本 |
| --- | --- | --- | --- | --- |
| A | Observation 框架（`@Observable` + `@State` + `@Environment`） | iOS 17.0 | 低（属性变化自动追踪，无需 `@Published`） | 无（新项目） |
| B | Combine（`ObservableObject` + `@Published` + `@StateObject`/`@ObservedObject`） | iOS 13+ | 中（样板多、易误用 `@ObservedObject`） | 无 |

> **历史记录**：2026-10-31 的早稿曾在“iOS 17 vs iOS 16”之间权衡（为覆盖 iPhone 8/X 而考虑退回 `ObservableObject`）。该讨论**已作废**：用户拍板最低版本为 **iOS 26**，不再为旧机型保留兼容分支，本文也不再保留 17/16 的权衡表。

---

## 决策

**最低部署目标设为 iOS 26.0，状态管理采用 Observation（`@Observable`）。**

由于最低版本已经是 26，iOS 17/18 引入的 API 均可**无条件使用**，不需要 `#available` 分支。具体约定：

1. 页面 Store：`@MainActor @Observable final class XxxStore`，由 `@State private var store` 持有（随页面生命周期创建/销毁）。
2. 全局会话：`@MainActor @Observable final class SessionStore`，在 `AppRoot` 创建并通过 `.environment(...)` 下发，子视图用 `@Environment(SessionStore.self)` 读取。
3. 角色能力：`RoleCapabilities` 通过自定义 `EnvironmentKey` 下发（值类型，`Sendable`）。
4. 纯数据 DTO：`struct: Sendable`，不用 `@Observable`。
5. **禁止**混用 `@Published`/`ObservableObject`；也**不再保留**“若将来要支持 iOS 16”的降级路径。若最低版本需要下调，必须另开 ADR 并整体替换，而不是两套并存。

```swift
@MainActor @Observable
final class SessionStore {
    private(set) var user: UserProfile?
    private(set) var phase: Phase = .restoring   // restoring / loggedOut / ready

    var capabilities: RoleCapabilities {
        user.map(RoleCapabilities.init) ?? .adultDefault
    }
}
```

---

## 为什么是 iOS 26

1. **用户设备与长期维护**：本项目服务家庭自用，设备可控；用户已确认按 iOS 26 规划，不为已不在用的旧机型付兼容成本。
2. **减少分支与心智负担**：单人维护下，最低版本越高，`#available`、双套状态写法、旧 API 弃用告警就越少；代码只保留一条路径。
3. **Observation 与 Swift 6 并发配合更自然**：`@MainActor` 隔离清晰，细粒度依赖追踪减少无谓重绘。
4. **新 API 可直接用**：`ContentUnavailableView`、`onChange(of:)` 新签名、`AVAudioApplication` 等自 iOS 17 起可用；`@Entry`、`MeshGradient` 等自 iOS 18 起可用；在 26 上均无需条件编译。
5. **分发方式匹配**：只走 TestFlight 内部测试（见 README §6.6），测试员设备同样升级到 iOS 26，不存在“用户装不上”的分发压力。

**设备覆盖**：按 Apple 公布口径，iOS 26 不再支持 iPhone XS/XR 及更早机型，最低为 iPhone 11 / iPhone SE（第二代）及之后（**实现前以 Apple 官方兼容列表复核**，本文未在真机逐型号验证）。家庭中若仍有低于该线的设备，将无法安装本 App —— 这是本决策的已知代价。

---

## iOS 17 / 18 / 26 新 API 使用策略

| API / 能力 | 最低版本 | 本期是否使用 | 说明 |
| --- | --- | --- | --- |
| Observation（`@Observable`、`@Environment(Type.self)`） | iOS 17 | ✅ **核心** | 所有 Store 的状态载体 |
| `ContentUnavailableView` | iOS 17 | ✅ 使用 | 统一空态；设计系统只做轻量包装 |
| `onChange(of:initial:)` 新签名 | iOS 17 | ✅ 使用 | 不再写旧签名 |
| `AVAudioApplication.requestRecordPermission` | iOS 17 | ✅ 使用 | 麦克风权限入口（见 `audio.md` §2.2） |
| `ScrollView` 滚动位置 API（`scrollPosition`） | iOS 17 | ✅ 使用 | 连读进度定位 |
| `@Entry` 宏 | iOS 18 | ✅ 使用 | 简化 `EnvironmentKey` / 自定义环境值样板 |
| `MeshGradient` | iOS 18 | ⚠️ 可选 | 仅登录页/成就页的轻量装饰背景；须经设计确认，且 Reduce Motion / 对比度复核通过后才用 |
| `Tab` / 新版 `TabView` 容器语法 | iOS 18 | 【待确认】 | 具体 API 名称与行为以 SDK 为准；若采用需保持 5 个 Tab 的现有信息架构 |
| iOS 26 Liquid Glass 材质与配套 SwiftUI 修饰符 | iOS 26 | ❌ **不使用** | 设计系统使用自有浅色卡片 + 轻阴影以与 Web 视觉同源；系统玻璃材质会让两端外观分叉。具体 API 名称以 SDK 为准【待确认】 |
| SwiftUI `WebView` | iOS 26 | ❌ 不使用 | 本期无内嵌网页需求（帮助页也用原生页面） |
| Foundation Models（端侧模型） | iOS 26 | ❌ 不使用 | LLM 在服务端（DeepSeek），端侧模型不在本期范围 |
| `@concurrent`（Swift 6.2 并发标注） | 工具链（Xcode 26） | ⚠️ 可选 | 仅用于明确的非隔离工具函数；不改变“UI 状态在 MainActor”的规则【待确认是否需要】 |

> 原则：**只用“能让代码更少、且不改变视觉/交互契约”的新 API**；iOS 26 的系统级外观变化（Liquid Glass）不跟进，避免与 Web 端视觉同源的目标冲突。

---

## 后果

**正面**

- 状态代码显著更少，`@Observable` 的细粒度追踪减少无谓重绘；
- 无 `#available` 分支、无旧 API 弃用告警，单人维护成本最低；
- 可直接使用 iOS 18 的 `@Entry` 等语法糖，进一步压缩样板代码；
- 与 Swift 6 严格并发配合更自然（`@MainActor` 隔离清晰）。

**负面 / 风险**

- 家庭中低于 iPhone 11 / SE2 的设备**无法安装**；
- 无法在旧系统上做兼容性验证；所有真机验收都要求 iOS 26 设备；
- 若日后产品要求覆盖旧设备，需要把 `@Observable` 全部替换为 `ObservableObject`，属**破坏性改动**，必须另开 ADR；
- 采用 iOS 26 意味着跟随新 SDK 的回归风险（新系统首年偶有 SwiftUI 行为变化），需要在 M0 真机矩阵里覆盖。

**缓解**

- M0 前确认家里每台要用的 iPhone/iPad 都已升级到 iOS 26（Q2 已决，但**设备清单未在仓库记录**）；
- 业务逻辑（`ErrorMapper`、`ScorePresenter`、轮询状态机）与 UI 框架解耦，降低未来系统迁移成本；
- 新 API 只用于“可替换的边角”（`@Entry` 等），核心状态机不依赖 26 独有特性。

---

## 验证与前置条件（未验证）

| 项 | 状态 |
| --- | --- |
| 家庭在用 iPhone 型号与系统版本 | **用户已拍板按 iOS 26 规划**；具体型号清单未记录 |
| 是否需要在 iPad 上运行 | 未知（Q8）；iPadOS 26 与 iOS 26 同步，不额外增加成本 |
| Xcode 版本与真机调试资格 | **需 Xcode 26+**；本机 macOS 是否满足未确认（Q3 已决为 TestFlight，付费开发者账号为前提） |
| iOS 26 设备兼容列表 | 以 Apple 官方页面为准，本文未逐型号复核 |

在上述确认前，本 ADR 的**版本决策本身有效**（用户已拍板）；待确认的只是设备清单与工具链就绪情况。
