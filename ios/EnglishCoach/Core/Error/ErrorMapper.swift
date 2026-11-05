import Foundation
import OSLog

/// 错误 → 用户可见中文（成人 / 儿童两套）。
///
/// 映射表唯一事实来源：`ios/docs/architecture.md` §5.2（逐条覆盖 transport 的 `URLError`
/// 分支、401/403、每个 `ServerErrorCode`、413/409/429/5xx、解码与取消）。
///
/// 规则：
/// - 纯数据映射，**不 import SwiftUI**，不做副作用（不登出、不跳转）；401 的清理由
///   `SessionStore.handleSessionExpired()` 由页面在用户点“重新登录”时执行；
/// - 儿童模式永不出现数字分 / “错误·失败·token·权限”等成人词，也不展示服务端原始
///   `message`（可能含术语或 IPA，孩子读不懂）；
/// - 所有非取消错误生成短 `diagnosticID` 并写一条 OSLog（日志不含凭据/邮箱/音频）。
enum ErrorMapper {
    private static let logger = Logger(subsystem: "top.dreamsearch.englishcoach", category: "ui")

    // MARK: - 契约 §3.13

    static func message(for error: any Error, isChild: Bool) -> UIMessage {
        let presentation: Presentation
        let kind: String
        if let apiError = error as? APIError {
            presentation = describe(apiError, isChild: isChild)
            kind = diagnosticKind(apiError)
        } else if let audioError = error as? AudioError {
            presentation = describeAudio(audioError, isChild: isChild)
            kind = diagnosticKind(audio: audioError)
        } else if error is CancellationError {
            return .silent()
        } else {
            presentation = fallback(isChild: isChild)
            kind = "unknown"
        }

        guard !presentation.isSilent else {
            return .silent()
        }
        let id = diagnosticID()
        logger.notice("ui error id=\(id, privacy: .public) kind=\(kind, privacy: .public)")
        return UIMessage(
            title: presentation.title,
            body: presentation.body.isEmpty ? nil : presentation.body,
            actionTitle: presentation.actionTitle,
            action: presentation.action,
            isRetryable: presentation.retryable,
            diagnosticID: id
        )
    }

    static func title(for code: APIError, isChild: Bool) -> String {
        describe(code, isChild: isChild).title
    }

    static func body(for code: APIError, isChild: Bool) -> String {
        describe(code, isChild: isChild).body
    }

    /// 是否为“网络类”错误（用于“检查服务器”引导 / 离线横幅判定，不用于文案）。
    static func isNetwork(_ error: any Error) -> Bool {
        if let apiError = error as? APIError {
            switch apiError {
            case .transport(let code):
                return code != .cancelled
            case .cancelled:
                return false
            default:
                return false
            }
        }
        if let urlError = error as? URLError {
            return urlError.code != .cancelled
        }
        return false
    }

    // MARK: - APIError 分派

    private static func describe(_ error: APIError, isChild: Bool) -> Presentation {
        switch error {
        case .transport(let code):
            return describeTransport(code, isChild: isChild)
        case .unauthorized:
            return relogin(isChild: isChild)
        case .forbidden:
            return forbidden(isChild: isChild)
        case .server(let code, let message, let status):
            return describeServer(code: code, message: message, status: status, isChild: isChild)
        case .decoding:
            return decoding(isChild: isChild)
        case .payloadTooLarge:
            return payloadTooLarge(isChild: isChild)
        case .cancelled:
            return .silent
        case .invalidBaseURL:
            return invalidBaseURL(isChild: isChild)
        case .credentialStorage:
            return credentialStorage(isChild: isChild)
        }
    }

    // MARK: - transport（URLError 分支）

    private static func describeTransport(_ code: URLError.Code, isChild: Bool) -> Presentation {
        switch code {
        case .notConnectedToInternet, .networkConnectionLost,
             .dataNotAllowed, .internationalRoamingOff, .callIsActive:
            return isChild
                ? presentation(title: "还没连上网", body: "先连上家里的 Wi-Fi 再玩哦", actionTitle: "再试一次", action: .retry, retryable: true)
                : presentation(title: "没有网络", body: "网络不可用，请检查是否连接到家里的 Wi-Fi", actionTitle: "重试", action: .retry, retryable: true)

        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed, .timedOut:
            return isChild
                ? presentation(title: "服务器睡觉了", body: "服务器睡着了，叫爸爸妈妈看一下", actionTitle: "再试一次", action: .retry, retryable: true)
                : presentation(title: "连不上服务器", body: "连不上学习服务器（NAS 可能未开机，或手机不在同一网络）；可在设置里检查服务器地址", actionTitle: "重试", action: .retry, retryable: true)

        case .appTransportSecurityRequiresSecureConnection, .secureConnectionFailed,
             .serverCertificateUntrusted, .serverCertificateHasUnknownRoot,
             .serverCertificateHasBadDate, .serverCertificateNotYetValid,
             .clientCertificateRejected, .clientCertificateRequired:
            return isChild
                ? presentation(title: "连不上服务器", body: "连不上服务器，叫爸爸妈妈看一下证书设置", actionTitle: nil, action: UIMessage.Action.none, retryable: false)
                : presentation(title: "HTTPS 连接被拒绝", body: "HTTPS 连接被系统拒绝：请确认服务器证书受信任（自签 / 内网 CA 需在设备上安装并信任）", actionTitle: nil, action: UIMessage.Action.none, retryable: false)

        case .badURL, .unsupportedURL:
            return invalidBaseURL(isChild: isChild)

        case .userAuthenticationRequired, .userCancelledAuthentication:
            return relogin(isChild: isChild)

        case .cancelled:
            return .silent

        case .badServerResponse, .zeroByteResource, .cannotParseResponse,
             .cannotDecodeRawData, .cannotDecodeContentData, .httpTooManyRedirects,
             .resourceUnavailable, .cannotLoadFromNetwork, .redirectToNonExistentLocation,
             .downloadDecodingFailedMidStream, .downloadDecodingFailedToComplete:
            return isChild
                ? presentation(title: "服务器没听懂", body: "服务器没听懂，再试一次", actionTitle: "再试一次", action: .retry, retryable: true)
                : presentation(title: "服务器返回异常", body: "服务器返回的内容异常，请重试", actionTitle: "重试", action: .retry, retryable: true)

        case .fileDoesNotExist, .fileIsDirectory, .noPermissionsToReadFile,
             .cannotCreateFile, .cannotOpenFile, .cannotCloseFile, .cannotWriteToFile,
             .cannotRemoveFile, .cannotMoveFile, .dataLengthExceedsMaximum,
             .requestBodyStreamExhausted:
            return isChild
                ? presentation(title: "刚才没成功", body: "刚才没成功，再试一次吧", actionTitle: "再试一次", action: .retry, retryable: true)
                : presentation(title: "本地操作失败", body: "读取 / 写入本机文件失败，请重试", actionTitle: "重试", action: .retry, retryable: true)

        default:
            return isChild
                ? presentation(title: "网络打了个盹", body: "网络打了个盹，再试一次", actionTitle: "再试一次", action: .retry, retryable: true)
                : presentation(title: "网络出了点问题", body: "网络出了点问题，请重试", actionTitle: "重试", action: .retry, retryable: true)
        }
    }

    // MARK: - 服务端错误码

    private static func describeServer(
        code: ServerErrorCode,
        message: String?,
        status: Int,
        isChild: Bool
    ) -> Presentation {
        // 任意 code 配 5xx：除 provider_* 有更具体语义外，一律按“服务器内部错误”处理。
        if status >= 500,
           code != .providerError,
           code != .providerTimeout,
           code != .providerUnavailable,
           code != .internalError {
            return internalServerError(isChild: isChild)
        }

        switch code {
        case .unauthorized:
            return relogin(isChild: isChild)

        case .forbidden:
            return forbidden(isChild: isChild)

        case .badRequest:
            return isChild
                ? presentation(title: "这一句没准备好", body: "这一句没准备好，再试一次", actionTitle: "再试一次", action: .retry, retryable: false)
                : presentation(title: "提交不完整", body: "提交的内容不完整，请重试", actionTitle: "重试", action: .retry, retryable: false)

        case .unsupportedAudio:
            return isChild
                ? presentation(title: "没听清", body: "没听清，再录一次", actionTitle: "再录一次", action: .retry, retryable: false)
                : presentation(title: "录音格式不受支持", body: "音频格式不受支持，请重新录制", actionTitle: "重新录制", action: .retry, retryable: false)

        case .audioTooLong, .payloadTooLarge:
            return payloadTooLarge(isChild: isChild)

        case .providerTimeout:
            return isChild
                ? presentation(title: "等得有点久", body: "服务器有点慢，再试一次", actionTitle: "再试一次", action: .retry, retryable: true)
                : presentation(title: "评测超时", body: "评测服务响应超时，请重试", actionTitle: "重试", action: .retry, retryable: true)

        case .providerUnavailable:
            return isChild
                ? presentation(title: "现在不能评分", body: "现在不能评分，先听一听吧", actionTitle: "再试一次", action: .retry, retryable: true)
                : presentation(title: "语音服务暂不可用", body: "语音服务暂时不可用，稍后再试；可以先听示范音或看文本跟读", actionTitle: "重试", action: .retry, retryable: true)

        case .providerError:
            return isChild
                ? presentation(title: "出了点小问题", body: "出了点小问题，再试一次", actionTitle: "再试一次", action: .retry, retryable: true)
                : presentation(title: "服务处理失败", body: "服务处理失败，请重试（若持续失败请联系家长）", actionTitle: "重试", action: .retry, retryable: true)

        case .audioNotFound, .audioGone:
            return isChild
                ? presentation(title: "录音找不到了", body: "录音找不到了", actionTitle: "再录一次", action: .retry, retryable: false)
                : presentation(title: "录音不见了", body: "找不到这段录音，可能已被清理", actionTitle: "重新录制", action: .retry, retryable: false)

        case .sessionClosed:
            return isChild
                ? presentation(title: "这个场景结束啦", body: "这个场景结束啦，换一个吧", actionTitle: "返回", action: .back, retryable: false)
                : presentation(title: "对话已结束", body: "这段对话已经结束了，换个场景继续吧", actionTitle: "返回场景列表", action: .back, retryable: false)

        case .blindTestClosed:
            return isChild
                ? presentation(title: "这一轮结束啦", body: "这一轮结束啦", actionTitle: "返回", action: .back, retryable: false)
                : presentation(title: "盲测已结束", body: "这次盲测已经结束了", actionTitle: "返回", action: .back, retryable: false)

        case .dailyLimitReached:
            return isChild
                ? presentation(title: "今天练够啦", body: "今天的练习时间到啦，明天再来吧", actionTitle: "返回", action: .back, retryable: false)
                : presentation(title: "今日练习到上限", body: "今天的练习时长已达上限，明天再来", actionTitle: "返回", action: .back, retryable: false)

        case .tooManyRequests:
            return isChild
                ? presentation(title: "先休息一下", body: "先休息一下，等会儿再试", actionTitle: "再试一次", action: .retry, retryable: true)
                : presentation(title: "请求太频繁", body: "尝试次数太多，请稍后再试", actionTitle: "重试", action: .retry, retryable: true)

        case .conflict:
            return isChild
                ? presentation(title: "再来一次吧", body: "刚才的状态变了一下，再试一次", actionTitle: "再试一次", action: .retry, retryable: true)
                : presentation(title: "请求冲突", body: "内容刚刚被更新过，刷新后再试", actionTitle: "重试", action: .retry, retryable: true)

        case .noAttempts, .noAudio:
            return isChild
                ? presentation(title: "还没有录音哦", body: "还没有可以评分的录音，先录一次吧", actionTitle: "再录一次", action: .retry, retryable: false)
                : presentation(title: "暂无可评分的录音", body: "没有可用的录音，请先录制一次", actionTitle: "重新录制", action: .retry, retryable: false)

        case .notFound:
            return isChild
                ? presentation(title: "找不到啦", body: "这个东西找不到啦", actionTitle: "返回", action: .back, retryable: false)
                : presentation(title: "内容不存在", body: "请求的内容不存在", actionTitle: "返回", action: .back, retryable: false)

        case .internalError:
            return internalServerError(isChild: isChild)

        case .unknown:
            if status == 413 {
                return payloadTooLarge(isChild: isChild)
            }
            if status == 429 {
                return isChild
                    ? presentation(title: "先休息一下", body: "先休息一下，等会儿再试", actionTitle: "再试一次", action: .retry, retryable: true)
                    : presentation(title: "请求太频繁", body: "尝试次数太多，请稍后再试", actionTitle: "重试", action: .retry, retryable: true)
            }
            if status == 409 {
                return isChild
                    ? presentation(title: "再来一次吧", body: "刚才的状态变了一下，再试一次", actionTitle: "再试一次", action: .retry, retryable: true)
                    : presentation(title: "请求冲突", body: "内容刚刚被更新过，刷新后再试", actionTitle: "重试", action: .retry, retryable: true)
            }
            if status >= 500 {
                return internalServerError(isChild: isChild)
            }
            // 未知 code：成人可以看服务端已本地化的 message；儿童一律用安全兜底文案。
            if !isChild, let message, !message.isEmpty {
                return presentation(title: "请求失败", body: message, actionTitle: "重试", action: .retry, retryable: true)
            }
            return isChild
                ? presentation(title: "出了点小问题", body: "出了点小问题，再试一次", actionTitle: "再试一次", action: .retry, retryable: true)
                : presentation(title: "请求失败", body: "请求没有完成，请重试", actionTitle: "重试", action: .retry, retryable: true)
        }
    }

    // MARK: - 文案

    private static func relogin(isChild: Bool) -> Presentation {
        isChild
            ? presentation(title: "要重新登录了", body: "需要重新登录", actionTitle: "重新登录", action: .relogin, retryable: false)
            : presentation(title: "登录已过期", body: "登录已过期，请重新登录", actionTitle: "重新登录", action: .relogin, retryable: false)
    }

    private static func forbidden(isChild: Bool) -> Presentation {
        // §5.2 表格对孩子这一行是“—（孩子不应触达）”；仍给一句孩子能读懂的兜底，避免空白页。
        isChild
            ? presentation(title: "这个不能玩", body: "这个功能要爸爸妈妈才能打开哦", actionTitle: "返回", action: .back, retryable: false)
            : presentation(title: "没有权限", body: "当前账号无权访问该功能", actionTitle: "返回", action: .back, retryable: false)
    }

    private static func payloadTooLarge(isChild: Bool) -> Presentation {
        isChild
            ? presentation(title: "说得太久啦", body: "说得太久啦，短一点再试", actionTitle: "再录一次", action: .retry, retryable: false)
            : presentation(title: "录音太长了", body: "录音太长了，请控制在 60 秒内", actionTitle: "重新录制", action: .retry, retryable: false)
    }

    private static func internalServerError(isChild: Bool) -> Presentation {
        isChild
            ? presentation(title: "服务器打了个嗝", body: "服务器打了个嗝，等一下再试", actionTitle: "再试一次", action: .retry, retryable: true)
            : presentation(title: "服务器内部错误", body: "服务器内部错误，请稍后再试", actionTitle: "重试", action: .retry, retryable: true)
    }

    private static func decoding(isChild: Bool) -> Presentation {
        // §5.2 的主操作是“上报”，但 UIMessage.Action 里没有对应项（契约 §3.13）→ 用 .none。
        isChild
            ? presentation(title: "需要更新一下", body: "需要爸爸妈妈更新一下 App", actionTitle: nil, action: UIMessage.Action.none, retryable: false)
            : presentation(title: "版本不匹配", body: "版本不匹配，请更新 App（并告知家长）", actionTitle: nil, action: UIMessage.Action.none, retryable: false)
    }

    private static func invalidBaseURL(isChild: Bool) -> Presentation {
        isChild
            ? presentation(title: "服务器地址不对", body: "叫爸爸妈妈看一下服务器地址", actionTitle: nil, action: UIMessage.Action.none, retryable: false)
            : presentation(title: "服务器地址不对", body: "服务器地址不正确，请填写以 https:// 开头的地址（只填主机名会自动补 /api）", actionTitle: "修改地址", action: .openSettings, retryable: false)
    }

    private static func credentialStorage(isChild: Bool) -> Presentation {
        isChild
            ? presentation(title: "登录状态没保存好", body: "登录状态没保存好，再试一次", actionTitle: "再试一次", action: .retry, retryable: true)
            : presentation(title: "凭据保存失败", body: "无法安全保存登录状态，请重试", actionTitle: "重试", action: .retry, retryable: true)
    }

    private static func fallback(isChild: Bool) -> Presentation {
        isChild
            ? presentation(title: "刚才没成功", body: "刚才没成功，再试一次吧", actionTitle: "再试一次", action: .retry, retryable: true)
            : presentation(title: "操作没有完成", body: "操作没有完成，请重试", actionTitle: "重试", action: .retry, retryable: true)
    }

    // MARK: - 诊断

    private static func diagnosticID() -> String {
        let raw = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        return String(raw.prefix(8)).lowercased()
    }

    private static func diagnosticKind(_ error: APIError) -> String {
        switch error {
        case .transport(let code):
            return "transport(\(code.rawValue))"
        case .unauthorized:
            return "unauthorized"
        case .forbidden:
            return "forbidden"
        case .server(let code, _, let status):
            return "server(\(serverCodeName(code)),http=\(status))"
        case .decoding(let path):
            return "decoding(path=\(path))"
        case .payloadTooLarge(let localBytes):
            return "payloadTooLarge(bytes=\(localBytes))"
        case .cancelled:
            return "cancelled"
        case .invalidBaseURL:
            return "invalidBaseURL"
        case .credentialStorage:
            return "credentialStorage"
        }
    }

    private static func serverCodeName(_ code: ServerErrorCode) -> String {
        switch code {
        case .badRequest: return "bad_request"
        case .unauthorized: return "unauthorized"
        case .forbidden: return "forbidden"
        case .notFound: return "not_found"
        case .unsupportedAudio: return "unsupported_audio"
        case .audioTooLong: return "audio_too_long"
        case .payloadTooLarge: return "payload_too_large"
        case .providerError: return "provider_error"
        case .providerTimeout: return "provider_timeout"
        case .providerUnavailable: return "provider_unavailable"
        case .audioNotFound: return "audio_not_found"
        case .audioGone: return "audio_gone"
        case .sessionClosed: return "session_closed"
        case .blindTestClosed: return "blind_test_closed"
        case .dailyLimitReached: return "daily_limit_reached"
        case .tooManyRequests: return "too_many_requests"
        case .conflict: return "conflict"
        case .noAttempts: return "no_attempts"
        case .noAudio: return "no_audio"
        case .internalError: return "internal_error"
        case .unknown: return "unknown"
        }
    }

    // MARK: - 音频（`Core/Audio` 的 AudioError；audio.md §2.3 / §9 要求由 ErrorMapper 转文案）

    private static func describeAudio(_ error: AudioError, isChild: Bool) -> Presentation {
        switch error {
        case .permissionDenied:
            return isChild
                ? presentation(title: "麦克风被关掉了", body: "麦克风被关掉了，去设置里打开就能录音啦", actionTitle: "去设置", action: .openSettings, retryable: false)
                : presentation(title: "需要麦克风权限", body: "麦克风权限被关闭了，请到系统设置里打开", actionTitle: "去设置", action: .openSettings, retryable: false)

        case .tooShort:
            return isChild
                ? presentation(title: "太短啦", body: "太短啦，再说一次", actionTitle: "再录一次", action: .retry, retryable: false)
                : presentation(title: "录音太短", body: "录音太短了（不足 0.5 秒），请读完再试", actionTitle: "重新录制", action: .retry, retryable: false)

        case .silent:
            return isChild
                ? presentation(title: "没有听到声音", body: "没有听到声音，靠近一点再说一次", actionTitle: "再录一次", action: .retry, retryable: false)
                : presentation(title: "没有检测到人声", body: "没有检测到人声，请靠近麦克风重试", actionTitle: "重新录制", action: .retry, retryable: false)

        case .tooLong:
            return isChild
                ? presentation(title: "说得太久啦", body: "说得太久啦，短一点再试", actionTitle: "再录一次", action: .retry, retryable: false)
                : presentation(title: "录音超时", body: "录音超过 60 秒上限，请缩短后再试", actionTitle: "重新录制", action: .retry, retryable: false)

        case .tooLarge:
            return isChild
                ? presentation(title: "这句话太长啦", body: "这句话太长啦，短一点好吗", actionTitle: "再录一次", action: .retry, retryable: false)
                : presentation(title: "录音文件过大", body: "录音文件超过 12MB，请缩短录音", actionTitle: "重新录制", action: .retry, retryable: false)

        case .engine:
            // 引擎层错误（AVAudioSession/AVAudioRecorder/AVAudioPlayer）不向用户暴露技术细节。
            return isChild
                ? presentation(title: "声音没有准备好", body: "声音没有准备好，再试一次吧", actionTitle: "再试一次", action: .retry, retryable: true)
                : presentation(title: "音频暂时不可用", body: "音频暂时不可用，请重试；若持续失败可换一副耳机或重启 App", actionTitle: "重试", action: .retry, retryable: true)
        }
    }

    private static func diagnosticKind(audio error: AudioError) -> String {
        switch error {
        case .permissionDenied: return "audio(permissionDenied)"
        case .tooShort: return "audio(tooShort)"
        case .silent: return "audio(silent)"
        case .tooLong: return "audio(tooLong)"
        case .tooLarge: return "audio(tooLarge)"
        case .engine: return "audio(engine)"
        }
    }

    // MARK: - 内部模型

    private struct Presentation {
        let title: String
        let body: String
        let actionTitle: String?
        let action: UIMessage.Action?
        let retryable: Bool

        var isSilent: Bool {
            title.isEmpty && body.isEmpty
        }

        static let silent = Presentation(
            title: "",
            body: "",
            actionTitle: nil,
            action: UIMessage.Action.none,
            retryable: false
        )
    }

    private static func presentation(
        title: String,
        body: String,
        actionTitle: String?,
        action: UIMessage.Action?,
        retryable: Bool
    ) -> Presentation {
        Presentation(title: title, body: body, actionTitle: actionTitle, action: action, retryable: retryable)
    }
}
