import SwiftUI

/// 故事集打印选项（多选后打开）：读取所选故事详情 → 生成「封面 + 连续排版」PDF → 系统打印/分享。
struct StoryCollectionPrintSheet: View {
    let storyIDs: [String]
    let currentUserId: String
    let services: AppServices
    let onPrint: (Data, String) -> Void
    let onShare: (Data, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.roleCapabilities) private var caps

    @State private var stories: [StoryPrintStory] = []
    @State private var phase: Phase = .loading
    @State private var loadedCount = 0
    @State private var includeChinese = false
    @State private var includeWritingLines = false
    @State private var isBuilding = false
    @State private var errorText = ""

    private enum Phase: Equatable {
        case loading
        case ready
        case failed(String)
    }

    private var hasChinese: Bool {
        stories.contains { !$0.sourceZh.isEmpty }
    }

    var body: some View {
        BottomSheetContainer(
            title: "打印故事集",
            subtitle: "第一页封面，之后连续排版；最多 30 篇",
            isScrollable: false
        ) {
            VStack(alignment: .leading, spacing: Tokens.Spacing.s16) {
                switch phase {
                case .loading:
                    LoadingBlock(text: "正在读取 \(loadedCount)/\(storyIDs.count) 篇故事…")
                case .failed(let message):
                    InlineErrorView(message: message)
                    AppButton(title: "关闭", kind: .ghost) { dismiss() }
                case .ready:
                    readyContent
                }
            }
            .padding(.horizontal, Tokens.Spacing.s16)
            .padding(.vertical, Tokens.Spacing.s12)
        }
        .task {
            await loadStories()
        }
    }

    private var readyContent: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s16) {
            VStack(alignment: .leading, spacing: Tokens.Spacing.s4) {
                Text("已选 \(stories.count) 篇")
                    .font(AppFont.bodyEmphasis(caps))
                    .foregroundStyle(Tokens.Colors.textPrimary)
                Text("封面 + 连续排版；长故事自然跨页")
                    .font(AppFont.micro(caps))
                    .foregroundStyle(Tokens.Colors.textSecondary)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: Tokens.Spacing.s4) {
                    ForEach(Array(stories.enumerated()), id: \.offset) { index, story in
                        Text("\(index + 1). \(story.title)")
                            .font(AppFont.caption(caps))
                            .foregroundStyle(Tokens.Colors.textSecondary)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(maxHeight: 140)

            Toggle(isOn: $includeChinese) {
                VStack(alignment: .leading, spacing: Tokens.Spacing.s2) {
                    Text("显示中文原文")
                        .font(AppFont.body(caps))
                        .foregroundStyle(Tokens.Colors.textPrimary)
                    Text(hasChinese ? "只有你创建的故事会印出中文原文" : "所选故事没有中文原文")
                        .font(AppFont.micro(caps))
                        .foregroundStyle(Tokens.Colors.textTertiary)
                }
            }
            .tint(Tokens.Colors.primary)
            .disabled(!hasChinese)
            .frame(minHeight: caps.minTapTarget)

            Toggle(isOn: $includeWritingLines) {
                VStack(alignment: .leading, spacing: Tokens.Spacing.s2) {
                    Text("加书写留白行")
                        .font(AppFont.body(caps))
                        .foregroundStyle(Tokens.Colors.textPrimary)
                    Text("每句英文下面留一条横线")
                        .font(AppFont.micro(caps))
                        .foregroundStyle(Tokens.Colors.textTertiary)
                }
            }
            .tint(Tokens.Colors.primary)
            .frame(minHeight: caps.minTapTarget)

            if !errorText.isEmpty {
                InlineErrorView(message: errorText)
            }

            AppButton(title: "🖨️ 打印故事集", kind: .primary, isLoading: isBuilding) {
                runPrint()
            }
            AppButton(title: "导出 PDF", icon: "square.and.arrow.up", kind: .ghost) {
                runShare()
            }
        }
    }

    private func loadStories() async {
        guard stories.isEmpty else { return }
        phase = .loading
        var result: [StoryPrintStory] = []
        for (index, id) in storyIDs.enumerated() {
            loadedCount = index + 1
            do {
                let detail = try await services.story.materialDetail(id: id)
                let sentences = StorySplit.sentences(from: detail.text ?? "")
                guard !sentences.isEmpty else { continue }
                let rawTitle = (detail.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                result.append(
                    StoryPrintStory(
                        title: rawTitle.isEmpty ? "未命名故事" : rawTitle,
                        level: (detail.level ?? "").uppercased(),
                        dateText: Self.dateText(detail.createdAt),
                        authorName: detail.createdByName ?? "",
                        sentences: sentences,
                        sourceZh: (detail.createdBy ?? "") == currentUserId
                            ? (detail.sourceZh ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                            : ""
                    )
                )
            } catch {
                continue
            }
        }
        stories = result
        phase = result.isEmpty ? .failed("没有取到可打印的故事，请稍后重试") : .ready
    }

    private func makePDF() -> Data? {
        StoryPrintService.makeCollectionPDF(
            StoryPrintCollectionOptions(
                stories: stories,
                includeChinese: includeChinese && hasChinese,
                includeWritingLines: includeWritingLines
            )
        )
    }

    private func runPrint() {
        errorText = ""
        isBuilding = true
        defer { isBuilding = false }
        guard let data = makePDF() else {
            errorText = "没有可打印的内容"
            return
        }
        onPrint(data, "我的故事集")
        dismiss()
    }

    private func runShare() {
        errorText = ""
        isBuilding = true
        defer { isBuilding = false }
        guard let data = makePDF() else {
            errorText = "没有可打印的内容"
            return
        }
        onShare(data, "story-collection-\(Self.dateFileToken()).pdf")
        dismiss()
    }

    private static func dateText(_ raw: String?) -> String {
        guard let date = ECJSON.date(from: raw) else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy/M/d"
        return formatter.string(from: date)
    }

    private static func dateFileToken() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd"
        return formatter.string(from: Date())
    }
}
