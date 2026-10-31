import SwiftUI

struct PracticeListView: View {
    @Environment(AppEnvironment.self) private var app
    @State private var viewModel: PracticeViewModel?

    var body: some View {
        Group {
            if let model = viewModel {
                PracticeContent(viewModel: model)
            } else {
                ProgressView()
                    .tint(Tokens.Colors.primary)
            }
        }
        .task {
            if viewModel == nil {
                viewModel = PracticeViewModel(app: app)
            }
        }
    }
}

private struct PracticeContent: View {
    let viewModel: PracticeViewModel

    @Environment(AppEnvironment.self) private var app
    @Environment(\.capabilities) private var caps
    @State private var showsLogoutConfirmation = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Tokens.Spacing.s20) {
                    greeting

                    if !caps.isChild {
                        levelPicker
                    }

                    content
                }
                .padding(.horizontal, Tokens.Spacing.s16)
                .padding(.vertical, Tokens.Spacing.s16)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.immediately)
            .background(Tokens.Colors.canvas.ignoresSafeArea())
            .navigationTitle("练习")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    accountMenu
                }
            }
            .navigationDestination(for: Int.self) { index in
                SentenceView(viewModel: viewModel, initialIndex: index)
            }
            .refreshable {
                await viewModel.load()
            }
            .task(id: viewModel.level) {
                await viewModel.load()
            }
        }
        .confirmationDialog(
            "要退出登录吗？",
            isPresented: $showsLogoutConfirmation,
            titleVisibility: .visible
        ) {
            Button("退出登录", role: .destructive) {
                Task { await app.signOut() }
            }
            Button("取消", role: .cancel) {}
        }
    }

    private var greeting: some View {
        HStack(alignment: .top, spacing: Tokens.Spacing.s12) {
            VStack(alignment: .leading, spacing: Tokens.Spacing.s4) {
                Text("你好，\(app.displayName.isEmpty ? "朋友" : app.displayName) \(app.currentUser?.avatarEmoji ?? "🙂")")
                    .font(AppFont.title(caps))
                    .foregroundStyle(Tokens.Colors.textPrimary)
                Text("今天想练点什么？")
                    .font(AppFont.body(caps))
                    .foregroundStyle(Tokens.Colors.textSecondary)
            }
            Spacer(minLength: 0)

            if caps.isChild {
                Text(viewModel.level)
                    .font(AppFont.caption(caps).weight(.semibold))
                    .foregroundStyle(Tokens.Colors.primary)
                    .padding(.horizontal, Tokens.Spacing.s12)
                    .padding(.vertical, Tokens.Spacing.s4)
                    .background(Capsule().fill(Tokens.Colors.surfaceMuted))
            }
        }
    }

    private var levelPicker: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s8) {
            Text("难度")
                .font(AppFont.footnote(caps).weight(.semibold))
                .foregroundStyle(Tokens.Colors.textSecondary)
            Picker(
                "难度",
                selection: Binding(
                    get: { viewModel.level },
                    set: { viewModel.level = $0 }
                )
            ) {
                ForEach(["A1", "A2", "B1", "B2", "C1"], id: \.self) { level in
                    Text(level).tag(level)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.sentences.isEmpty {
            switch viewModel.state {
            case .idle, .loading:
                loadingSkeleton
            case .failed(let error):
                ErrorStateView(
                    title: "加载失败",
                    message: error.userMessage(forChild: caps.isChild),
                    retryTitle: error.primaryActionTitle(forChild: caps.isChild),
                    onRetry: { Task { await viewModel.load() } }
                )
            case .loaded:
                EmptyStateView(
                    icon: "text.book.closed",
                    title: "这个难度还没有句子",
                    message: "换个难度，或者检查服务器上的语料库。",
                    actionTitle: "刷新",
                    action: { Task { await viewModel.load() } }
                )
            }
        } else {
            VStack(alignment: .leading, spacing: Tokens.Spacing.s12) {
                if case .failed(let error) = viewModel.state {
                    ErrorBanner(
                        message: error.userMessage(forChild: caps.isChild),
                        onRetry: { Task { await viewModel.load() } }
                    )
                }

                LazyVStack(spacing: Tokens.Spacing.s12) {
                    ForEach(viewModel.sentences.indices, id: \.self) { index in
                        NavigationLink(value: index) {
                            SentenceRow(sentence: viewModel.sentences[index])
                        }
                        .buttonStyle(.plain)
                    }
                }

                if viewModel.state == .loading {
                    HStack {
                        Spacer()
                        ProgressView().tint(Tokens.Colors.primary)
                        Spacer()
                    }
                    .padding(.vertical, Tokens.Spacing.s12)
                }
            }
        }
    }

    private var loadingSkeleton: some View {
        VStack(spacing: Tokens.Spacing.s12) {
            ForEach(0..<5, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Tokens.Radius.large, style: .continuous)
                    .fill(Tokens.Colors.surfaceSunken)
                    .frame(height: 92)
            }
        }
        .redacted(reason: .placeholder)
        .accessibilityLabel("正在加载句子")
    }

    private var accountMenu: some View {
        Menu {
            if let user = app.currentUser {
                Text(user.email)
                Text("\(user.normalizedLevel) · \(user.isChild ? "儿童" : "家长")")
            }
            Button {
                Task { await viewModel.load() }
            } label: {
                Label("重新加载", systemImage: "arrow.clockwise")
            }
            Button(role: .destructive) {
                showsLogoutConfirmation = true
            } label: {
                Label("退出登录", systemImage: "rectangle.portrait.and.arrow.right")
            }
        } label: {
            Image(systemName: "person.crop.circle")
                .font(.system(size: 22))
                .foregroundStyle(Tokens.Colors.primary)
                .frame(width: caps.minTapTarget, height: caps.minTapTarget)
        }
        .accessibilityLabel("账号")
    }
}

private struct SentenceRow: View {
    let sentence: Sentence

    @Environment(\.capabilities) private var caps

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s8) {
            Text(sentence.text)
                .font(AppFont.sentence(caps))
                .foregroundStyle(Tokens.Colors.textPrimary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            if let translation = sentence.translationZh, !translation.isEmpty {
                Text(translation)
                    .font(AppFont.body(caps))
                    .foregroundStyle(Tokens.Colors.textSecondary)
            }

            if !caps.isChild {
                HStack(spacing: Tokens.Spacing.s8) {
                    if let level = sentence.level, !level.isEmpty {
                        tag(level)
                    }
                    ForEach(sentence.focusPhonemes.prefix(3), id: \.self) { phoneme in
                        Text(phoneme)
                            .font(AppFont.ipa)
                            .foregroundStyle(Tokens.Colors.textSecondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(AppFont.caption(caps))
                        .foregroundStyle(Tokens.Colors.textTertiary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
        .accessibilityElement(children: .combine)
    }

    private func tag(_ text: String) -> some View {
        Text(text)
            .font(AppFont.caption(caps))
            .foregroundStyle(Tokens.Colors.primary)
            .padding(.horizontal, Tokens.Spacing.s8)
            .padding(.vertical, Tokens.Spacing.s2)
            .background(Capsule().fill(Tokens.Colors.surfaceMuted))
    }
}
