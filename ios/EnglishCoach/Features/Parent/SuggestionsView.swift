import SwiftUI
import UIKit

/// 建议箱 / 我想说（契约 §3.15.1：`SuggestionsView(services:audio:)`）。
/// 儿童只看到提交表单（3 个分类）；家长额外看到列表、状态筛选、标记已读/已解决与 Markdown 导出。
struct SuggestionsView: View {
    private let services: AppServices
    private let audio: AudioCoordinator

    @Environment(SessionStore.self) private var session
    @Environment(\.roleCapabilities) private var caps

    @State private var viewModel: SuggestionsViewModel?
    @State private var showsExport = false

    init(services: AppServices, audio: AudioCoordinator) {
        self.services = services
        self.audio = audio
    }

    var body: some View {
        Group {
            if let viewModel {
                content(viewModel)
            } else {
                LoadingBlock(text: "正在加载建议箱…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Tokens.Colors.canvas.ignoresSafeArea())
            }
        }
        .navigationTitle(viewModel?.title ?? "建议箱")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard viewModel == nil else { return }
            let model = SuggestionsViewModel(services: services, audio: audio, session: session)
            await model.loadList()
            viewModel = model
        }
        .sheet(isPresented: $showsExport) {
            if let viewModel {
                ExportSheet(viewModel: viewModel)
            }
        }
    }

    private func content(_ model: SuggestionsViewModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Spacing.s16) {
                Text(model.subtitle)
                    .font(AppFont.caption(caps))
                    .foregroundStyle(Tokens.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                composeCard(model)

                if !model.isChild {
                    countsRow(model)
                    filterRow(model)
                    listSection(model)
                }
            }
            .padding(Tokens.Spacing.s16)
            .contentColumn(alignment: .center)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Tokens.Colors.canvas.ignoresSafeArea())
        .refreshable {
            await model.loadList(force: true)
        }
    }

    // MARK: - 提交

    private func composeCard(_ model: SuggestionsViewModel) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s12) {
            Text("写点什么")
                .font(AppFont.heading(caps))
                .foregroundStyle(Tokens.Colors.textPrimary)

            Picker("分类", selection: Binding(
                get: { model.category },
                set: { model.category = $0 }
            )) {
                ForEach(model.categories) { category in
                    Text(model.isChild ? category.childLabel : category.adultLabel).tag(category.key)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)

            ZStack(alignment: .topLeading) {
                if model.content.isEmpty {
                    Text("比如：/θ/ 的评分总是偏低；希望故事可以选更长的。")
                        .font(AppFont.body(caps))
                        .foregroundStyle(Tokens.Colors.textTertiary)
                        .padding(.horizontal, Tokens.Spacing.s8)
                        .padding(.vertical, Tokens.Spacing.s12)
                        .allowsHitTesting(false)
                }
                TextEditor(text: Binding(
                    get: { model.content },
                    set: { model.content = $0 }
                ))
                .font(AppFont.body(caps))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 120)
            }
            .background(
                RoundedRectangle(cornerRadius: Tokens.Radius.medium, style: .continuous)
                    .fill(Tokens.Colors.surfaceSunken)
            )

            HStack {
                Text("\(model.content.count) / \(model.maxLength) 字")
                    .font(AppFont.micro(caps))
                    .foregroundStyle(Tokens.Colors.textTertiary)
                Spacer(minLength: 0)
            }

            if let error = model.createError {
                InlineErrorView(message: errorText(error))
            }
            if let notice = model.createNotice {
                Banner(message: notice, kind: .success)
            }

            AppButton(
                title: model.isChild ? "告诉爸爸妈妈" : "提交建议",
                icon: "paperplane.fill",
                isLoading: model.isSubmitting
            ) {
                Task { await model.submit() }
            }
        }
        .padding(Tokens.Spacing.s16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Tokens.Radius.large, style: .continuous)
                .fill(Tokens.Colors.surfaceCard)
        )
    }

    // MARK: - 家长：统计 / 筛选 / 列表

    private func countsRow(_ model: SuggestionsViewModel) -> some View {
        HStack(spacing: Tokens.Spacing.s8) {
            PillTag(text: "未读 \(model.openCount)", tone: .warning)
            PillTag(text: "已读 \(model.readCount)", tone: .primary)
            PillTag(text: "已解决 \(model.resolvedCount)", tone: .success)
            Spacer(minLength: 0)
            Button {
                Task {
                    if await model.exportMarkdown() {
                        showsExport = true
                    }
                }
            } label: {
                HStack(spacing: Tokens.Spacing.s4) {
                    if model.isExporting {
                        ProgressView().controlSize(.small)
                    }
                    Text(model.isExporting ? "导出中…" : "导出 Markdown")
                }
                .font(AppFont.footnote(caps).weight(.semibold))
                .foregroundStyle(Tokens.Colors.primary)
                .frame(minHeight: caps.minTapTarget)
            }
            .buttonStyle(.plain)
        }
    }

    private func filterRow(_ model: SuggestionsViewModel) -> some View {
        Picker("状态筛选", selection: Binding(
            get: { model.filterStatus },
            set: { value in Task { await model.setFilter(value) } }
        )) {
            ForEach(SuggestionsViewModel.statusFilters) { item in
                Text(item.label).tag(item.key)
            }
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private func listSection(_ model: SuggestionsViewModel) -> some View {
        switch model.listState {
        case .idle, .loading:
            LoadingBlock(text: "正在加载建议…")
        case .failed(let message):
            ErrorStateView(
                title: message.title,
                message: message.body ?? "",
                retryTitle: "重试",
                onRetry: { Task { await model.loadList(force: true) } }
            )
            .cardStyle()
        case .loaded:
            if model.items.isEmpty {
                EmptyStateView(
                    icon: "tray",
                    title: "这里还没有建议",
                    message: "家人用的时候可以在这里随手留言。",
                    actionTitle: nil,
                    action: nil
                )
                .cardStyle()
            } else {
                if let error = model.listError {
                    InlineErrorView(message: errorText(error))
                }
                ForEach(model.items, id: \.id) { item in
                    suggestionRow(model, item)
                }
            }
        }
    }

    private func suggestionRow(_ model: SuggestionsViewModel, _ item: SuggestionDTO) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s8) {
            HStack(spacing: Tokens.Spacing.s8) {
                PillTag(text: model.categoryLabel(item.category), tone: .neutral)
                PillTag(text: model.statusLabel(item.status), tone: model.statusTone(item.status))
                PillTag(text: model.roleLabel(item.userRole), tone: .primary)
                Spacer(minLength: 0)
                Text(model.relativeTime(item.createdAt))
                    .font(AppFont.micro(caps))
                    .foregroundStyle(Tokens.Colors.textTertiary)
            }
            Text(item.content ?? "")
                .font(AppFont.body(caps))
                .foregroundStyle(Tokens.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Tokens.Spacing.s8) {
                if item.status != "read" && item.status != "resolved" {
                    AppButton(title: "标记已读", kind: .ghost, isLoading: model.markingId == item.id) {
                        Task { await model.mark(item.id, status: "read") }
                    }
                }
                if item.status != "resolved" {
                    AppButton(title: "标记已解决", kind: .ghost, isLoading: model.markingId == item.id) {
                        Task { await model.mark(item.id, status: "resolved") }
                    }
                }
            }
        }
        .padding(Tokens.Spacing.s16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Tokens.Radius.large, style: .continuous)
                .fill(Tokens.Colors.surfaceCard)
        )
    }

    private func errorText(_ message: UIMessage) -> String {
        let body = message.body ?? ""
        return message.title.isEmpty ? body : "\(message.title)：\(body)"
    }
}

// MARK: - 导出

private struct ExportSheet: View {
    let viewModel: SuggestionsViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.roleCapabilities) private var caps
    @State private var copied = false

    var body: some View {
        BottomSheetContainer(title: "Markdown 导出", subtitle: "可复制给开发者继续优化") {
            VStack(alignment: .leading, spacing: Tokens.Spacing.s12) {
                if let error = viewModel.exportError {
                    InlineErrorView(message: error.body ?? error.title)
                }
                ScrollView {
                    Text(viewModel.exportText)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(Tokens.Colors.textPrimary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 320)
                .padding(Tokens.Spacing.s12)
                .background(
                    RoundedRectangle(cornerRadius: Tokens.Radius.medium, style: .continuous)
                        .fill(Tokens.Colors.surfaceSunken)
                )

                if let notice = viewModel.exportNotice {
                    Text(notice)
                        .font(AppFont.micro(caps))
                        .foregroundStyle(Tokens.Colors.textSecondary)
                }

                AppButton(title: copied ? "已复制" : "一键复制", icon: "doc.on.doc") {
                    UIPasteboard.general.string = viewModel.exportText
                    copied = true
                }
                AppButton(title: "关闭", kind: .text) {
                    dismiss()
                }
            }
        }
    }
}
