import SwiftUI

/// 连读 setup：来源（语料 / 自己输入）、等级、句数、随机、预览、开始。
@MainActor
struct FlowSetupView: View {
    let store: FlowStore

    @Environment(\.roleCapabilities) private var caps

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Spacing.s12) {
                header

                VStack(alignment: .leading, spacing: Tokens.Spacing.s12) {
                    sourceTabs
                    if store.source == .corpus {
                        corpusPanel
                    } else if store.source == .materials {
                        materialsPanel
                    } else {
                        customPanel
                    }
                    if let setupError = store.setupError, !setupError.isEmpty {
                        Banner(message: setupError, kind: .warning)
                    }
                }
                .padding(Tokens.Spacing.s16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardStyle()

                Text("连读是一句一个文件、一次提交；录完立刻进入下一句，评分在后台排队。")
                    .font(AppFont.micro(caps))
                    .foregroundStyle(Tokens.Colors.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(.horizontal, Tokens.Spacing.pageMargin(isChild: caps.isChild))
            .padding(.vertical, Tokens.Spacing.s16)
            .contentColumn(alignment: .center)
        }
        .task {
            if store.source == .materials {
                await store.loadMaterials()
            }
        }
    }

    // MARK: - 我的书页

    @ViewBuilder
    private var materialsPanel: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s12) {
            if store.materialsLoading {
                LoadingBlock(text: "正在取我的书页…")
            } else if let error = store.materialsError {
                ErrorBanner(
                    message: [error.title, error.body].compactMap { $0 }.joined(separator: " "),
                    onRetry: { Task { await store.loadMaterials(force: true) } }
                )
            } else if store.flowMaterials.isEmpty {
                EmptyStateView(
                    icon: "book.closed",
                    title: "还没有书页",
                    message: "去「故事」页讲一个故事，或用拍书页存一篇，就能在这里逐句连读。",
                    actionTitle: "刷新",
                    action: { Task { await store.loadMaterials(force: true) } }
                )
            } else {
                ForEach(store.flowMaterials, id: \.id) { material in
                    HStack(alignment: .center, spacing: Tokens.Spacing.s8) {
                        VStack(alignment: .leading, spacing: Tokens.Spacing.s2) {
                            Text(material.title ?? "未命名故事")
                                .font(AppFont.bodyEmphasis(caps))
                                .foregroundStyle(Tokens.Colors.textPrimary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            Text(materialMeta(material))
                                .font(AppFont.micro(caps))
                                .foregroundStyle(Tokens.Colors.textSecondary)
                        }
                        Spacer(minLength: 0)
                        AppButton(title: "读这篇", kind: .tonal) {
                            Task { await store.startMaterial(material) }
                        }
                    }
                    .padding(Tokens.Spacing.s12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: Tokens.Radius.medium, style: .continuous)
                            .fill(Tokens.Colors.surfaceSunken)
                    )
                }
            }
        }
    }

    private func materialMeta(_ material: StoryMaterialDTO) -> String {
        var parts: [String] = []
        if let count = material.sentenceCount, count > 0 {
            parts.append("\(count) 句")
        }
        if let level = material.level, !level.isEmpty {
            parts.append(level)
        }
        if let name = material.createdByName, !name.isEmpty {
            parts.append(name)
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - 页头

    private var header: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s4) {
            Text(caps.isChild ? "🔗 一口气读好多句" : "🔗 连读模式")
                .font(AppFont.title(caps))
                .foregroundStyle(Tokens.Colors.textPrimary)
            Text(caps.isChild
                ? "读完一句就自动跳到下一句，不用等评分。读完后分数会自己出现在下面的列表里。"
                : "逐句连读：录完一句立刻进入下一句，评分在后台排队，结果陆续显示。")
                .font(AppFont.caption(caps))
                .foregroundStyle(Tokens.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 来源

    private var sourceTabs: some View {
        HStack(spacing: Tokens.Spacing.s8) {
            ForEach(store.sourceOptions) { option in
                Button {
                    store.setSource(option)
                } label: {
                    Text(option.title)
                        .font(AppFont.caption(caps).weight(.medium))
                        .foregroundStyle(store.source == option ? Tokens.Colors.onPrimary : Tokens.Colors.textSecondary)
                        .padding(.horizontal, Tokens.Spacing.s12)
                        .frame(minHeight: caps.minTapTarget)
                        .background(
                            Capsule(style: .continuous)
                                .fill(store.source == option ? Tokens.Colors.primary : Tokens.Colors.surfaceSunken)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(option.title))
            }
        }
    }

    // MARK: - 语料

    private var corpusPanel: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s12) {
            levelRow

            switch store.corpusPhase {
            case .idle, .loading:
                LoadingBlock(text: "正在取句子…")
            case .failed:
                if let error = store.corpusError {
                    ErrorBanner(
                        message: [error.title, error.body].compactMap { $0 }.joined(separator: " "),
                        onRetry: { Task { await store.loadCorpus(force: true) } }
                    )
                }
            default:
                if store.corpusSentences.isEmpty {
                    EmptyStateView(
                        icon: "text.book.closed",
                        title: "这个等级还没有句子",
                        message: "换个等级看看。",
                        actionTitle: "刷新",
                        action: { Task { await store.loadCorpus(force: true) } }
                    )
                } else {
                    countRow
                    randomRow
                    if !store.randomMode {
                        startIndexRow
                    }
                    previewList
                    AppButton(
                        title: "🎤 开始连读（\(store.preview.count) 句）",
                        isEnabled: !store.preview.isEmpty
                    ) {
                        store.startCorpus()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var levelRow: some View {
        if caps.canChangeLevel {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Tokens.Spacing.s8) {
                    ForEach(store.levels, id: \.self) { level in
                        Button {
                            store.setLevel(level)
                        } label: {
                            Text(level == "ALL" ? "全部" : level)
                                .font(AppFont.caption(caps).weight(.medium))
                                .foregroundStyle(store.level == level ? Tokens.Colors.onPrimary : Tokens.Colors.textSecondary)
                                .padding(.horizontal, Tokens.Spacing.s12)
                                .frame(minHeight: caps.minTapTarget)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(store.level == level ? Tokens.Colors.primary : Tokens.Colors.surfaceSunken)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("等级 \(level)"))
                    }
                }
            }
        } else {
            HStack(spacing: Tokens.Spacing.s8) {
                PillTag(text: store.level == "ALL" ? "全部" : store.level, tone: .primary)
                Text("等级由家长设置")
                    .font(AppFont.caption(caps))
                    .foregroundStyle(Tokens.Colors.textSecondary)
            }
        }
    }

    private var countRow: some View {
        HStack(spacing: Tokens.Spacing.s8) {
            Text("读")
                .font(AppFont.caption(caps))
                .foregroundStyle(Tokens.Colors.textSecondary)
            ForEach(store.counts, id: \.self) { value in
                Button {
                    store.setCount(value)
                } label: {
                    Text("\(value) 句")
                        .font(AppFont.caption(caps))
                        .foregroundStyle(store.count == value ? Tokens.Colors.onPrimary : Tokens.Colors.textSecondary)
                        .padding(.horizontal, Tokens.Spacing.s8)
                        .frame(minHeight: caps.minTapTarget)
                        .background(
                            RoundedRectangle(cornerRadius: Tokens.Radius.small, style: .continuous)
                                .fill(store.count == value ? Tokens.Colors.primary : Tokens.Colors.surfaceSunken)
                        )
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }

    private var randomRow: some View {
        HStack(spacing: Tokens.Spacing.s8) {
            Text("共 \(store.levelPoolSize) 句")
                .font(AppFont.caption(caps))
                .foregroundStyle(Tokens.Colors.textSecondary)
            Spacer(minLength: 0)
            Button {
                store.setRandomMode(!store.randomMode)
            } label: {
                Text(store.randomMode ? "🎲 随机 ✓" : "🎲 随机")
                    .font(AppFont.caption(caps))
                    .foregroundStyle(Tokens.Colors.primary)
                    .frame(minHeight: caps.minTapTarget)
            }
            .buttonStyle(.plain)
            if store.randomMode {
                Button {
                    store.drawRandomSentences()
                } label: {
                    Text("🔀 换一批")
                        .font(AppFont.caption(caps))
                        .foregroundStyle(Tokens.Colors.primary)
                        .frame(minHeight: caps.minTapTarget)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var startIndexRow: some View {
        Stepper(
            value: Binding(
                get: { store.startIndex },
                set: { store.setStartIndex($0) }
            ),
            in: 0...max(store.levelPoolSize - 1, 0)
        ) {
            Text("从第 \(store.startIndex + 1) 句开始")
                .font(AppFont.caption(caps))
                .foregroundStyle(Tokens.Colors.textSecondary)
        }
    }

    private var previewList: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s4) {
            ForEach(Array(store.preview.prefix(8).enumerated()), id: \.offset) { pair in
                Text("\(pair.offset + 1). \(pair.element.text)")
                    .font(AppFont.caption(caps))
                    .foregroundStyle(Tokens.Colors.textPrimary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if store.preview.isEmpty {
                Text("这个位置没有句子")
                    .font(AppFont.caption(caps))
                    .foregroundStyle(Tokens.Colors.textSecondary)
            }
        }
        .padding(Tokens.Spacing.s12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Tokens.Radius.medium, style: .continuous)
                .fill(Tokens.Colors.surfaceSunken)
        )
    }

    // MARK: - 自己输入

    private var customPanel: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s12) {
            TextField(
                "把想读的英文段落贴进来（会按 . ! ? 。！？ 自动切句）",
                text: Binding(
                    get: { store.customInput },
                    set: { store.setCustomInput($0) }
                ),
                axis: .vertical
            )
            .font(AppFont.body(caps))
            .lineLimit(4...10)
            .padding(Tokens.Spacing.s12)
            .background(
                RoundedRectangle(cornerRadius: Tokens.Radius.medium, style: .continuous)
                    .fill(Tokens.Colors.surfaceSunken)
            )

            HStack(spacing: Tokens.Spacing.s8) {
                AppButton(title: "✂️ 切句", kind: .tonal) {
                    store.splitCustom()
                }
                Text("切出 \(store.customSentences.count) 句（可逐句修改后再开始）")
                    .font(AppFont.micro(caps))
                    .foregroundStyle(Tokens.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(Array(store.customSentences.enumerated()), id: \.offset) { pair in
                HStack(spacing: Tokens.Spacing.s8) {
                    Text("\(pair.offset + 1)")
                        .font(AppFont.micro(caps))
                        .foregroundStyle(Tokens.Colors.textSecondary)
                        .frame(width: 20, alignment: .trailing)
                    TextField(
                        "第 \(pair.offset + 1) 句",
                        text: Binding(
                            get: {
                                store.customSentences.indices.contains(pair.offset) ? store.customSentences[pair.offset] : pair.element
                            },
                            set: { store.updateCustomSentence(index: pair.offset, text: $0) }
                        )
                    )
                    .font(AppFont.caption(caps))
                    .padding(Tokens.Spacing.s8)
                    .background(
                        RoundedRectangle(cornerRadius: Tokens.Radius.small, style: .continuous)
                            .fill(Tokens.Colors.surfaceSunken)
                    )
                }
            }

            AppButton(
                title: "🎤 开始连读（\(store.customSentences.count) 句）",
                isEnabled: !store.customSentences.isEmpty
            ) {
                store.startCustom()
            }
        }
    }
}
