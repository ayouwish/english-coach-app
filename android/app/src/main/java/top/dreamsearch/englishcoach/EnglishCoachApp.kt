package top.dreamsearch.englishcoach

import android.app.Application
import top.dreamsearch.englishcoach.core.di.AppGraph

/**
 * 进程入口：只负责初始化依赖图（等价 hos 的 EntryAbility + AppConfig.init + CacheService.cleanupOnBoot）。
 */
class EnglishCoachApp : Application() {
    override fun onCreate() {
        super.onCreate()
        AppGraph.init(this)
    }
}
