import SwiftUI

/// 对话场景卡片（内置 / 自定义共用）。
struct ChatScenarioCard: View {
    let scenario: ChatScenarioDTO
    let isChild: Bool
    let isStarting: Bool
    var onStart: () -> Void
    var onEdit: (() -> Void)? = nil

    @Environment(\.roleCapabilities) private var caps

    private var displayTitle: String {
        let zh = (scenario.titleZh ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !zh.isEmpty { return zh }
        let en = (scenario.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return en.isEmpty ? scenario.id : en
    }

    private var displaySubtitle: String {
        (scenario.settingZh ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var subtitleFallback: String {
        let en = (scenario.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return displaySubtitle.isEmpty ? en : displaySubtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s12) {
            HStack(alignment: .top, spacing: Tokens.Spacing.s12) {
                Text(Self.emoji(for: scenario))
                    .font(.system(size: 34))
                    .frame(width: caps.minTapTarget, height: caps.minTapTarget)
                    .background(
                        Circle().fill(Tokens.Colors.surfaceMuted)
                    )
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Tokens.Spacing.s4) {
                    Text(displayTitle)
                        .font(AppFont.heading(caps))
                        .foregroundStyle(Tokens.Colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !subtitleFallback.isEmpty {
                        Text(subtitleFallback)
                            .font(AppFont.caption(caps))
                            .foregroundStyle(Tokens.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let onEdit {
                    AppButton(title: "编辑", kind: .text, action: onEdit)
                        .accessibilityLabel(Text("编辑这个自定义场景"))
                }
            }

            if !chips.isEmpty {
                HStack(spacing: Tokens.Spacing.s8) {
                    ForEach(chips, id: \.self) { chip in
                        Text(chip)
                            .font(AppFont.micro(caps))
                            .foregroundStyle(Tokens.Colors.textSecondary)
                            .padding(.horizontal, Tokens.Spacing.s8)
                            .padding(.vertical, Tokens.Spacing.s2)
                            .background(
                                Capsule().fill(Tokens.Colors.surfaceSunken)
                            )
                    }
                }
            }

            HStack(spacing: Tokens.Spacing.s8) {
                Spacer(minLength: 0)
                AppButton(
                    title: isStarting ? "正在开始…" : "开始 ›",
                    kind: .primary,
                    isLoading: isStarting,
                    isEnabled: !isStarting
                ) {
                    onStart()
                }
                .accessibilityLabel(Text("\(displayTitle) 开始对话"))
            }
        }
        .padding(Tokens.Spacing.s16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Tokens.Radius.large, style: .continuous)
                .fill(Tokens.Colors.surfaceCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.Radius.large, style: .continuous)
                .stroke(Tokens.Colors.borderSubtle, lineWidth: 1)
        )
    }

    private var chips: [String] {
        var values: [String] = []
        let level = (scenario.level ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !level.isEmpty {
            values.append(level.uppercased())
        }
        if scenario.isCustom == true {
            values.append("我的场景")
        }
        if let minAge = scenario.minAge, minAge > 0, !isChild {
            values.append("\(minAge)+ 岁")
        }
        if let variationCount = scenario.variationCount, variationCount > 0 {
            values.append("开场白变体 \(variationCount)")
        }
        if !isChild, (scenario.audience ?? "").lowercased() == "child" {
            values.append("小朋友场景")
        }
        return values
    }

    /// 接口没有 emoji 字段：按 id 关键词给一个稳定映射（HOS 同策略）。
    private static func emoji(for scenario: ChatScenarioDTO) -> String {
        let key = "\(scenario.id) \(scenario.title ?? "") \(scenario.titleZh ?? "")".lowercased()
        let table: [(String, String)] = [
            ("fastfood", "🍔"), ("burger", "🍔"), ("restaurant", "🍽️"), ("cafe", "☕"),
            ("coffee", "☕"), ("shop", "🛍️"), ("store", "🛍️"), ("market", "🛒"),
            ("school", "🏫"), ("class", "🏫"), ("teacher", "🏫"), ("library", "📚"),
            ("airport", "✈️"), ("travel", "🧳"), ("hotel", "🏨"), ("station", "🚉"),
            ("hospital", "🏥"), ("doctor", "🩺"), ("nurse", "🏥"), ("park", "🌳"), ("zoo", "🦁"),
            ("movie", "🎬"), ("cinema", "🎬"), ("sport", "⚽"), ("game", "🎮"),
            ("home", "🏠"), ("family", "🏠"), ("birthday", "🎂"), ("party", "🎉"),
            ("weather", "🌤️"), ("phone", "📱"), ("job", "💼")
        ]
        for (keyword, symbol) in table where key.contains(keyword) {
            return symbol
        }
        return scenario.isCustom == true ? "✨" : (scenario.audience?.lowercased() == "child" ? "🧸" : "💬")
    }
}
