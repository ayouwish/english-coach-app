import SwiftUI

/// 跟读页的句子列表抽屉：当前级别下的句子，当前句高亮，点击直接切句。
///
/// 数据直接复用 `PracticeStore.sentences`（不重新请求）；列表底部保留「查看全部句子」
/// 进入原来的 `.sentences` 路由（可换等级浏览）。
struct PracticeSentenceDrawer: View {
    let store: PracticeStore
    let onSelect: (Int) -> Void
    let onClose: () -> Void
    let onOpenAll: () -> Void

    @Environment(\.roleCapabilities) private var caps

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
                .overlay(Tokens.Colors.borderSubtle)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: Tokens.Spacing.s4) {
                        ForEach(Array(store.sentences.enumerated()), id: \.element.id) { index, sentence in
                            Button {
                                onSelect(index)
                            } label: {
                                row(index: index, sentence: sentence)
                            }
                            .buttonStyle(.plain)
                            .id(sentence.id)
                        }
                    }
                    .padding(.horizontal, Tokens.Spacing.s12)
                    .padding(.vertical, Tokens.Spacing.s8)
                }
                .scrollIndicators(.hidden)
                .onAppear {
                    scrollToCurrent(proxy)
                }
                .onChange(of: store.currentSentence?.id) { _, _ in
                    scrollToCurrent(proxy)
                }
            }
            footer
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: - 头部

    private var header: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s8) {
            Capsule()
                .fill(Tokens.Colors.borderSubtle)
                .frame(width: 36, height: 4)
                .frame(maxWidth: .infinity)
                .padding(.top, Tokens.Spacing.s8)
            HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.s8) {
                Text("句子列表")
                    .font(AppFont.title(caps))
                    .foregroundStyle(Tokens.Colors.textPrimary)
                Text("\(store.level) · 共 \(store.total) 句")
                    .font(AppFont.micro(caps))
                    .foregroundStyle(Tokens.Colors.textSecondary)
                Spacer(minLength: 0)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Tokens.Colors.textSecondary)
                        .frame(width: caps.minTapTarget, height: caps.minTapTarget)
                        .background(Circle().fill(Tokens.Colors.surfaceSunken))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("关闭句子列表"))
            }
        }
        .padding(.horizontal, Tokens.Spacing.s16)
        .padding(.bottom, Tokens.Spacing.s12)
        .contentShape(Rectangle())
        // 头部下拉/左滑收起（列表本身仍可正常上下滚动）。
        .gesture(
            DragGesture(minimumDistance: 12, coordinateSpace: .local)
                .onEnded { value in
                    if value.translation.height > 40 || value.translation.width < -60 {
                        onClose()
                    }
                }
        )
    }

    // MARK: - 行

    private func row(index: Int, sentence: SentenceDTO) -> some View {
        let isCurrent = sentence.id == store.currentSentence?.id
        return HStack(alignment: .top, spacing: Tokens.Spacing.s8) {
            Text("\(index + 1)")
                .font(AppFont.micro(caps).weight(.semibold).monospacedDigit())
                .foregroundStyle(isCurrent ? Tokens.Colors.onPrimary : Tokens.Colors.textSecondary)
                .frame(width: 24, height: 24)
                .background(
                    Circle().fill(isCurrent ? Tokens.Colors.primary : Tokens.Colors.surfaceSunken)
                )
            VStack(alignment: .leading, spacing: Tokens.Spacing.s2) {
                Text(sentence.text)
                    .font(AppFont.caption(caps))
                    .foregroundStyle(isCurrent ? Tokens.Colors.primary : Tokens.Colors.textPrimary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if let zh = sentence.translationZh?.trimmingCharacters(in: .whitespacesAndNewlines), !zh.isEmpty {
                    Text(zh)
                        .font(AppFont.micro(caps))
                        .foregroundStyle(Tokens.Colors.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if isCurrent {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Tokens.Colors.primary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, Tokens.Spacing.s8)
        .padding(.vertical, Tokens.Spacing.s8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Tokens.Radius.medium, style: .continuous)
                .fill(isCurrent ? Tokens.Colors.primary.opacity(0.1) : Color.clear)
        )
        .contentShape(Rectangle())
        .accessibilityLabel(Text("第 \(index + 1) 句，\(sentence.text)"))
        .accessibilityAddTraits(isCurrent ? [.isSelected] : [])
    }

    // MARK: - 底部

    private var footer: some View {
        VStack(spacing: 0) {
            Divider()
                .overlay(Tokens.Colors.borderSubtle)
            Button(action: onOpenAll) {
                HStack(spacing: Tokens.Spacing.s4) {
                    Image(systemName: "text.book.closed")
                    Text("查看全部句子 / 换等级")
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                }
                .font(AppFont.caption(caps))
                .foregroundStyle(Tokens.Colors.primary)
                .padding(.horizontal, Tokens.Spacing.s16)
                .frame(minHeight: caps.minTapTarget)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - 自动定位

    private func scrollToCurrent(_ proxy: ScrollViewProxy) {
        guard let id = store.currentSentence?.id else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(60))
            withAnimation(.easeInOut(duration: 0.2)) {
                proxy.scrollTo(id, anchor: .center)
            }
        }
    }
}
