import SwiftUI

/// 音色（契约 §3.15.1：`VoicesView(services:audio:)`）。
///
/// 9 个内置音色（英/中分组）+ 试听 + 保存到 `settings.tts_voice`；
/// 默认音色（provider 决定）单独一行。试听走 `POST /tts`，播放由 `AudioCoordinator` 统一管理。
struct VoicesView: View {
    private let services: AppServices
    private let audio: AudioCoordinator

    @Environment(SessionStore.self) private var session
    @Environment(\.roleCapabilities) private var caps

    @State private var viewModel: VoicesViewModel?

    init(services: AppServices, audio: AudioCoordinator) {
        self.services = services
        self.audio = audio
    }

    var body: some View {
        Group {
            if let viewModel {
                content(viewModel)
            } else {
                LoadingBlock(text: "正在加载音色…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Tokens.Colors.canvas.ignoresSafeArea())
            }
        }
        .navigationTitle("音色")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard viewModel == nil else { return }
            let model = VoicesViewModel(services: services, audio: audio, session: session)
            await model.load()
            viewModel = model
        }
        .onDisappear {
            if let viewModel {
                Task { await viewModel.stopPreview() }
            }
        }
    }

    @ViewBuilder
    private func content(_ model: VoicesViewModel) -> some View {
        switch model.loadState {
        case .idle, .loading:
            ScrollView {
                VStack(spacing: Tokens.Spacing.s12) {
                    SkeletonBlock(height: 72)
                    SkeletonBlock(height: 72)
                    SkeletonBlock(height: 72)
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
                    Text("练习示范音、对话朗读、鼓励音都会用它。默认音色由语音服务决定；试听会临时合成一小段话。")
                        .font(AppFont.caption(caps))
                        .foregroundStyle(Tokens.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let error = model.previewError {
                        InlineErrorView(message: errorText(error))
                    }
                    if let error = model.saveError {
                        InlineErrorView(message: errorText(error))
                    }
                    if let notice = model.notice {
                        Banner(message: notice, kind: .success)
                    }

                    defaultVoiceRow(model)

                    group("英语音色", voices: model.englishVoices, model: model)
                    group("中文音色", voices: model.chineseVoices, model: model)

                    Text("提示：慢速更清楚，但合成耗时更长；音色偏好保存后对所有页面生效。")
                        .font(AppFont.micro(caps))
                        .foregroundStyle(Tokens.Colors.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(Tokens.Spacing.s16)
                .contentColumn(alignment: .center)
            }
            .background(Tokens.Colors.canvas.ignoresSafeArea())
            .refreshable { await model.load(force: true) }
        }
    }

    private func defaultVoiceRow(_ model: VoicesViewModel) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s8) {
            HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.s8) {
                Text("默认音色（provider 决定）")
                    .font(AppFont.bodyEmphasis(caps))
                    .foregroundStyle(Tokens.Colors.textPrimary)
                if model.currentVoice.isEmpty {
                    PillTag(text: "当前使用", tone: .success)
                }
                Spacer(minLength: 0)
            }
            Text("不指定 voice，由语音服务选择最合适的音色。")
                .font(AppFont.caption(caps))
                .foregroundStyle(Tokens.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            AppButton(
                title: model.currentVoice.isEmpty ? "正在使用" : "使用默认音色",
                kind: .ghost,
                isLoading: model.isSaving,
                isEnabled: !model.currentVoice.isEmpty || model.isSaving
            ) {
                Task { _ = await model.save("") }
            }
        }
        .padding(Tokens.Spacing.s16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Tokens.Radius.large, style: .continuous)
                .fill(Tokens.Colors.surfaceCard)
        )
    }

    private func group(_ title: String, voices: [VoiceOption], model: VoicesViewModel) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s8) {
            Text(title)
                .font(AppFont.caption(caps).weight(.semibold))
                .foregroundStyle(Tokens.Colors.textSecondary)
                .padding(.leading, Tokens.Spacing.s4)
            ForEach(voices) { voice in
                voiceRow(voice, model: model)
            }
        }
    }

    private func voiceRow(_ voice: VoiceOption, model: VoicesViewModel) -> some View {
        let isCurrent = model.currentVoice == voice.id
        let isPreviewing = model.previewingId == voice.id
        return VStack(alignment: .leading, spacing: Tokens.Spacing.s8) {
            HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.s8) {
                Text(voice.labelZh)
                    .font(AppFont.bodyEmphasis(caps))
                    .foregroundStyle(Tokens.Colors.textPrimary)
                if isCurrent {
                    PillTag(text: "当前使用", tone: .success)
                }
                Spacer(minLength: 0)
            }
            if let sample = voice.sample, !sample.isEmpty {
                Text(sample)
                    .font(AppFont.micro(caps))
                    .foregroundStyle(Tokens.Colors.textSecondary)
                    .lineLimit(2)
            }
            HStack(spacing: Tokens.Spacing.s8) {
                AppButton(
                    title: isPreviewing ? "停止试听" : "试听",
                    icon: isPreviewing ? "stop.fill" : "play.fill",
                    kind: .ghost,
                    isLoading: isPreviewing && model.isSynthesizing
                ) {
                    Task { await model.togglePreview(voice) }
                }
                AppButton(
                    title: isCurrent ? "已选择" : "使用这个音色",
                    icon: "checkmark.circle",
                    kind: isCurrent ? .text : .tonal,
                    isLoading: model.isSaving,
                    isEnabled: !isCurrent
                ) {
                    Task { _ = await model.save(voice.id) }
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
