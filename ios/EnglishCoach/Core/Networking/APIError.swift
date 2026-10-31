import Foundation

/// 后端 `error.code` 的已知集合（以 `english-coach/web` 实际抛出的 code 为准）。
/// 未知 code 不会被丢弃到“未知错误”里看不到内容——message 仍会展示。
enum ServerErrorCode: Sendable, Equatable {
    case badRequest
    case unauthorized
    case forbidden
    case notFound
    case unsupportedAudio
    case audioTooLong
    case payloadTooLarge
    case providerError
    case providerTimeout
    case providerUnavailable
    case audioNotFound
    case audioGone
    case sessionClosed
    case blindTestClosed
    case dailyLimitReached
    case tooManyRequests
    case conflict
    case noAttempts
    case noAudio
    case internalError
    case unknown

    init(rawCode: String?) {
        switch rawCode ?? "" {
        case "bad_request": self = .badRequest
        case "unauthorized": self = .unauthorized
        case "forbidden": self = .forbidden
        case "not_found": self = .notFound
        case "unsupported_audio": self = .unsupportedAudio
        case "audio_too_long": self = .audioTooLong
        case "payload_too_large": self = .payloadTooLarge
        case "provider_error": self = .providerError
        case "provider_timeout": self = .providerTimeout
        case "provider_unavailable", "no_provider", "voice_unreachable": self = .providerUnavailable
        case "audio_not_found": self = .audioNotFound
        case "audio_gone": self = .audioGone
        case "session_closed": self = .sessionClosed
        case "blind_test_closed": self = .blindTestClosed
        case "daily_limit_reached": self = .dailyLimitReached
        case "too_many_requests": self = .tooManyRequests
        case "conflict": self = .conflict
        case "no_attempts": self = .noAttempts
        case "no_audio": self = .noAudio
        case "internal_error": self = .internalError
        default: self = .unknown
        }
    }
}

/// 全 App 唯一的网络错误类型。页面不得自造网络错误文案，
/// 统一通过 `userMessage(forChild:)` 取中文（成人 / 儿童两套）。
enum APIError: Error, Equatable, Sendable {
    /// 连接/超时/DNS 等客户端侧失败；不是“未登录”。
    case transport(URLError.Code)
    /// 刷新后仍 401：会话失效，需要重新登录。
    case unauthorized
    /// 403：角色无权（例如孩子访问家长接口），不登出。
    case forbidden
    case server(code: ServerErrorCode, message: String?, status: Int)
    /// 契约漂移；需要看服务端返回体，不能当网络错误重试。
    case decoding(path: String)
    /// 客户端在提交前拦截的超限（不依赖服务端 413）。
    case payloadTooLarge(localBytes: Int)
    case cancelled
    case invalidBaseURL
    /// Keychain 写入失败等凭据存储问题。
    case credentialStorage

    var isCancelled: Bool {
        if case .cancelled = self { return true }
        return false
    }

    var isUnauthorized: Bool {
        if case .unauthorized = self { return true }
        return false
    }

    /// 是否值得给“重试”按钮。401/403/格式错误重试没有意义。
    var canRetry: Bool {
        switch self {
        case .transport, .payloadTooLarge:
            return true
        case .server(let code, _, _):
            switch code {
            case .providerError, .providerTimeout, .providerUnavailable,
                 .internalError, .unknown, .tooManyRequests:
                return true
            default:
                return false
            }
        case .decoding, .unauthorized, .forbidden, .cancelled, .invalidBaseURL, .credentialStorage:
            return false
        }
    }

    func userMessage(forChild isChild: Bool) -> String {
        switch self {
        case .transport(let code):
            switch code {
            case .notConnectedToInternet, .networkConnectionLost:
                return isChild ? "先连上家里的 Wi-Fi 再玩哦" : "网络不可用，请检查是否连接到家里的 Wi-Fi"
            case .cannotFindHost, .cannotConnectToHost, .timedOut, .dnsLookupFailed:
                return isChild
                    ? "服务器睡着了，叫爸爸妈妈看一下"
                    : "连不上学习服务器（NAS 可能未开机，或手机不在同一网络）"
            case .cancelled:
                return ""
            default:
                return isChild ? "网络打了个盹，再试一次" : "网络出了点问题，请重试"
            }

        case .unauthorized:
            return isChild ? "需要重新登录" : "登录已过期，请重新登录"

        case .forbidden:
            return isChild ? "这个功能现在不能玩" : "当前账号无权访问该功能"

        case .server(let code, let message, _):
            switch code {
            case .badRequest:
                return isChild ? "这一句没准备好，再试一次" : "提交的内容不完整，请重试"
            case .unsupportedAudio:
                return isChild ? "没听清，再录一次" : "音频格式不受支持，请重新录制"
            case .audioTooLong:
                return isChild ? "说得太久啦，短一点再试" : "录音太长了，请控制在 60 秒内"
            case .payloadTooLarge:
                return isChild ? "说得太久啦，短一点再试" : "录音文件太大，请重录"
            case .providerTimeout:
                return isChild ? "服务器有点慢，再试一次" : "评测服务响应超时，请重试"
            case .providerUnavailable:
                return isChild ? "现在不能评分，先听一听吧" : "语音服务暂时不可用，稍后再试"
            case .providerError:
                return isChild ? "出了点小问题，再试一次" : "服务处理失败，请重试（若持续失败请联系家长）"
            case .audioNotFound, .audioGone:
                return isChild ? "录音找不到了" : "找不到这段录音，可能已被清理"
            case .sessionClosed:
                return isChild ? "这个场景结束啦，换一个吧" : "这段对话已经结束了，换个场景继续吧"
            case .blindTestClosed:
                return isChild ? "这一轮结束啦" : "这次盲测已经结束了"
            case .dailyLimitReached:
                return message ?? (isChild ? "今天的练习时间到啦，明天再来吧" : "今天的练习时长已达上限")
            case .tooManyRequests:
                return message ?? (isChild ? "先休息一下，等会儿再试" : "尝试次数太多，请稍后再试")
            case .internalError:
                return isChild ? "服务器打了个嗝，等一下再试" : "服务器内部错误，请稍后再试"
            case .notFound:
                return isChild ? "这个东西找不到啦" : "请求的内容不存在"
            case .noAttempts, .noAudio, .conflict, .unknown, .unauthorized, .forbidden:
                return message ?? (isChild ? "出了点小问题，再试一次" : "请求失败，请重试")
            }

        case .decoding:
            return isChild ? "需要爸爸妈妈更新一下 App" : "版本不匹配，请更新 App（并告知家长）"

        case .payloadTooLarge:
            return isChild ? "说得太久啦，短一点再试" : "录音文件太大，请重录"

        case .cancelled:
            return ""

        case .invalidBaseURL:
            return "服务器地址不正确，请填写以 https:// 开头、包含 /api 的地址"

        case .credentialStorage:
            return isChild ? "登录状态没保存好，再试一次" : "无法安全保存登录状态，请重试"
        }
    }

    func primaryActionTitle(forChild isChild: Bool) -> String {
        switch self {
        case .unauthorized:
            return "重新登录"
        case .server(let code, _, _):
            switch code {
            case .unsupportedAudio, .audioTooLong, .payloadTooLarge, .audioNotFound, .audioGone:
                return isChild ? "再录一次" : "重新录制"
            default:
                return isChild ? "再试一次" : "重试"
            }
        case .transport, .decoding, .credentialStorage:
            return isChild ? "再试一次" : "重试"
        default:
            return isChild ? "再试一次" : "重试"
        }
    }
}
