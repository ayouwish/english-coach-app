import { ApiError, ApiErrorCode } from '../net/ApiError';

/**
 * 用户可见的错误（页面只渲染这个，不直接看 HTTP code）。
 * `code` 仅用于日志/测试；`message` 是中文、可执行；`actionLabel` 为空表示无动作。
 */
export class UiError {
  title: string = '';
  message: string = '';
  actionLabel: string = '';
  retryable: boolean = false;
  code: string = '';

  constructor(title: string, message: string, actionLabel: string, retryable: boolean, code: string) {
    this.title = title;
    this.message = message;
    this.actionLabel = actionLabel;
    this.retryable = retryable;
    this.code = code;
  }

  static of(code: string, message: string, retryable: boolean): UiError {
    return new UiError('', message, retryable ? '重试' : '', retryable, code);
  }
}

/**
 * 错误 → 中文文案（成人 / 儿童两套）。
 *
 * 规则（docs/architecture.md §6）：
 * - 服务端 `error.message` 已经是中文，优先直接用；
 * - 没有 message 时用本表兜底；
 * - 儿童版更短、更口语，不出现「错误/失败/权限/token」等词。
 */
export class ErrorMapper {
  static from(err: Error, isChild: boolean): UiError {
    if (err instanceof ApiError) {
      return ErrorMapper.fromApiError(err, isChild);
    }
    return new UiError('', isChild ? '刚才没成功，再试一次吧' : '操作没有完成，请重试', '重试', true, 'unknown');
  }

  private static fromApiError(err: ApiError, isChild: boolean): UiError {
    const code = err.code;
    const serverMessage = err.detail;
    const fallback = ErrorMapper.messageFor(code, isChild);
    // 服务端消息优先（后端文案已面向用户）；本地错误（status 0）用兜底文案
    const message = (err.status > 0 && serverMessage.length > 0 && !ErrorMapper.isNetworkCode(code))
      ? serverMessage
      : fallback;
    const retryable = err.retryable;
    return new UiError(ErrorMapper.titleFor(code, isChild), message,
      retryable ? (isChild ? '再试一次' : '重试') : '', retryable, code);
  }

  private static isNetworkCode(code: string): boolean {
    return code === ApiErrorCode.NETWORK_UNREACHABLE
      || code === ApiErrorCode.TIMEOUT
      || code === ApiErrorCode.CLEARTEXT_BLOCKED
      || code === ApiErrorCode.BAD_RESPONSE
      || code === ApiErrorCode.INTERNAL_ERROR;
  }

  private static titleFor(code: string, isChild: boolean): string {
    if (code === ApiErrorCode.NETWORK_UNREACHABLE) {
      return isChild ? '连不上家里的网' : '连不上家庭 NAS';
    }
    if (code === ApiErrorCode.TIMEOUT) {
      return isChild ? '等太久啦' : '请求超时';
    }
    if (code === ApiErrorCode.UNAUTHORIZED) {
      return isChild ? '要重新登录了' : '登录已过期';
    }
    if (code === ApiErrorCode.MIC_DENIED) {
      return isChild ? '还听不到你说话' : '需要麦克风权限';
    }
    if (code === ApiErrorCode.PROVIDER_ERROR || code === ApiErrorCode.PROVIDER_UNAVAILABLE) {
      return isChild ? '评分老师休息一下' : '评测服务暂不可用';
    }
    return '';
  }

  /** code → 中文兜底文案（服务端 message 缺失时使用）。 */
  static messageFor(code: string, isChild: boolean): string {
    if (code === ApiErrorCode.BAD_REQUEST) {
      return isChild ? '好像有点不对，再试一次吧' : '请求参数不对，请检查后重试';
    }
    if (code === ApiErrorCode.UNAUTHORIZED) {
      return isChild ? '请重新登录一下' : '登录已过期，请重新登录';
    }
    if (code === ApiErrorCode.FORBIDDEN) {
      return isChild ? '这个要爸爸妈妈才能用哦' : '你没有权限访问这个功能';
    }
    if (code === ApiErrorCode.NOT_FOUND) {
      return isChild ? '这个内容不见了' : '内容不在了，刷新看看';
    }
    if (code === ApiErrorCode.AUDIO_NOT_FOUND) {
      return isChild ? '这段录音找不到了' : '这条录音找不到了，可能已过期';
    }
    if (code === ApiErrorCode.AUDIO_GONE) {
      return isChild ? '录音不见了，再录一次吧' : '录音文件已不存在，请重新录制';
    }
    if (code === ApiErrorCode.PAYLOAD_TOO_LARGE) {
      return isChild ? '这句话太长啦，说短一点' : '文件太大了（录音上限 12MB），请缩短后重试';
    }
    if (code === ApiErrorCode.DAILY_LIMIT_REACHED) {
      return isChild ? '今天已经练得很棒啦，明天再来 🌙' : '今天的练习时长已达上限，明天再来';
    }
    if (code === ApiErrorCode.TOO_MANY_REQUESTS) {
      return isChild ? '试得有点快，等一下再试吧' : '尝试次数过多，请稍后再试';
    }
    if (code === ApiErrorCode.CONTENT_UNSAFE) {
      return isChild ? '这个我们换个说法吧' : '内容未通过审核，请换一种表达';
    }
    if (code === ApiErrorCode.INTERNAL_ERROR) {
      return isChild ? '服务器打了个盹，再试一次吧' : '服务器开小差了，稍后再试';
    }
    if (code === ApiErrorCode.PROVIDER_ERROR) {
      return isChild ? '评分老师有点忙，录音先存好啦' : '语音服务暂时不可用；录音已保存，稍后可重试';
    }
    if (code === ApiErrorCode.PROVIDER_UNAVAILABLE) {
      return isChild ? '这个功能还没开，换一种方式吧' : '该能力当前未启用，请稍后再试';
    }
    if (code === ApiErrorCode.PROVIDER_TIMEOUT) {
      return isChild ? '等太久啦，再试一次吧' : '上游服务超时，请重试';
    }
    if (code === ApiErrorCode.NETWORK_UNREACHABLE) {
      return isChild
        ? '检查一下是不是连着家里的 Wi-Fi'
        : '连不上家里的服务器，请确认连着家庭 Wi-Fi（该域名只在家庭网络可达）';
    }
    if (code === ApiErrorCode.TIMEOUT) {
      return isChild ? '网络有点慢，再试一次吧' : '请求超时了，网络有点慢，请重试';
    }
    if (code === ApiErrorCode.CLEARTEXT_BLOCKED) {
      return '当前网络不允许明文 HTTP，请改用 https 地址';
    }
    if (code === ApiErrorCode.MIC_DENIED) {
      return isChild ? '要听到你的声音，需要打开麦克风' : '需要麦克风才能练习，请在设置里允许';
    }
    if (code === ApiErrorCode.MIC_UNAVAILABLE) {
      return isChild ? '麦克风被别人占用了，等一下再试' : '麦克风被占用了，请关闭其他录音应用后重试';
    }
    if (code === ApiErrorCode.RECORD_FAILED) {
      return isChild ? '录音没有成功，再试一次吧' : '录音失败，请重试（或重启 App）';
    }
    if (code === ApiErrorCode.RECORD_TOO_SHORT) {
      return isChild ? '这次录得太短啦，把句子读完再点完成' : '录音太短（少于 0.6 秒），请读完整句后重试';
    }
    if (code === ApiErrorCode.RECORD_TOO_LARGE) {
      return isChild ? '这句话太长啦，短一点好吗' : '录音超过 12MB，请缩短录音';
    }
    if (code === ApiErrorCode.PLAYBACK_FAILED) {
      return isChild ? '声音没有播出来，再点一次吧' : '声音播放失败，请再试一次';
    }
    if (code === ApiErrorCode.CACHE_CORRUPT) {
      return isChild ? '声音文件有点问题，重新下载一次' : '缓存文件损坏，已重新下载';
    }
    if (code === ApiErrorCode.BAD_RESPONSE) {
      return isChild ? '没听懂服务器说什么，再试一次吧' : '服务器返回格式异常，请重试';
    }
    if (code === ApiErrorCode.BAD_BASE_URL) {
      return '服务器地址格式不对，示例：https://english.dreamsearch.top';
    }
    return isChild ? '刚才没成功，再试一次吧' : '操作没有完成，请重试';
  }
}
