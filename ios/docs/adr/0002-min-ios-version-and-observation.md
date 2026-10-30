# ADR-0002 · 最低 iOS 版本 17.0 与状态管理选型（Observation）

- **状态**：Accepted（暂定，需产品确认家庭在用设备 —— Q2）
- **日期**：2026-10-31
- **决策者**：iOS 客户端（产品确认后转正）
- **相关**：`README.md` §3、`docs/architecture.md` §3、`docs/open-questions.md` Q2

---

## 背景

这是一个**单人维护**的家庭应用，页面数量约 15 个，但状态交互密集（录音/上传/轮询/播放/多阶段向导）。UI 用 SwiftUI，需要一个"够轻、够直接"的状态方案。

两个候选：

| 方案 | 状态载体 | 最低系统 | 代码量 | 迁移成本 |
| --- | --- | --- | --- | --- |
| A | Observation 框架（`@Observable` + `@State` + `@Environment`） | iOS 17.0 | 低（属性变化自动追踪，无需 `@Published`） | 无（新项目） |
| B | Combine（`ObservableObject` + `@Published` + `@StateObject`/`@ObservedObject`） | iOS 13+ | 中（样板多、易误用 `@ObservedObject`） | 无 |

同时，iOS 17 还带来若干对本文档有用的 API：

- `ContentUnavailableView`（空态统一）；
- `onChange(of:)` 两参数闭包（旧签名已弃用）；
- `@Observable` 与 SwiftUI 的细粒度依赖追踪（只有真正用到的属性变化才触发重绘）；
- `AVAudioApplication.requestRecordPermission`（麦克风权限新入口）；
- `ScrollView` 的滚动位置 API（连读进度条）。

兼容性事实（需确认，不臆断）：iOS 17 支持的机型为 iPhone XS/XR 及以后；**iPhone X、iPhone 8 及更早机型最高只能到 iOS 16**。

---

## 决策

**最低部署目标设为 iOS 17.0，状态管理采用 Observation（`@Observable`）。**

具体约定：

1. 页面 Store：`@MainActor @Observable final class XxxStore`，由 `@State private var store` 持有（随页面生命周期创建/销毁）。
2. 全局会话：`@MainActor @Observable final class SessionStore`，在 `AppRoot` 创建并通过 `.environment(...)` 下发，子视图用 `@Environment(SessionStore.self)` 读取。
3. 角色能力：`RoleCapabilities` 通过自定义 `EnvironmentKey` 下发（值类型，`Sendable`）。
4. 纯数据 DTO：`struct: Sendable`，不用 `@Observable`。
5. 禁止混用 `@Published`/`ObservableObject`；如果未来必须支持 iOS 16，走"整体替换"而非"两套并存"。

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

## 为什么不是 iOS 16

| 维度 | iOS 17（选） | iOS 16（备选） |
| --- | --- | --- |
| Store 样板 | 少：属性即状态 | 多：每个属性 `@Published`，每个 View `@StateObject`/`@EnvironmentObject` |
| 重绘粒度 | 细（按属性追踪） | 粗（整个 objectWillChange） |
| 空态组件 | `ContentUnavailableView` | 自研 |
| 权限 API | `AVAudioApplication`（新） | `AVAudioSession.requestRecordPermission`（已弃用） |
| 覆盖设备 | iPhone XS/XR 及以后（家庭常见） | 多覆盖 iPhone 8/X |
| 风险 | 老设备装不上 | 代码量 + 约 2 人日，且并发检查更啰嗦 |

对单人维护的项目，**代码量与认知负担的收益大于多覆盖两代旧机型**。家庭场景通常设备更新较慢，但 iPhone X 已是 2017 年机型，在 2026 年作为主力学习设备概率不高（需 Q2 确认）。

---

## 后果

**正面**
- 状态代码显著更少，`@Observable` 的细粒度追踪减少无谓重绘；
- 可以用 `onChange(of:)` 新签名、`ContentUnavailableView` 等，少写自研组件；
- 与 Swift 6 严格并发配合更自然（`@MainActor` 隔离清晰）。

**负面**
- 家庭中若有 iPhone 8/X（iOS 16 上限）将无法安装；
- 部分第三方库（本期不用）最低版本可能低于 17，不构成问题；
- 若日后要降级到 16，需要把 `@Observable` 全部替换为 `ObservableObject`，属**破坏性改动**，需单独 ADR。

**缓解**
- 在 M0 前确认设备清单（Q2）；若存在 iOS 16 设备，改选 16.0，代价是 +2 人日与更多样板代码；
- 业务逻辑（`ErrorMapper`、`ScorePresenter`、轮询状态机）与 UI 框架解耦，即使降级也不必重写这些部分。

---

## 备选方案（若 Q2 结论为 iOS 16）

- Store 改为 `ObservableObject` + `@Published`，View 用 `@StateObject` / `@EnvironmentObject`；
- 空态自研 `EmptyStateView`（设计系统本来就有，不额外成本）；
- 麦克风权限用 `AVAudioSession.sharedInstance().recordPermission` + iOS 17 分支 `#available`；
- `onChange(of:)` 用旧签名并加 `#available` 兼容（或统一用旧签名，减少分支）。

**注意**：不要为了"兼容 16"而在 17 上继续用旧写法——那等于放弃了选 17 的全部收益。要么全 17，要么全 16。

---

## 验证与前置条件（未验证）

| 项 | 状态 |
| --- | --- |
| 家庭在用 iPhone 型号与系统版本 | **未知，需产品提供** |
| 是否需要在 iPad 上运行 | 未知（Q8）；iPadOS 17 与 iOS 17 同步，不额外增加成本 |
| Xcode 版本与真机调试资格 | 未知（Q3） |

在上述确认前，本 ADR 为**暂定接受**；若设备清单显示必须支持 iOS 16，则本文改为 `Superseded` 并新建 `0003-min-ios-16.md`。
