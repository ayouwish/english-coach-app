import Foundation
import Observation

/// 服务状态页状态（`HealthView(services:audio:)`）。
///
/// `GET /health?force=1`（无需登录，5s 超时）：展示 db / voice.reachable / voice.mode /
/// capabilities / features，并支持“复制诊断信息”（只含版本与主机名，**不含 token/邮箱**）。
@MainActor
@Observable
final class HealthViewModel {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(UIMessage)
    }

    let services: AppServices
    let audio: AudioCoordinator
    let session: SessionStore

    private(set) var loadState: LoadState = .idle
    private(set) var health: HealthFullDTO?
    private(set) var isRefreshing = false
    private(set) var lastUpdated: Date?
    private(set) var didLoad = false

    init(services: AppServices, audio: AudioCoordinator, session: SessionStore) {
        self.services = services
        self.audio = audio
        self.session = session
    }

    // MARK: - 加载

    func load(force: Bool = false) async {
        if didLoad && !force { return }
        if case .loading = loadState { return }
        loadState = .loading
        do {
            let dto = try await services.stats.healthFull(force: force)
            health = dto
            lastUpdated = Date()
            didLoad = true
            loadState = .loaded
        } catch let error as APIError {
            loadState = .failed(ErrorMapper.message(for: error, isChild: session.isChild))
        } catch {
            loadState = .failed(ErrorMapper.message(for: error, isChild: session.isChild))
        }
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        didLoad = false
        await load(force: true)
    }

    // MARK: - 展示

    var statusText: String {
        health?.status ?? "未知"
    }

    var voiceReachableText: String {
        guard let voice = health?.voice else { return "未返回" }
        if let reachable = voice.reachable {
            return reachable ? "可用" : "不可用"
        }
        return "未知"
    }

    var dbText: String {
        guard let db = health?.db else { return "未返回" }
        if let ok = db.ok {
            return ok ? "正常" : "异常"
        }
        return "未知"
    }

    var lastUpdatedText: String {
        guard let lastUpdated else { return "尚未检查" }
        return "更新于 " + EcFormat.timeText(lastUpdated)
    }

    var capabilityItems: [KeyValueItem] {
        guard let caps = health?.voice?.capabilities else { return [] }
        var items: [KeyValueItem] = []
        var index = 0
        func append(_ key: String, _ value: Bool?) {
            items.append(KeyValueItem(id: index, key: key, value: Self.boolText(value)))
            index += 1
        }
        append("音素级评分", caps.phonemeLevel)
        append("语调曲线", caps.intonationCurve)
        append("韵律分析", caps.prosody)
        append("N-Best 音素", caps.nbestPhonemes)
        append("SSML", caps.ssml)
        append("OCR", caps.ocr)
        append("HEIC", caps.heic)
        append("插画", caps.image)
        append("形象预设", caps.avatarPresets)
        append("音频拼接", caps.audioConcat)
        return items
    }

    var featureItems: [KeyValueItem] {
        guard let features = health?.features else { return [] }
        var items: [KeyValueItem] = []
        var index = 0
        func append(_ key: String, _ value: Bool?) {
            items.append(KeyValueItem(id: index, key: key, value: Self.boolText(value)))
            index += 1
        }
        append("对话不限轮数", features.chatUnlimitedTurns)
        append("对话音频回放", features.chatAudioReplay)
        append("场景受众区分", features.chatScenariosAudience)
        append("虚拟形象", features.avatarPresets)
        append("故事模式", features.storyMode)
        append("异步评分", features.asyncScoring)
        return items
    }

    var serverHost: String {
        session.baseURL?.host ?? "未知"
    }

    /// 复制给家长/开发者的诊断信息（不含 token、Cookie、邮箱、音频）。
    var diagnosticText: String {
        var lines: [String] = []
        lines.append("English Coach \(AppConfig.appVersion)")
        lines.append("服务器：\(session.baseURL?.absoluteString ?? "未配置")")
        lines.append("主机：\(serverHost)")
        if let health {
            lines.append("status: \(health.status ?? "—")")
            lines.append("service: \(health.service ?? "—")")
            lines.append("version: \(health.version ?? "—")")
            lines.append("db.ok: \(Self.boolText(health.db?.ok))")
            lines.append("voice.reachable: \(Self.boolText(health.voice?.reachable))")
            lines.append("voice.mode: \(health.voice?.mode ?? "—")")
            if let caps = health.voice?.capabilities {
                lines.append("capabilities.ocr: \(Self.boolText(caps.ocr))")
                lines.append("capabilities.image: \(Self.boolText(caps.image))")
                lines.append("capabilities.heic: \(Self.boolText(caps.heic))")
            }
            if let hint = health.voice?.hint, !hint.isEmpty {
                lines.append("voice.hint: \(hint)")
            }
        } else {
            lines.append("尚未拿到 /health 结果")
        }
        lines.append("检查时间：\(lastUpdatedText)")
        return lines.joined(separator: "\n")
    }

    private static func boolText(_ value: Bool?) -> String {
        guard let value else { return "未知" }
        return value ? "支持" : "不支持"
    }
}
