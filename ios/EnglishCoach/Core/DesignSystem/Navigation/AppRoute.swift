import Foundation

/// 全局路由（逐字对齐 `ios/docs/port-contract.md` §3.14，case 与 §4 页面表一致）。
///
/// 使用方式（B1–B5）：
/// ```swift
/// @Environment(AppRouter.self) private var router
/// NavigationStack(path: Bindable(router).path) { ... }
///     .navigationDestination(for: AppRoute.self) { route in ... }
/// router.push(.sentences)
/// ```
///
/// 说明：`practice(SentenceDTO)` 的关联值是契约 §3.14 的原文签名（路由必须携带句子对象，
/// 避免 push 后再次请求）；这是本文件唯一的网络 DTO 引用，与 DesignSystem「纯展示」原则
/// 的冲突已在交付回报中说明，待 Lead 决定是否改为 `practice(sentenceId: String)`。
enum AppRoute: Hashable {
    /// 句子列表（跟读选句）。
    case sentences
    /// 单句跟读（含页内结果）。
    case practice(SentenceDTO)
    /// 跟读详细结果（全屏）。
    case practiceResult(attemptId: String?)
    /// 连读汇总。
    case flowSummary

    /// 对话场景列表。
    case chatScenarios
    /// 对话会话。
    case chatSession(sessionId: String)
    /// 对话历史列表。
    case chatHistory
    /// 对话详情。
    case chatDetail(sessionId: String)
    /// 自定义场景（scenarioId 为 nil 表示新建）。
    case chatCustom(scenarioId: String?)

    /// 讲故事（录音 → ASR → 改写）。
    case storyRecord
    /// 故事详情。
    case storyDetail(materialId: String)
    /// 故事复述（sentences 为待复述的原文句子）。
    case storyReview(materialId: String, sentences: [String])

    /// 盲测。
    case blindTest
    /// 诊断（成长）。
    case diagnosis
    /// 错音本。
    case review

    /// 家长面板。
    case parent
    /// 家庭成员。
    case family
    /// 建议箱。
    case suggestions
    /// 虚拟形象。
    case avatar
    /// 音色。
    case voices
    /// 服务状态。
    case health

    /// 设置。
    case settings
}
