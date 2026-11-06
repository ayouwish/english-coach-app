import SwiftUI

// MARK: - 分区标题

/// 区块标题：标题 + 可选副标题 + 可选右侧动作（「查看全部」等）。
struct SectionHeader: View {
    let title: String
    var subtitle: String? = nil
    var actionTitle: String? = nil
    var onAction: (() -> Void)? = nil

    @Environment(\.roleCapabilities) private var caps

    init(title: String, subtitle: String? = nil, actionTitle: String? = nil, onAction: (() -> Void)? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.actionTitle = actionTitle
        self.onAction = onAction
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.s8) {
            VStack(alignment: .leading, spacing: Tokens.Spacing.s2) {
                Text(title)
                    .font(AppFont.heading(caps))
                    .foregroundStyle(Tokens.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle = self.subtitle {
                    Text(subtitle)
                        .font(AppFont.caption(caps))
                        .foregroundStyle(Tokens.Colors.textSecondary)
                }
            }
            Spacer(minLength: Tokens.Spacing.s8)
            if let actionTitle = self.actionTitle, let onAction = self.onAction {
                Button(actionTitle, action: onAction)
                    .font(AppFont.caption(caps).weight(.semibold))
                    .foregroundStyle(Tokens.Colors.primary)
                    .frame(minHeight: caps.minTapTarget, alignment: .trailing)
                    .accessibilityLabel(Text(actionTitle))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 信息行

/// 通用信息行：图标 + 标题 + 副说明 + 右侧值/箭头；给了 `onTap` 时整行可点。
struct InfoRow: View {
    var icon: String? = nil
    let title: String
    var value: String? = nil
    var detail: String? = nil
    var showsChevron: Bool = false
    var onTap: (() -> Void)? = nil

    @Environment(\.roleCapabilities) private var caps

    init(
        icon: String? = nil,
        title: String,
        value: String? = nil,
        detail: String? = nil,
        showsChevron: Bool = false,
        onTap: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.title = title
        self.value = value
        self.detail = detail
        self.showsChevron = showsChevron
        self.onTap = onTap
    }

    var body: some View {
        Group {
            if let onTap = self.onTap {
                Button(action: onTap) {
                    rowContent
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(accessibilityText))
                .accessibilityHint(Text("双击打开"))
            } else {
                rowContent
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(accessibilityText))
            }
        }
        .contentShape(Rectangle())
    }

    private var rowContent: some View {
        HStack(alignment: .center, spacing: Tokens.Spacing.s12) {
            if let icon = self.icon {
                Image(systemName: icon)
                    .font(AppFont.body(caps))
                    .foregroundStyle(Tokens.Colors.primary)
                    .frame(width: 24, alignment: .center)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: Tokens.Spacing.s2) {
                Text(title)
                    .font(AppFont.body(caps))
                    .foregroundStyle(Tokens.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail = self.detail {
                    Text(detail)
                        .font(AppFont.caption(caps))
                        .foregroundStyle(Tokens.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: Tokens.Spacing.s8)
            if let value = self.value {
                Text(value)
                    .font(AppFont.body(caps))
                    .foregroundStyle(Tokens.Colors.textSecondary)
                    .multilineTextAlignment(.trailing)
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(AppFont.caption(caps))
                    .foregroundStyle(Tokens.Colors.textTertiary)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: onTap == nil ? 36 : caps.minTapTarget)
    }

    private var accessibilityText: String {
        var parts = [title]
        if let value = self.value, !value.isEmpty { parts.append(value) }
        if let detail = self.detail, !detail.isEmpty { parts.append(detail) }
        return parts.joined(separator: "，")
    }
}

// MARK: - 胶囊标签

/// 胶囊标签（等级、状态、音素、受众）。只做展示，不承载点击。
struct PillTag: View {
    enum Tone {
        case neutral
        case primary
        case success
        case warning
        case danger
        case child
    }

    let text: String
    var tone: Tone = .neutral
    var icon: String? = nil
    var isCompact: Bool = true

    @Environment(\.roleCapabilities) private var caps

    init(text: String, tone: Tone = .neutral, icon: String? = nil, isCompact: Bool = true) {
        self.text = text
        self.tone = tone
        self.icon = icon
        self.isCompact = isCompact
    }

    var body: some View {
        HStack(spacing: Tokens.Spacing.s4) {
            if let icon = self.icon {
                Image(systemName: icon)
                    .font(AppFont.micro(caps))
                    .accessibilityHidden(true)
            }
            Text(text)
                .font(isCompact ? AppFont.micro(caps).weight(.medium) : AppFont.caption(caps))
                .lineLimit(1)
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, Tokens.Spacing.s8)
        .padding(.vertical, Tokens.Spacing.s2)
        .background(Capsule(style: .continuous).fill(background))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(text))
    }

    private var background: Color {
        switch tone {
        case .neutral: return Tokens.Colors.surfaceSunken
        case .primary: return Tokens.Colors.surfaceMuted
        case .success: return Tokens.Colors.successBackground
        case .warning: return Tokens.Colors.warningBackground
        case .danger: return Tokens.Colors.dangerBackground
        case .child: return Tokens.Colors.childAccentSoft
        }
    }

    private var foreground: Color {
        switch tone {
        case .neutral: return Tokens.Colors.textSecondary
        case .primary: return Tokens.Colors.primary
        case .success: return Tokens.Colors.successText
        case .warning: return Tokens.Colors.warningText
        case .danger: return Tokens.Colors.dangerText
        case .child: return Tokens.Colors.childAccentText
        }
    }
}

// MARK: - 要点列表

/// 要点列表（问题说明、练习建议）：圆点 + 正文，自动换行。
struct BulletList: View {
    let items: [String]
    var bulletColor: Color = Tokens.Colors.primary
    var bulletSymbol: String = "•"

    @Environment(\.roleCapabilities) private var caps

    init(items: [String], bulletColor: Color = Tokens.Colors.primary, bulletSymbol: String = "•") {
        self.items = items
        self.bulletColor = bulletColor
        self.bulletSymbol = bulletSymbol
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s8) {
            ForEach(items.indices, id: \.self) { index in
                HStack(alignment: .top, spacing: Tokens.Spacing.s8) {
                    Text(bulletSymbol)
                        .font(AppFont.body(caps).weight(.semibold))
                        .foregroundStyle(bulletColor)
                        .accessibilityHidden(true)
                    Text(items[index])
                        .font(AppFont.body(caps))
                        .foregroundStyle(Tokens.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 键值网格

/// 键值对展示模型（家长面板、服务状态、设置只读项）。
struct KeyValueItem: Identifiable, Hashable, Sendable {
    let id: Int
    let key: String
    let value: String

    init(id: Int, key: String, value: String) {
        self.id = id
        self.key = key
        self.value = value
    }
}

/// 键值网格：2 列（或指定列数）排列 `key / value`，适合家长统计与服务状态。
struct KeyValueGrid: View {
    let items: [KeyValueItem]
    var columns: Int = 2

    @Environment(\.roleCapabilities) private var caps

    init(items: [KeyValueItem], columns: Int = 2) {
        self.items = items
        self.columns = columns
    }

    private var gridColumns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(minimum: 88), spacing: Tokens.Spacing.s12, alignment: .topLeading),
            count: max(1, columns)
        )
    }

    var body: some View {
        LazyVGrid(columns: gridColumns, alignment: .leading, spacing: Tokens.Spacing.s12) {
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: Tokens.Spacing.s2) {
                    Text(item.key)
                        .font(AppFont.caption(caps))
                        .foregroundStyle(Tokens.Colors.textSecondary)
                    Text(item.value)
                        .font(AppFont.bodyEmphasis(caps))
                        .foregroundStyle(Tokens.Colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("\(item.key)，\(item.value)"))
            }
        }
    }
}

// MARK: - 横幅

/// 通用横幅（降级提示、离线、成功提示、儿童鼓励）。
/// 与 `StateViews.ErrorBanner` 的区别：本组件支持四种语义与标题，不做网络语义绑定。
struct Banner: View {
    enum Kind {
        case info
        case success
        case warning
        case danger
        case child
    }

    let message: String
    var title: String? = nil
    var kind: Kind = .warning
    var icon: String? = nil
    var actionTitle: String? = nil
    var onAction: (() -> Void)? = nil

    @Environment(\.roleCapabilities) private var caps

    init(
        message: String,
        title: String? = nil,
        kind: Kind = .warning,
        icon: String? = nil,
        actionTitle: String? = nil,
        onAction: (() -> Void)? = nil
    ) {
        self.message = message
        self.title = title
        self.kind = kind
        self.icon = icon
        self.actionTitle = actionTitle
        self.onAction = onAction
    }

    var body: some View {
        HStack(alignment: .top, spacing: Tokens.Spacing.s8) {
            Image(systemName: icon ?? defaultIcon)
                .font(AppFont.footnote(caps))
                .foregroundStyle(accentColor)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Tokens.Spacing.s2) {
                if let title = self.title {
                    Text(title)
                        .font(AppFont.footnote(caps).weight(.semibold))
                        .foregroundStyle(accentColor)
                }
                Text(message)
                    .font(AppFont.footnote(caps))
                    .foregroundStyle(Tokens.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let actionTitle = self.actionTitle, let onAction = self.onAction {
                Button(actionTitle, action: onAction)
                    .font(AppFont.caption(caps).weight(.semibold))
                    .foregroundStyle(Tokens.Colors.primary)
                    .frame(minHeight: caps.minTapTarget, alignment: .trailing)
                    .accessibilityLabel(Text(actionTitle))
            }
        }
        .padding(Tokens.Spacing.s12)
        .background(
            RoundedRectangle(cornerRadius: Tokens.Radius.medium, style: .continuous)
                .fill(backgroundColor)
        )
        .accessibilityElement(children: onAction == nil ? .combine : .contain)
        .accessibilityLabel(Text(title.map { "\($0)，\(message)" } ?? message))
    }

    private var defaultIcon: String {
        switch kind {
        case .info: return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .danger: return "exclamationmark.circle.fill"
        case .child: return "sparkles"
        }
    }

    private var accentColor: Color {
        switch kind {
        case .info: return Tokens.Colors.info
        case .success: return Tokens.Colors.successText
        case .warning: return Tokens.Colors.warningText
        case .danger: return Tokens.Colors.dangerText
        case .child: return Tokens.Colors.childAccentText
        }
    }

    private var backgroundColor: Color {
        switch kind {
        case .info: return Tokens.Colors.surfaceMuted
        case .success: return Tokens.Colors.successBackground
        case .warning: return Tokens.Colors.warningBackground
        case .danger: return Tokens.Colors.dangerBackground
        case .child: return Tokens.Colors.childAccentSoft
        }
    }
}
