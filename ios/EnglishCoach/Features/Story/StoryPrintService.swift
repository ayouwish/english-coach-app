import UIKit

/// 打印版式（对齐 web/HOS）：A4 整页练习纸 / A5 打印卡片。
enum StoryPrintLayout: String, CaseIterable, Identifiable {
    case fullPage
    case card

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fullPage: return "A4 整页"
        case .card: return "A5 卡片"
        }
    }

    var subtitle: String {
        switch self {
        case .fullPage: return "标题 + 编号句子，适合夹在绘本里练"
        case .card: return "148×210mm，虚线裁切框，可剪下贴墙"
        }
    }
}

/// 一次打印的内容与选项。
struct StoryPrintOptions {
    var title: String
    var level: String
    var dateText: String
    var authorName: String
    var sentences: [String]
    var sourceZh: String
    var includeChinese: Bool
    var includeWritingLines: Bool
    var layout: StoryPrintLayout
}

/// 故事打印：本地画 PDF（A4 / A5），再交给系统打印面板；
/// 也支持导出 PDF 用「文件」App / 分享打印（对齐 web 的「打印 / 另存为 PDF」）。
enum StoryPrintService {
    /// A4 = 210×297mm@72dpi；A5 = 148×210mm@72dpi（PDF 单位 pt）。
    private static let a4 = CGSize(width: 595.28, height: 841.89)
    private static let a5 = CGSize(width: 419.53, height: 595.28)

    // MARK: - 生成 PDF

    static func makePDF(_ options: StoryPrintOptions) -> Data? {
        let sentences = options.sentences
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !sentences.isEmpty else { return nil }

        let isCard = options.layout == .card
        let media = isCard ? a5 : a4
        let margin: CGFloat = isCard ? 30 : 44
        let contentWidth = media.width - margin * 2
        let footerReserve: CGFloat = isCard ? 52 : 56
        let bottomLimit = media.height - margin - footerReserve

        let titleFont = UIFont.systemFont(ofSize: isCard ? 17 : 20, weight: .bold)
        let metaFont = UIFont.systemFont(ofSize: isCard ? 9 : 10)
        let headingFont = UIFont.systemFont(ofSize: isCard ? 11 : 13, weight: .bold)
        let bodyFont = UIFont.systemFont(ofSize: isCard ? 12 : 14)
        let numberFont = UIFont.systemFont(ofSize: isCard ? 12 : 14, weight: .semibold)
        let zhTitleFont = UIFont.systemFont(ofSize: isCard ? 9 : 11, weight: .bold)
        let zhBodyFont = UIFont.systemFont(ofSize: isCard ? 8.5 : 10)
        let footerFont = UIFont.systemFont(ofSize: isCard ? 8.5 : 10)

        let titleAttrs = attrs(titleFont)
        let metaAttrs = attrs(metaFont, UIColor(white: 0.32, alpha: 1))
        let headingAttrs = attrs(headingFont)
        let bodyAttrs = attrs(bodyFont, lineSpacing: isCard ? 4 : 6)
        let numberAttrs = attrs(numberFont)
        let zhTitleAttrs = attrs(zhTitleFont)
        let zhBodyAttrs = attrs(zhBodyFont, lineSpacing: 2)
        let footerAttrs = attrs(footerFont, UIColor(white: 0.25, alpha: 1))

        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: media))
        return renderer.pdfData { ctx in
            var pageIndex = 0
            var y: CGFloat = margin

            func beginPage() {
                ctx.beginPage()
                pageIndex += 1
                if isCard {
                    drawCardBorder(media: media)
                    y = margin + 16
                } else {
                    y = margin
                    if pageIndex > 1 {
                        // 续页只画一行小标题，避免整页没有出处。
                        drawText("《\(options.title)》", at: CGPoint(x: margin, y: y), width: contentWidth, attrs: attrs(UIFont.systemFont(ofSize: 9), UIColor(white: 0.45, alpha: 1)))
                        y += 16
                        strokeLine(from: CGPoint(x: margin, y: y), to: CGPoint(x: media.width - margin, y: y), color: UIColor(white: 0.8, alpha: 1))
                        y += 12
                    }
                }
            }

            func endPage() {
                drawFooter(page: pageIndex, media: media, margin: margin, attrs: footerAttrs)
            }

            func ensureSpace(_ height: CGFloat) {
                if y + height > bottomLimit {
                    endPage()
                    beginPage()
                }
            }

            beginPage()

            // 标题 + 元信息（只在第一页）
            let titleHeight = textSize(options.title, width: contentWidth, attrs: titleAttrs).height
            drawText(options.title, at: CGPoint(x: margin, y: y), width: contentWidth, attrs: titleAttrs)
            y += titleHeight + (isCard ? 4 : 6)

            var meta = "等级 \(options.level.isEmpty ? "—" : options.level) · \(sentences.count) 句"
            if !options.dateText.isEmpty { meta += " · \(options.dateText)" }
            if !options.authorName.isEmpty { meta += " · \(options.authorName)" }
            drawText(meta, at: CGPoint(x: margin, y: y), width: contentWidth, attrs: metaAttrs)
            y += textSize(meta, width: contentWidth, attrs: metaAttrs).height + (isCard ? 8 : 10)

            strokeLine(
                from: CGPoint(x: margin, y: y),
                to: CGPoint(x: media.width - margin, y: y),
                color: UIColor(white: 0.55, alpha: 1)
            )
            y += isCard ? 10 : 14

            // 中文原文（仅创建者、且勾选时；放在英文前作为“我讲的”参考）
            let zh = options.sourceZh.trimmingCharacters(in: .whitespacesAndNewlines)
            if options.includeChinese, !zh.isEmpty {
                let boxWidth = contentWidth
                let zhBodyWidth = boxWidth - 20
                let bodyHeight = textSize(zh, width: zhBodyWidth, attrs: zhBodyAttrs).height
                let headingHeight = textSize("中文原文（我讲的）", width: zhBodyWidth, attrs: zhTitleAttrs).height
                let boxHeight = 10 + headingHeight + 4 + bodyHeight + 10
                ensureSpace(boxHeight + 10)
                let box = CGRect(x: margin, y: y, width: boxWidth, height: boxHeight)
                UIColor(red: 0.972, green: 0.976, blue: 1, alpha: 1).setFill()
                UIBezierPath(roundedRect: box, cornerRadius: 8).fill()
                drawText("中文原文（我讲的）", at: CGPoint(x: margin + 10, y: y + 10), width: zhBodyWidth, attrs: zhTitleAttrs)
                drawText(zh, at: CGPoint(x: margin + 10, y: y + 10 + headingHeight + 4), width: zhBodyWidth, attrs: zhBodyAttrs)
                y += boxHeight + 12
            }

            // 小节标题
            ensureSpace(24)
            drawText("Read aloud · 朗读练习", at: CGPoint(x: margin, y: y), width: contentWidth, attrs: headingAttrs)
            y += textSize("Read aloud · 朗读练习", width: contentWidth, attrs: headingAttrs).height + (isCard ? 6 : 8)

            // 逐句编号
            let numberWidth: CGFloat = isCard ? 20 : 24
            let textWidth = contentWidth - numberWidth
            for (index, sentence) in sentences.enumerated() {
                let bodyHeight = textSize(sentence, width: textWidth, attrs: bodyAttrs).height
                let writingHeight: CGFloat = options.includeWritingLines ? 22 : 0
                ensureSpace(bodyHeight + writingHeight + 6)
                drawText("\(index + 1).", at: CGPoint(x: margin, y: y + 1), width: numberWidth, attrs: numberAttrs)
                drawText(sentence, at: CGPoint(x: margin + numberWidth, y: y), width: textWidth, attrs: bodyAttrs)
                y += bodyHeight
                if options.includeWritingLines {
                    y += 6
                    strokeLine(
                        from: CGPoint(x: margin + numberWidth, y: y + 12),
                        to: CGPoint(x: media.width - margin, y: y + 12),
                        color: UIColor(white: 0.72, alpha: 1)
                    )
                    y += 22
                } else {
                    y += isCard ? 6 : 8
                }
            }

            endPage()
        }
    }

    // MARK: - 打印 / 分享

    /// 打开系统打印面板；返回是否真的弹出了打印选项（用 delegate 回调判断，超时算失败）。
    @MainActor
    @discardableResult
    static func presentPrintPanel(data: Data, jobName: String) async -> Bool {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("story-print-\(UUID().uuidString).pdf")
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            return false
        }
        let controller = UIPrintInteractionController.shared
        let info = UIPrintInfo(dictionary: nil)
        info.jobName = jobName
        info.outputType = .general
        info.orientation = .portrait
        controller.printInfo = info
        // 与 HOS 一致：传一个真实 PDF 文件，避免打印框架对内存 Data 的格式判断差异。
        controller.printingItem = url
        guard let top = await waitForPresentableViewController(),
              let view = top.view,
              view.window != nil else {
            return false
        }
        let watcher = PrintPresentationWatcher.shared
        watcher.reset()
        controller.delegate = watcher
        // iPad 用 anchored popover；iPhone 用不带锚点的 modal。两者都会返回 Bool，
        // 返回 false 表示系统拒绝弹出（例如上层还有 modal / view 不在 window 上）。
        let presented: Bool
        if UIDevice.current.userInterfaceIdiom == .pad {
            presented = controller.present(
                from: CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0),
                in: view,
                animated: true,
                completionHandler: nil
            )
        } else {
            presented = controller.present(animated: true, completionHandler: nil)
        }
        guard presented else { return false }
        return await watcher.waitForPresentation(timeoutMs: 1500)
    }

    /// 分享 PDF（可存到「文件」、AirDrop、邮件，或从分享面板里选「打印」）。
    @MainActor
    @discardableResult
    static func sharePDF(data: Data, fileName: String) async -> Bool {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(fileName)
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            return false
        }
        guard let top = await waitForPresentableViewController(),
              let view = top.view,
              view.window != nil else {
            return false
        }
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let popover = controller.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        top.present(controller, animated: true)
        return true
    }

    /// 等 modal（打印选项 sheet）真正离场后再弹系统面板，避免 “already presenting” 导致的静默失败。
    @MainActor
    private static func waitForPresentableViewController() async -> UIViewController? {
        for _ in 0..<15 {
            if let top = topViewController(),
               top.presentedViewController == nil,
               top.viewIfLoaded?.window != nil {
                return top
            }
            try? await Task.sleep(for: .milliseconds(200))
        }
        return topViewController()
    }

    // MARK: - 绘制工具

    private static func attrs(
        _ font: UIFont,
        _ color: UIColor = .black,
        lineSpacing: CGFloat = 0
    ) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = lineSpacing
        paragraph.lineBreakMode = .byWordWrapping
        return [.font: font, .foregroundColor: color, .paragraphStyle: paragraph]
    }

    private static func textSize(_ text: String, width: CGFloat, attrs: [NSAttributedString.Key: Any]) -> CGSize {
        let rect = (text as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attrs,
            context: nil
        )
        return CGSize(width: ceil(rect.width), height: ceil(rect.height))
    }

    private static func drawText(
        _ text: String,
        at origin: CGPoint,
        width: CGFloat,
        attrs: [NSAttributedString.Key: Any]
    ) {
        (text as NSString).draw(
            with: CGRect(x: origin.x, y: origin.y, width: width, height: 20_000),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attrs,
            context: nil
        )
    }

    private static func strokeLine(from: CGPoint, to: CGPoint, color: UIColor) {
        color.setStroke()
        let path = UIBezierPath()
        path.move(to: from)
        path.addLine(to: to)
        path.lineWidth = 0.6
        path.stroke()
    }

    private static func drawCardBorder(media: CGSize) {
        let inset: CGFloat = 28.35 // 10mm
        let rect = CGRect(x: inset, y: inset, width: media.width - inset * 2, height: media.height - inset * 2)
        let path = UIBezierPath(roundedRect: rect, cornerRadius: 11)
        path.lineWidth = 1.2
        path.setLineDash([6, 4], count: 2, phase: 0)
        UIColor(white: 0.4, alpha: 1).setStroke()
        path.stroke()
    }

    private static func drawFooter(
        page: Int,
        media: CGSize,
        margin: CGFloat,
        attrs: [NSAttributedString.Key: Any]
    ) {
        let footerY = media.height - margin - 22
        strokeLine(
            from: CGPoint(x: margin, y: footerY - 10),
            to: CGPoint(x: media.width - margin, y: footerY - 10),
            color: UIColor(white: 0.72, alpha: 1)
        )
        let left = "名字 Name：________   日期 Date：________"
        drawText(left, at: CGPoint(x: margin, y: footerY), width: media.width - margin * 2 - 110, attrs: attrs)
        let right = "英语教练 · 我的故事" + (page > 1 ? "（第 \(page) 页）" : "")
        let width = textSize(right, width: media.width, attrs: attrs).width
        drawText(right, at: CGPoint(x: media.width - margin - width, y: footerY), width: width + 1, attrs: attrs)
    }

    @MainActor
    private static func keyWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
    }

    @MainActor
    private static func topViewController() -> UIViewController? {
        guard var top = keyWindow()?.rootViewController else { return nil }
        while let presented = top.presentedViewController {
            top = presented
        }
        return top
    }
}


/// 用 `UIPrintInteractionControllerDelegate` 判断打印面板是否真的弹出来：
/// iOS 26 上 `present(from:in:)` 失败时不会抛错，只能靠这个回调 + 超时兜底。
@MainActor
private final class PrintPresentationWatcher: NSObject, UIPrintInteractionControllerDelegate {
    static let shared = PrintPresentationWatcher()

    private var didPresent = false
    private var waiter: CheckedContinuation<Bool, Never>?

    func reset() {
        didPresent = false
        waiter = nil
    }

    func waitForPresentation(timeoutMs: Int) async -> Bool {
        if didPresent { return true }
        return await withCheckedContinuation { continuation in
            waiter = continuation
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(timeoutMs))
                self.timeout()
            }
        }
    }

    func printInteractionControllerWillPresentPrinterOptions(_ controller: UIPrintInteractionController) {
        didPresent = true
        if let waiter {
            self.waiter = nil
            waiter.resume(returning: true)
        }
    }

    private func timeout() {
        guard let waiter else { return }
        self.waiter = nil
        waiter.resume(returning: didPresent)
    }
}
