import SwiftUI

/// 「我的」Tab（契约 §3.15.1：`MeView(services:audio:)`）。
///
/// 内容：账号卡（头像/昵称/角色/等级/今日用量）+ 学习入口 + 偏好入口 + 家长区 + 服务状态 + 退出登录。
/// 儿童隐藏家长面板/家庭成员入口（只留“我想说”给家长提建议），符合 screens.md §14。
struct MeView: View {
    private let services: AppServices
    private let audio: AudioCoordinator

    @Environment(SessionStore.self) private var session
    @Environment(AppRouter.self) private var router
    @Environment(\.roleCapabilities) private var caps

    @State private var viewModel: MeViewModel?
    @State private var showsSignOutConfirm = false

    init(services: AppServices, audio: AudioCoordinator) {
        self.services = services
        self.audio = audio
    }

    var body: some View {
        Group {
            if let viewModel {
                content(viewModel)
            } else {
                LoadingBlock(text: "正在加载账号…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Tokens.Colors.canvas.ignoresSafeArea())
            }
        }
        .task {
            guard viewModel == nil else { return }
            viewModel = MeViewModel(services: services, audio: audio, session: session)
        }
    }

    private func content(_ model: MeViewModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Spacing.s16) {
                accountCard(model)

                groupTitle("学习")
                card {
                    InfoRow(icon: "waveform.path.ecg", title: "发音诊断", detail: "最薄弱的音素与建议", showsChevron: true) {
                        router.push(.diagnosis)
                    }
                    divider
                    InfoRow(icon: "book.closed", title: "错音本", detail: "按记忆曲线复习读错的音", showsChevron: true) {
                        router.push(.review)
                    }
                    divider
                    InfoRow(icon: "theatermasks", title: "盲测周报", detail: "每周一次，只统计已评分", showsChevron: true) {
                        router.push(.blindTest)
                    }
                }

                groupTitle("偏好")
                card {
                    InfoRow(icon: "gearshape", title: "设置", detail: "偏好、服务器、缓存、退出", showsChevron: true) {
                        router.push(.settings)
                    }
                    divider
                    InfoRow(icon: "speaker.wave.2", title: "音色", detail: "9 种音色，可试听", showsChevron: true) {
                        router.push(.voices)
                    }
                    divider
                    InfoRow(icon: "paintpalette", title: "我的形象", detail: "预置形象选择题", showsChevron: true) {
                        router.push(.avatar)
                    }
                }

                if session.isChild {
                    groupTitle("家长")
                    card {
                        InfoRow(icon: "lightbulb", title: "我想说", detail: "给爸爸妈妈提个建议", showsChevron: true) {
                            router.push(.suggestions)
                        }
                    }
                } else {
                    groupTitle("家长")
                    card {
                        InfoRow(icon: "person.2", title: "家长面板", detail: "使用时长 / 趋势 / 掌握度", showsChevron: true) {
                            router.push(.parent)
                        }
                        divider
                        InfoRow(icon: "person.3", title: "家庭成员", detail: "建账号、改水平、重置密码", showsChevron: true) {
                            router.push(.family)
                        }
                        divider
                        InfoRow(icon: "tray.full", title: "建议箱", detail: "家人提的建议都在这里", showsChevron: true) {
                            router.push(.suggestions)
                        }
                    }
                }

                groupTitle("服务")
                card {
                    InfoRow(icon: "stethoscope", title: "服务状态", detail: "家庭 NAS / 语音能力自查", showsChevron: true) {
                        router.push(.health)
                    }
                }

                footer(model)

                AppButton(title: "退出登录", icon: "rectangle.portrait.and.arrow.right", kind: .ghost) {
                    showsSignOutConfirm = true
                }
                .padding(.top, Tokens.Spacing.s8)
            }
            .padding(.horizontal, Tokens.Spacing.s16)
            .padding(.vertical, Tokens.Spacing.s16)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Tokens.Colors.canvas.ignoresSafeArea())
        .refreshable { await model.refresh() }
        .sheet(isPresented: $showsSignOutConfirm) {
            ConfirmDialog(
                title: "退出登录？",
                message: "退出后需要重新输入邮箱和密码；本机的示范音、图片与录音副本会被清理。",
                confirmTitle: "退出登录",
                isDestructive: true,
                icon: "rectangle.portrait.and.arrow.right",
                onConfirm: { Task { await model.signOut() } }
            )
        }
    }

    // MARK: - 账号卡

    private func accountCard(_ model: MeViewModel) -> some View {
        HStack(alignment: .center, spacing: Tokens.Spacing.s16) {
            Text(model.avatarEmoji)
                .font(.system(size: 30, weight: .bold))
                .frame(width: 64, height: 64)
                .background(
                    Circle().fill(
                        LinearGradient(
                            colors: [Tokens.Colors.primary, Tokens.Colors.brandGradientEnd],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Tokens.Spacing.s4) {
                Text(model.displayName)
                    .font(AppFont.title(caps))
                    .foregroundStyle(Tokens.Colors.textPrimary)
                    .lineLimit(1)

                Text(model.roleText)
                    .font(AppFont.caption(caps))
                    .foregroundStyle(Tokens.Colors.textSecondary)

                HStack(spacing: Tokens.Spacing.s8) {
                    PillTag(text: model.usageText, tone: .primary)
                    if session.isChild {
                        PillTag(text: "儿童模式", tone: .child, icon: "sparkles")
                    }
                    if let remaining = model.remainingText {
                        PillTag(text: remaining, tone: session.usage?.exceeded == true ? .warning : .neutral)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Tokens.Spacing.s16)
        .background(
            RoundedRectangle(cornerRadius: Tokens.Radius.large, style: .continuous)
                .fill(Tokens.Colors.surfaceCard)
                .shadow(color: Tokens.Shadow.cardPrimary, radius: Tokens.Elevation.cardRadius, x: 0, y: Tokens.Elevation.cardY)
        )
        .accessibilityElement(children: .combine)
    }

    // MARK: - 小组件

    private func groupTitle(_ text: String) -> some View {
        Text(text)
            .font(AppFont.caption(caps).weight(.semibold))
            .foregroundStyle(Tokens.Colors.textSecondary)
            .padding(.leading, Tokens.Spacing.s4)
            .accessibilityAddTraits(.isHeader)
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(.horizontal, Tokens.Spacing.s12)
        .padding(.vertical, Tokens.Spacing.s4)
        .background(
            RoundedRectangle(cornerRadius: Tokens.Radius.large, style: .continuous)
                .fill(Tokens.Colors.surfaceCard)
        )
    }

    private var divider: some View {
        Divider().overlay(Tokens.Colors.borderSubtle)
    }

    private func footer(_ model: MeViewModel) -> some View {
        VStack(spacing: Tokens.Spacing.s4) {
            Text("English Coach \(AppConfig.appVersion)")
                .font(AppFont.micro(caps))
                .foregroundStyle(Tokens.Colors.textTertiary)
            Text(session.baseURL?.absoluteString ?? "未配置服务器")
                .font(AppFont.micro(caps))
                .foregroundStyle(Tokens.Colors.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Tokens.Spacing.s8)
    }
}
