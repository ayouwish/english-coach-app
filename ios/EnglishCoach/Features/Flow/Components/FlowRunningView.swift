import SwiftUI

/// 连读 running：当前句录音/提交 + 进度 + 实时评分列表。
@MainActor
struct FlowRunningView: View {
    let store: FlowStore
    var onExit: () -> Void

    @Environment(\.roleCapabilities) private var caps

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Spacing.s12) {
                header
                if store.allSubmitted {
                    waitingCard
                } else {
                    currentCard
                }
                if let error = store.errorMessage {
                    errorBlock(error)
                }
                Text("实时评分（点一行展开详情）")
                    .font(AppFont.caption(caps))
                    .foregroundStyle(Tokens.Colors.textSecondary)
                    .padding(.top, Tokens.Spacing.s4)
                LazyVStack(spacing: Tokens.Spacing.s8) {
                    ForEach(store.items) { item in
                        FlowItemRow(
                            item: item,
                            badge: store.statusBadge(item),
                            tone: store.statusTone(item),
                            isExpanded: store.expandedIndex == item.index,
                            onTap: { store.toggleExpanded(index: item.index) },
                            onRetry: { store.retryItem(index: item.index) }
                        )
                    }
                }
            }
            .padding(.horizontal, Tokens.Spacing.pageMargin(isChild: caps.isChild))
            .padding(.vertical, Tokens.Spacing.s16)
            .contentColumn(alignment: .center)
        }
    }

    // MARK: - 页头

    private var header: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s8) {
            HStack(spacing: Tokens.Spacing.s8) {
                Button(action: onExit) {
                    Text("‹ 重新选句")
                        .font(AppFont.caption(caps).weight(.semibold))
                        .foregroundStyle(Tokens.Colors.primary)
                        .frame(minHeight: caps.minTapTarget)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("退出连读，重新选句"))

                Text(caps.isChild ? "🔗 一句一句读" : "🔗 连读模式")
                    .font(AppFont.heading(caps))
                    .foregroundStyle(Tokens.Colors.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text("第 \(min(store.currentIndex + 1, store.items.count)) / \(store.items.count) 句")
                    .font(AppFont.caption(caps).weight(.medium))
                    .foregroundStyle(Tokens.Colors.primary)
                    .padding(.horizontal, Tokens.Spacing.s8)
                    .padding(.vertical, Tokens.Spacing.s2)
                    .background(Capsule(style: .continuous).fill(Tokens.Colors.surfaceMuted))
            }

            ProgressView(value: Double(store.progressPercent), total: 100)
                .tint(Tokens.Colors.primary)

            Button {
                store.autoNext.toggle()
            } label: {
                HStack(spacing: Tokens.Spacing.s8) {
                    Image(systemName: store.autoNext ? "checkmark.square.fill" : "square")
                        .foregroundStyle(Tokens.Colors.primary)
                    Text(caps.isChild ? "读完自动跳到下一句" : "录完后自动进入下一句（400ms 缓冲）")
                        .font(AppFont.micro(caps))
                        .foregroundStyle(Tokens.Colors.textSecondary)
                    Spacer(minLength: 0)
                }
                .frame(minHeight: caps.minTapTarget)
            }
            .buttonStyle(.plain)

            if let limit = store.limitMessage {
                Banner(
                    message: [limit.title, limit.body].compactMap { $0 }.joined(separator: " "),
                    kind: .warning,
                    icon: "moon.zzz.fill"
                )
            }
        }
    }

    // MARK: - 当前句

    private var currentCard: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s12) {
            if let item = store.currentItem {
                WordTextView(
                    text: item.text,
                    showIPA: caps.canSeeIPA,
                    onTapWord: caps.canSeeIPA ? { _ in } : nil
                )
            }

            if store.recording || store.preparing || store.uploadingCount > 0 || store.isPlayingDemo {
                HStack(spacing: Tokens.Spacing.s8) {
                    if store.preparing || store.uploadingCount > 0 {
                        ProgressView().controlSize(.small).tint(Tokens.Colors.primary)
                    }
                    Text(store.recording
                        ? "正在听你说…读完点「说完啦」"
                        : (store.preparing
                            ? "正在打开麦克风…"
                            : (store.isPlayingDemo ? "正在播放示范音…" : "正在上传…")))
                        .font(AppFont.caption(caps))
                        .foregroundStyle(store.recording ? Tokens.Colors.warningText : Tokens.Colors.primary)
                }
            }

            if let item = store.currentItem {
                if store.recording {
                    HStack(spacing: Tokens.Spacing.s8) {
                        AppButton(
                            title: "⏹ 说完啦 \(store.elapsedMs / 1000)s",
                            kind: .danger,
                            action: { Task { await store.stopAndSubmit() } }
                        )
                        AppButton(title: "✖️ 不要了", kind: .ghost) {
                            Task { await store.cancelRecording() }
                        }
                    }
                } else if item.status == .unsent {
                    // 与跟读页一致：听示范 / 跟我读 / 开始说 三个动作都在当前卡片上。
                    VStack(spacing: Tokens.Spacing.s8) {
                        HStack(spacing: Tokens.Spacing.s8) {
                            AppButton(
                                title: "🔊 听示范",
                                kind: .tonal,
                                isLoading: store.isPreparingDemo,
                                isEnabled: !store.preparing,
                                action: { store.playDemo(autoRecord: false) }
                            )
                            AppButton(
                                title: "🎧 跟我读",
                                kind: .tonal,
                                isEnabled: !store.preparing && !store.limitReached,
                                action: { store.playDemo(autoRecord: true) }
                            )
                        }
                        AppButton(
                            title: store.preparing ? "麦克风准备中…" : "🎤 开始说",
                            isLoading: store.preparing,
                            isEnabled: !store.limitReached,
                            action: { Task { await store.startRecording() } }
                        )
                    }
                } else if store.hasNextUnsentHint {
                    AppButton(title: "下一句 →", kind: .tonal) {
                        store.nextSentence()
                    }
                }
            }

            let statusLine = store.currentStatusLine()
            if !statusLine.isEmpty {
                Text(statusLine)
                    .font(AppFont.caption(caps))
                    .foregroundStyle(Tokens.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Tokens.Spacing.s16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private var waitingCard: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s8) {
            Text("全部读完啦，正在后台评分…")
                .font(AppFont.bodyEmphasis(caps))
                .foregroundStyle(Tokens.Colors.textPrimary)
            Text("已评分 \(store.doneCount) 句 · 待评分 \(store.pendingCount) 句 · 失败 \(store.failedCount) 句")
                .font(AppFont.caption(caps))
                .foregroundStyle(Tokens.Colors.textSecondary)
            Text("评分完成后会自动跳到汇总页，不用一直等在这里。")
                .font(AppFont.micro(caps))
                .foregroundStyle(Tokens.Colors.textTertiary)
        }
        .padding(Tokens.Spacing.s16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func errorBlock(_ error: UIMessage) -> some View {
        InlineErrorView(
            message: [error.title, error.body].compactMap { $0 }.joined(separator: " "),
            retryTitle: error.actionTitle,
            onRetry: { store.clearError() }
        )
    }
}

// MARK: - 便捷派生

@MainActor
extension FlowStore {
    /// 当前句已提交/失败，且还有未读句子 → 显示「下一句 →」。
    var hasNextUnsentHint: Bool {
        guard let current = currentItem else { return false }
        guard current.status != .unsent else { return false }
        return items.contains { $0.status == .unsent }
    }
}
