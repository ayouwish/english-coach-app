import SwiftUI
import UIKit

/// 服务状态（契约 §3.15.1：`HealthView(services:audio:)`）。
///
/// `GET /health`（无需登录）展示：db、voice.reachable、voice.mode、capabilities、features；
/// 可强制绕过服务端 15s 缓存，并复制诊断信息（不含 token/邮箱）。
struct HealthView: View {
    private let services: AppServices
    private let audio: AudioCoordinator

    @Environment(SessionStore.self) private var session
    @Environment(\.roleCapabilities) private var caps

    @State private var viewModel: HealthViewModel?
    @State private var copied = false

    init(services: AppServices, audio: AudioCoordinator) {
        self.services = services
        self.audio = audio
    }

    var body: some View {
        Group {
            if let viewModel {
                content(viewModel)
            } else {
                LoadingBlock(text: "正在检查服务状态…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Tokens.Colors.canvas.ignoresSafeArea())
            }
        }
        .navigationTitle("服务状态")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await viewModel?.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .accessibilityLabel(Text("强制刷新服务状态"))
                }
                .disabled(viewModel?.isRefreshing == true)
            }
        }
        .task {
            guard viewModel == nil else { return }
            let model = HealthViewModel(services: services, audio: audio, session: session)
            await model.load()
            viewModel = model
        }
    }

    @ViewBuilder
    private func content(_ model: HealthViewModel) -> some View {
        switch model.loadState {
        case .idle, .loading:
            ScrollView {
                VStack(spacing: Tokens.Spacing.s12) {
                    SkeletonBlock(height: 96)
                    SkeletonBlock(height: 140)
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
                    Text("家庭 NAS / 语音能力自查。此接口无需登录，可用来判断服务是否在线。")
                        .font(AppFont.caption(caps))
                        .foregroundStyle(Tokens.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if model.health?.voice?.reachable == false {
                        Banner(
                            message: "voice 未就绪时录音与文本仍会入库，可稍后「重试评测」；文本/历史功能不受影响。",
                            title: "语音服务未就绪",
                            kind: .warning
                        )
                    }

                    coreCard(model)
                    capabilitiesCard(model)
                    featuresCard(model)

                    AppButton(
                        title: copied ? "已复制诊断信息" : "复制诊断信息",
                        icon: "doc.on.doc"
                    ) {
                        UIPasteboard.general.string = model.diagnosticText
                        copied = true
                    }

                    Text("客户端不对 /health 做超过每 30 秒一次的轮询；voice 探测有 3 秒超时 + 15 秒缓存。")
                        .font(AppFont.micro(caps))
                        .foregroundStyle(Tokens.Colors.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(Tokens.Spacing.s16)
                .contentColumn(alignment: .center)
            }
            .background(Tokens.Colors.canvas.ignoresSafeArea())
            .refreshable { await model.refresh() }
        }
    }

    private func coreCard(_ model: HealthViewModel) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            InfoRow(icon: "antenna.radiowaves.left.and.right", title: "服务", value: model.statusText)
            divider
            InfoRow(icon: "externaldrive.connected.to.line.below", title: "数据库", value: model.dbText)
            divider
            InfoRow(icon: "waveform", title: "语音服务", value: model.voiceReachableText)
            if let mode = model.health?.voice?.mode, !mode.isEmpty {
                divider
                InfoRow(icon: "dial.medium", title: "语音模式", value: mode)
            }
            if let version = model.health?.version, !version.isEmpty {
                divider
                InfoRow(icon: "number", title: "服务端版本", value: version)
            }
            divider
            InfoRow(icon: "network", title: "主机", value: model.serverHost)
            divider
            InfoRow(icon: "clock", title: "检查时间", value: model.lastUpdatedText)
            if let hint = model.health?.voice?.hint, !hint.isEmpty {
                divider
                Text(hint)
                    .font(AppFont.caption(caps))
                    .foregroundStyle(Tokens.Colors.warningText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, Tokens.Spacing.s8)
            }
        }
        .padding(.horizontal, Tokens.Spacing.s12)
        .padding(.vertical, Tokens.Spacing.s4)
        .background(
            RoundedRectangle(cornerRadius: Tokens.Radius.large, style: .continuous)
                .fill(Tokens.Colors.surfaceCard)
        )
    }

    private func capabilitiesCard(_ model: HealthViewModel) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s12) {
            Text("语音能力（voice.capabilities）")
                .font(AppFont.caption(caps).weight(.semibold))
                .foregroundStyle(Tokens.Colors.textSecondary)
            if model.capabilityItems.isEmpty {
                Text("未返回 capabilities 字段")
                    .font(AppFont.caption(caps))
                    .foregroundStyle(Tokens.Colors.textTertiary)
            } else {
                KeyValueGrid(items: model.capabilityItems, columns: 2)
            }
        }
        .padding(Tokens.Spacing.s16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Tokens.Radius.large, style: .continuous)
                .fill(Tokens.Colors.surfaceCard)
        )
    }

    private func featuresCard(_ model: HealthViewModel) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s12) {
            Text("构建特性（静态标记，用来确认服务端是不是新构建）")
                .font(AppFont.caption(caps).weight(.semibold))
                .foregroundStyle(Tokens.Colors.textSecondary)
            if model.featureItems.isEmpty {
                Text("未返回 features 字段")
                    .font(AppFont.caption(caps))
                    .foregroundStyle(Tokens.Colors.textTertiary)
            } else {
                KeyValueGrid(items: model.featureItems, columns: 2)
            }
        }
        .padding(Tokens.Spacing.s16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Tokens.Radius.large, style: .continuous)
                .fill(Tokens.Colors.surfaceCard)
        )
    }

    private var divider: some View {
        Divider().overlay(Tokens.Colors.borderSubtle)
    }
}
