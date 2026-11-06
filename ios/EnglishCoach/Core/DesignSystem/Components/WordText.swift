import Foundation
import SwiftUI

/// 可点单词正文。
///
/// - 按字母切词（保留空格与标点，渲染后与原文一致），单词可点；
/// - 点击**只回调** `onTapWord`，**组件内不发请求、不弹窗**——音标查询与展示由页面决定；
/// - `showIPA == false` 时退化为普通文本（不显示下划线、不响应点击）；默认取
///   `RoleCapabilities.canSeeIPA`，所以孩子模式默认关闭（design-system §3）；
/// - 中文文案全部由页面传入，组件只负责排版与命中。
struct WordTextView: View {
    let text: String
    /// 是否开启「点词看音标」；nil 表示跟随 `RoleCapabilities.canSeeIPA`。
    var showIPA: Bool? = nil
    /// 自定义字体；nil 时用 `AppFont.sentence`。
    var font: Font? = nil
    var textColor: Color = Tokens.Colors.textPrimary
    var lineSpacing: CGFloat = 6
    var onTapWord: ((String) -> Void)? = nil

    @Environment(\.roleCapabilities) private var caps

    init(
        text: String,
        showIPA: Bool? = nil,
        font: Font? = nil,
        textColor: Color = Tokens.Colors.textPrimary,
        lineSpacing: CGFloat = 6,
        onTapWord: ((String) -> Void)? = nil
    ) {
        self.text = text
        self.showIPA = showIPA
        self.font = font
        self.textColor = textColor
        self.lineSpacing = lineSpacing
        self.onTapWord = onTapWord
    }

    private var isTappable: Bool {
        (showIPA ?? caps.canSeeIPA) && onTapWord != nil
    }

    var body: some View {
        Text(attributedText)
            .font(font ?? AppFont.sentence(caps))
            .foregroundStyle(textColor)
            .lineSpacing(lineSpacing)
            .environment(\.openURL, OpenURLAction { url in
                guard let word = Self.word(from: url), let handler = onTapWord else {
                    return .systemAction
                }
                handler(word)
                return .handled
            })
            .accessibilityHint(isTappable ? Text("点单词可查看音标") : Text(""))
    }

    private var attributedText: AttributedString {
        var result = AttributedString()
        for token in Self.tokenize(text) {
            var run = AttributedString(token.text)
            if token.isWord && isTappable, let url = Self.wordURL(token.text) {
                run.link = url
                run.foregroundColor = textColor
                run.underlineStyle = Text.LineStyle(pattern: .solid, color: Tokens.Colors.textTertiary)
            }
            result.append(run)
        }
        return result
    }

    // MARK: - 切词

    private struct WordToken {
        let text: String
        let isWord: Bool
    }

    /// 字母（含中文之外的拉丁字母）/ 撇号 / 连字符组成单词；空格、标点原样保留。
    private static func tokenize(_ text: String) -> [WordToken] {
        var tokens: [WordToken] = []
        var plainBuffer = ""
        var wordBuffer = ""

        func flushPlain() {
            guard !plainBuffer.isEmpty else { return }
            tokens.append(WordToken(text: plainBuffer, isWord: false))
            plainBuffer = ""
        }
        func flushWord() {
            guard !wordBuffer.isEmpty else { return }
            tokens.append(WordToken(text: wordBuffer, isWord: true))
            wordBuffer = ""
        }

        for character in text {
            let isWordCharacter = character.isLetter
                || ((character == "'" || character == "’" || character == "-") && !wordBuffer.isEmpty)
            if isWordCharacter {
                flushPlain()
                wordBuffer.append(character)
            } else {
                flushWord()
                plainBuffer.append(character)
            }
        }
        flushWord()
        flushPlain()
        return tokens
    }

    // MARK: - 词 → URL（用自定义 scheme 承载点击回调）

    private static func wordURL(_ word: String) -> URL? {
        var components = URLComponents()
        components.scheme = "ecword"
        components.host = "word"
        components.queryItems = [URLQueryItem(name: "w", value: word)]
        return components.url
    }

    private static func word(from url: URL) -> String? {
        guard url.scheme == "ecword" else { return nil }
        return URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "w" })?
            .value
    }
}
