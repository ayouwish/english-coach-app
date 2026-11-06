import Foundation
import Observation
import SwiftUI

/// 建议箱状态（`SuggestionsView(services:audio:)`）。
///
/// - 所有人（含儿童）都能提交；儿童只能看到 3 个分类、看不到列表（API 仅家长可列）。
/// - 家长可筛选状态、标记已读/已解决、导出 Markdown（复制给开发者）。
/// 对齐 HOS `AccountVM.SuggestionsVM` 与 screens.md §12。
@MainActor
@Observable
final class SuggestionsViewModel {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(UIMessage)
    }

    struct Category: Identifiable, Sendable, Equatable {
        let key: String
        let adultLabel: String
        let childLabel: String
        var id: String { key }
    }

    static let allCategories: [Category] = [
        Category(key: "experience", adultLabel: "体验问题", childLabel: "用起来哪里不顺手"),
        Category(key: "content", adultLabel: "内容建议", childLabel: "想读·想聊的内容"),
        Category(key: "feature", adultLabel: "新功能想法", childLabel: "想要的新功能"),
        Category(key: "bug", adultLabel: "程序出错", childLabel: "哪里出错了"),
        Category(key: "other", adultLabel: "其他", childLabel: "其他想法")
    ]

    struct StatusFilter: Identifiable, Hashable, Sendable {
        let key: String
        let label: String
        var id: String { key }
    }

    static let statusFilters: [StatusFilter] = [
        StatusFilter(key: "", label: "全部"),
        StatusFilter(key: "open", label: "未读"),
        StatusFilter(key: "read", label: "已读"),
        StatusFilter(key: "resolved", label: "已解决")
    ]

    let services: AppServices
    let audio: AudioCoordinator
    let session: SessionStore
    let isChild: Bool

    // 提交表单
    var category = "experience"
    var content = ""
    private(set) var maxLength = 2000
    private(set) var isSubmitting = false
    private(set) var createError: UIMessage?
    private(set) var createNotice: String?

    // 列表（仅家长）
    private(set) var filterStatus = ""
    private(set) var items: [SuggestionDTO] = []
    private(set) var openCount = 0
    private(set) var readCount = 0
    private(set) var resolvedCount = 0
    private(set) var total = 0
    private(set) var listState: LoadState = .idle
    private(set) var didLoadList = false
    private(set) var markingId = ""
    private(set) var listError: UIMessage?

    // 导出（仅家长）
    private(set) var isExporting = false
    private(set) var exportText = ""
    private(set) var exportError: UIMessage?
    private(set) var exportNotice: String?

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoFormatterPlain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    init(services: AppServices, audio: AudioCoordinator, session: SessionStore) {
        self.services = services
        self.audio = audio
        self.session = session
        self.isChild = session.isChild
    }

    // MARK: - 分类 / 标签

    var categories: [Category] {
        guard isChild else { return Self.allCategories }
        return Self.allCategories.filter { ["experience", "content", "other"].contains($0.key) }
    }

    var title: String {
        isChild ? "我想说" : "建议箱"
    }

    var subtitle: String {
        isChild
            ? "用起来哪里不顺手、想读什么故事、想加什么功能，都可以告诉我。"
            : "哪里不好用、想要什么功能、内容有什么问题，都记在这里，家长可以统一查看和导出。"
    }

    func categoryLabel(_ key: String?) -> String {
        guard let key, let category = Self.allCategories.first(where: { $0.key == key }) else {
            return key ?? "其他"
        }
        return isChild ? category.childLabel : category.adultLabel
    }

    func statusLabel(_ status: String?) -> String {
        switch status ?? "" {
        case "open": return "未读"
        case "read": return "已读"
        case "resolved": return "已解决"
        default: return status ?? "未知"
        }
    }

    func statusTone(_ status: String?) -> PillTag.Tone {
        switch status ?? "" {
        case "open": return .warning
        case "read": return .primary
        case "resolved": return .success
        default: return .neutral
        }
    }

    func roleLabel(_ role: String?) -> String {
        switch role ?? "" {
        case "child": return "孩子"
        case "parent": return "家长"
        default: return "未知"
        }
    }

    func relativeTime(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "" }
        let date = Self.isoFormatter.date(from: raw) ?? Self.isoFormatterPlain.date(from: raw)
        guard let date else { return raw }
        return EcFormat.relative(date)
    }

    // MARK: - 提交

    func submit() async -> Bool {
        guard !isSubmitting else { return false }
        createError = nil
        createNotice = nil
        let text = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            createError = localError(isChild ? "先写一句想说的话吧" : "请先写点什么再提交")
            return false
        }
        if text.count > maxLength {
            createError = localError("建议最多 \(maxLength) 字（当前 \(text.count) 字）")
            return false
        }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let body = SuggestionCreateDTO(
                category: category,
                content: text,
                page: "/settings",
                context: nil
            )
            _ = try await services.account.submitSuggestion(body)
            content = ""
            createNotice = isChild ? "收到啦，谢谢你！" : "收到啦，谢谢！已记到建议列表里。"
            if !isChild {
                didLoadList = false
                await loadList(force: true)
            }
            return true
        } catch let error as APIError {
            createError = ErrorMapper.message(for: error, isChild: isChild)
            return false
        } catch {
            createError = ErrorMapper.message(for: error, isChild: isChild)
            return false
        }
    }

    // MARK: - 列表

    func setFilter(_ status: String) async {
        guard filterStatus != status else { return }
        filterStatus = status
        didLoadList = false
        await loadList(force: true)
    }

    func loadList(force: Bool = false) async {
        guard !isChild else { return }
        if didLoadList && !force { return }
        if case .loading = listState { return }
        listState = .loading
        listError = nil
        do {
            let dto = try await services.account.listSuggestions(status: filterStatus, limit: 50, offset: 0)
            items = dto.items ?? []
            total = dto.total ?? 0
            openCount = dto.counts?.open ?? 0
            readCount = dto.counts?.read ?? 0
            resolvedCount = dto.counts?.resolved ?? 0
            if let serverMax = dto.maxLength, serverMax > 0 {
                maxLength = serverMax
            }
            didLoadList = true
            listState = .loaded
        } catch let error as APIError {
            listError = ErrorMapper.message(for: error, isChild: isChild)
            listState = .failed(listError ?? ErrorMapper.message(for: error, isChild: isChild))
        } catch {
            listError = ErrorMapper.message(for: error, isChild: isChild)
            listState = .failed(listError ?? ErrorMapper.message(for: error, isChild: isChild))
        }
    }

    func mark(_ suggestionId: String, status: String) async {
        guard markingId.isEmpty else { return }
        markingId = suggestionId
        listError = nil
        defer { markingId = "" }
        do {
            try await services.account.patchSuggestionStatus(id: suggestionId, status: status)
            didLoadList = false
            await loadList(force: true)
        } catch let error as APIError {
            listError = ErrorMapper.message(for: error, isChild: isChild)
        } catch {
            listError = ErrorMapper.message(for: error, isChild: isChild)
        }
    }

    // MARK: - 导出

    func exportMarkdown() async -> Bool {
        guard !isChild, !isExporting else { return false }
        isExporting = true
        exportError = nil
        exportNotice = nil
        defer { isExporting = false }
        do {
            exportText = try await services.account.exportSuggestionsMarkdown(status: filterStatus)
            exportNotice = "已生成 Markdown，可复制给开发者"
            return true
        } catch let error as APIError {
            exportError = ErrorMapper.message(for: error, isChild: isChild)
            return false
        } catch {
            exportError = ErrorMapper.message(for: error, isChild: isChild)
            return false
        }
    }

    // MARK: - 工具

    private func localError(_ text: String) -> UIMessage {
        UIMessage(
            title: "无法提交",
            body: text,
            actionTitle: nil,
            action: UIMessage.Action.none,
            isRetryable: false,
            diagnosticID: nil
        )
    }
}
