package top.dreamsearch.englishcoach.core.di

import android.content.Context
import top.dreamsearch.englishcoach.core.audio.AudioController
import top.dreamsearch.englishcoach.core.audio.VoicePrefs
import top.dreamsearch.englishcoach.core.config.AppConfig
import top.dreamsearch.englishcoach.core.content.CapabilityCache
import top.dreamsearch.englishcoach.core.net.ApiClient
import top.dreamsearch.englishcoach.core.offline.PendingUploadQueue
import top.dreamsearch.englishcoach.core.service.AccountService
import top.dreamsearch.englishcoach.core.service.AuthService
import top.dreamsearch.englishcoach.core.service.ChatService
import top.dreamsearch.englishcoach.core.service.DictionaryService
import top.dreamsearch.englishcoach.core.service.FlowService
import top.dreamsearch.englishcoach.core.service.PracticeService
import top.dreamsearch.englishcoach.core.service.StatsService
import top.dreamsearch.englishcoach.core.service.StoryService
import top.dreamsearch.englishcoach.core.session.CredentialStore
import top.dreamsearch.englishcoach.core.session.SessionStore
import top.dreamsearch.englishcoach.core.session.TokenStore
import top.dreamsearch.englishcoach.core.storage.AppPrefs
import top.dreamsearch.englishcoach.core.storage.CacheStore

/**
 * 依赖图（手写 DI，不引入 Hilt：依赖少、可读性高，与 hos 的静态服务风格一致）。
 *
 * 约定：**服务全部无状态、可安全共享**；页面状态放各自 ViewModel。
 */
class AppContainer(context: Context) {

    private val appContext: Context = context.applicationContext

    val prefs = AppPrefs(appContext)
    val config = AppConfig(prefs)
    val tokenStore = TokenStore(appContext)
    val credentials = CredentialStore(appContext)
    val cache = CacheStore(appContext)
    val api = ApiClient(config, tokenStore)

    // ---- 认证与服务（构造签名见 android/CONTRACT.md；数据层必须严格照此实现）----
    val auth: AuthService by lazy { AuthService(api) }
    val session: SessionStore by lazy { SessionStore(config, tokenStore, cache, credentials, auth) }
    val practice: PracticeService by lazy { PracticeService(api) }
    val flow: FlowService by lazy { FlowService(api) }
    val chat: ChatService by lazy { ChatService(api) }
    val story: StoryService by lazy { StoryService(api) }
    val account: AccountService by lazy { AccountService(api) }
    val stats: StatsService by lazy { StatsService(api) }
    val dictionary: DictionaryService by lazy { DictionaryService(api) }

    // ---- 能力开关（image/ocr/avatar_presets…，来自 /health 的 features + capabilities）----
    val capability: CapabilityCache by lazy { CapabilityCache(api) }

    // ---- 账号语音偏好本机镜像（示范音/对话朗读用；设置页 PATCH 后同步）----
    val voicePrefs: VoicePrefs by lazy { VoicePrefs(prefs) }

    // ---- 离线：TTS/回放 LRU 与"待重试录音队列"----
    val pendingUploads: PendingUploadQueue by lazy { PendingUploadQueue(appContext, cache) }

    // ---- 音频（录音 / 播放 / TTS 缓存）----
    val audio: AudioController by lazy { AudioController(appContext) }

    val appContextRef: Context get() = appContext

    init {
        cache.cleanupOnBoot()
    }
}

/** 全局句柄：`AppGraph.container.xxx` 或 `AppGraph.session`。 */
object AppGraph {
    @Volatile
    private var _container: AppContainer? = null

    val container: AppContainer
        get() = _container ?: error("AppGraph 未初始化：确认 EnglishCoachApp.onCreate() 已执行")

    val session: SessionStore get() = container.session
    val config: AppConfig get() = container.config
    val cache: CacheStore get() = container.cache
    val audio: AudioController get() = container.audio

    fun init(context: Context) {
        if (_container == null) {
            synchronized(this) {
                if (_container == null) _container = AppContainer(context)
            }
        }
    }
}
