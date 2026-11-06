import SwiftUI
import UIKit

/// 虚拟形象（契约 §3.15.1：`AvatarView(services:audio:)`）。
///
/// 对齐 HOS `AvatarPage`：不用上传照片，选预置角色 + 风格即生效；支持按性别筛选、描述编辑、清空。
/// 预置图是站内静态路径，下载后进 `ImageCache`（100MB LRU），不重复下载。
struct AvatarView: View {
    private let services: AppServices
    private let audio: AudioCoordinator

    @Environment(SessionStore.self) private var session
    @Environment(\.roleCapabilities) private var caps

    @State private var viewModel: AvatarViewModel?
    @State private var activeSheet: AvatarSheet?

    private enum AvatarSheet: String, Identifiable {
        case description
        case clear

        var id: String { rawValue }
    }

    init(services: AppServices, audio: AudioCoordinator) {
        self.services = services
        self.audio = audio
    }

    var body: some View {
        Group {
            if let viewModel {
                content(viewModel)
            } else {
                LoadingBlock(text: "正在加载形象库…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Tokens.Colors.canvas.ignoresSafeArea())
            }
        }
        .navigationTitle("我的形象")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard viewModel == nil else { return }
            let model = AvatarViewModel(services: services, audio: audio, session: session)
            await model.load()
            viewModel = model
        }
        .sheet(item: $activeSheet) { sheet in
            if let viewModel {
                switch sheet {
                case .description:
                    DescriptionSheet(viewModel: viewModel)
                case .clear:
                    ConfirmDialog(
                        title: "清空虚拟形象？",
                        message: "会清空当前形象与描述（预置静态图不会被删除），可随时重新选择。",
                        confirmTitle: "清空",
                        isDestructive: true,
                        icon: "trash",
                        onConfirm: { Task { _ = await viewModel.clear() } }
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func content(_ model: AvatarViewModel) -> some View {
        switch model.loadState {
        case .idle, .loading:
            ScrollView {
                VStack(spacing: Tokens.Spacing.s12) {
                    SkeletonBlock(height: 180)
                    SkeletonBlock(height: 120)
                }
                .padding(Tokens.Spacing.s16)
            }
            .background(Tokens.Colors.canvas.ignoresSafeArea())

        case .failed(let message):
            ErrorStateView(
                title: message.title,
                message: message.body ?? "",
                retryTitle: "重试",
                onRetry: { Task { await model.load(force: true) } }
            )
            .padding(Tokens.Spacing.s24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Tokens.Colors.canvas.ignoresSafeArea())

        case .loaded:
            ScrollView {
                VStack(alignment: .leading, spacing: Tokens.Spacing.s16) {
                    Text("不用上传照片，选一个就好；点一下立即生效，不需要生成。")
                        .font(AppFont.caption(caps))
                        .foregroundStyle(Tokens.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if model.placeholder {
                        Banner(
                            message: "当前展示的是占位图，真实插画生成后会替换。",
                            kind: .warning
                        )
                    }

                    if let error = model.error {
                        InlineErrorView(message: errorText(error))
                    }
                    if let notice = model.notice {
                        Banner(message: notice, kind: .success)
                    }

                    currentCard(model)

                    if !model.styles.isEmpty {
                        styleSection(model)
                    }

                    genderSection(model)

                    characterGrid(model)

                    Text("形象描述只用于插画提示词与形象筛选，不会展示给其他人。")
                        .font(AppFont.micro(caps))
                        .foregroundStyle(Tokens.Colors.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(Tokens.Spacing.s16)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .background(Tokens.Colors.canvas.ignoresSafeArea())
            .refreshable { await model.load(force: true) }
        }
    }

    // MARK: - 当前形象

    private func currentCard(_ model: AvatarViewModel) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s12) {
            Text("当前形象")
                .font(AppFont.heading(caps))
                .foregroundStyle(Tokens.Colors.textPrimary)

            HStack(alignment: .top, spacing: Tokens.Spacing.s16) {
                if let url = model.currentImageURL {
                    AvatarThumb(url: url, loader: { await model.imageData(for: $0) })
                        .frame(width: 96, height: 96)
                        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.medium, style: .continuous))
                } else {
                    Text(model.hasAvatar ? "🖼" : "🙂")
                        .font(.system(size: 40))
                        .frame(width: 96, height: 96)
                        .background(
                            RoundedRectangle(cornerRadius: Tokens.Radius.medium, style: .continuous)
                                .fill(Tokens.Colors.surfaceSunken)
                        )
                }

                VStack(alignment: .leading, spacing: Tokens.Spacing.s4) {
                    Text(model.hasAvatar ? "已设置形象" : "还没有选择形象")
                        .font(AppFont.bodyEmphasis(caps))
                        .foregroundStyle(Tokens.Colors.textPrimary)
                    if !model.currentDesc.isEmpty {
                        Text(model.currentDesc)
                            .font(AppFont.caption(caps))
                            .foregroundStyle(Tokens.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if model.hasAvatar && model.currentImageURL == nil {
                        Text("当前形象已设置，但图片按隐私策略不可在此展示。")
                            .font(AppFont.micro(caps))
                            .foregroundStyle(Tokens.Colors.textTertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: Tokens.Spacing.s8) {
                AppButton(title: "修改描述", icon: "text.bubble", kind: .ghost) {
                    model.descDraft = model.currentDesc
                    activeSheet = .description
                }
                if model.hasAvatar {
                    AppButton(title: "清空", icon: "trash", kind: .ghost) {
                        activeSheet = .clear
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

    // MARK: - 风格

    private func styleSection(_ model: AvatarViewModel) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s8) {
            Text("第 1 步：选风格")
                .font(AppFont.caption(caps).weight(.semibold))
                .foregroundStyle(Tokens.Colors.textSecondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Tokens.Spacing.s8) {
                    ForEach(model.styles) { style in
                        let selected = model.selectedStyle == style.id
                        Button {
                            model.selectedStyle = style.id
                        } label: {
                            Text(model.styleLabel(style.id))
                                .font(AppFont.footnote(caps).weight(.semibold))
                                .foregroundStyle(selected ? Tokens.Colors.onPrimary : Tokens.Colors.textSecondary)
                                .padding(.horizontal, Tokens.Spacing.s12)
                                .frame(minHeight: caps.minTapTarget)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(selected ? Tokens.Colors.primary : Tokens.Colors.surfaceSunken)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("风格：\(model.styleLabel(style.id))"))
                    }
                }
            }
        }
    }

    private func genderSection(_ model: AvatarViewModel) -> some View {
        Toggle(isOn: Binding(
            get: { model.showAllGender },
            set: { model.showAllGender = $0 }
        )) {
            VStack(alignment: .leading, spacing: Tokens.Spacing.s2) {
                Text("显示全部形象")
                    .font(AppFont.body(caps))
                    .foregroundStyle(Tokens.Colors.textPrimary)
                Text("默认按账号性别筛选（可在设置里修改），打开后显示全部。")
                    .font(AppFont.micro(caps))
                    .foregroundStyle(Tokens.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(Tokens.Colors.primary)
    }

    // MARK: - 角色网格

    @ViewBuilder
    private func characterGrid(_ model: AvatarViewModel) -> some View {
        let characters = model.visibleCharacters()
        if characters.isEmpty {
            EmptyStateView(
                icon: "person.crop.square",
                title: "这个分类下暂时没有可选形象",
                message: "试试切换风格，或打开「显示全部形象」。",
                actionTitle: nil,
                action: nil
            )
            .cardStyle()
        } else {
            VStack(alignment: .leading, spacing: Tokens.Spacing.s8) {
                Text("第 2 步：选角色")
                    .font(AppFont.caption(caps).weight(.semibold))
                    .foregroundStyle(Tokens.Colors.textSecondary)
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 96), spacing: Tokens.Spacing.s8)],
                    spacing: Tokens.Spacing.s8
                ) {
                    ForEach(characters) { character in
                        characterCell(model, character)
                    }
                }
            }
        }
    }

    private func characterCell(_ model: AvatarViewModel, _ character: AvatarPresetCharacterDTO) -> some View {
        let selected = model.isSelected(character)
        return Button {
            Task { await model.selectPreset(character) }
        } label: {
            VStack(spacing: Tokens.Spacing.s4) {
                if let url = model.imageURL(for: character) {
                    AvatarThumb(url: url, loader: { await model.imageData(for: $0) })
                        .frame(height: 96)
                        .frame(maxWidth: .infinity)
                } else {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 40))
                        .foregroundStyle(Tokens.Colors.textTertiary)
                        .frame(height: 96)
                        .frame(maxWidth: .infinity)
                }
                Text(character.labelZh ?? "角色")
                    .font(AppFont.micro(caps))
                    .foregroundStyle(Tokens.Colors.textPrimary)
                    .lineLimit(1)
            }
            .padding(Tokens.Spacing.s8)
            .background(
                RoundedRectangle(cornerRadius: Tokens.Radius.medium, style: .continuous)
                    .fill(selected ? Tokens.Colors.surfaceMuted : Tokens.Colors.surfaceCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Tokens.Radius.medium, style: .continuous)
                    .strokeBorder(selected ? Tokens.Colors.primary : Tokens.Colors.borderSubtle, lineWidth: selected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(model.isSavingPreset)
        .accessibilityLabel(Text(character.labelZh ?? "角色"))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func errorText(_ message: UIMessage) -> String {
        let body = message.body ?? ""
        return message.title.isEmpty ? body : "\(message.title)：\(body)"
    }
}

// MARK: - 图片（ImageCache 驱动）

private struct AvatarThumb: View {
    let url: URL?
    let loader: @MainActor (URL) async -> Data?

    @State private var data: Data?

    var body: some View {
        Group {
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 34))
                    .foregroundStyle(Tokens.Colors.textTertiary)
            }
        }
        .task(id: url) { @MainActor in
            guard let url else {
                data = nil
                return
            }
            data = await loader(url)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - 形象描述

private struct DescriptionSheet: View {
    @Bindable var viewModel: AvatarViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.roleCapabilities) private var caps

    var body: some View {
        BottomSheetContainer(title: "形象描述", subtitle: "描述得越具体，插画越像你") {
            VStack(alignment: .leading, spacing: Tokens.Spacing.s12) {
                ZStack(alignment: .topLeading) {
                    if viewModel.descDraft.isEmpty {
                        Text("例如：黑色短发、戴圆框眼镜、喜欢穿黄色卫衣。")
                            .font(AppFont.body(caps))
                            .foregroundStyle(Tokens.Colors.textTertiary)
                            .padding(.horizontal, Tokens.Spacing.s8)
                            .padding(.vertical, Tokens.Spacing.s12)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $viewModel.descDraft)
                        .font(AppFont.body(caps))
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 140)
                }
                .background(
                    RoundedRectangle(cornerRadius: Tokens.Radius.medium, style: .continuous)
                        .fill(Tokens.Colors.surfaceSunken)
                )

                if let error = viewModel.error {
                    InlineErrorView(message: error.body ?? error.title)
                }

                AppButton(
                    title: "保存描述",
                    icon: "checkmark.circle.fill",
                    isLoading: viewModel.isSavingDesc
                ) {
                    Task {
                        if await viewModel.saveDescription() {
                            dismiss()
                        }
                    }
                }
            }
        }
    }
}
